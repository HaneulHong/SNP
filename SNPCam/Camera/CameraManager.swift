import AVFoundation
import CoreImage
import Photos
import SwiftUI

/// 기본 카메라의 "사진 / 비디오" 모드
enum CaptureMode {
    case photo
    case video
}

final class CameraManager: NSObject, ObservableObject {

    // MARK: - 상태
    @Published private(set) var isSessionRunning = false
    @Published private(set) var setupFailed = false
    @Published private(set) var cameraDenied = false

    @Published private(set) var captureMode: CaptureMode = .photo
    @Published var ratio: FrameRatio = .square
    @Published var lookPreset: LookPreset = .standard
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var timerSeconds: Int = 0
    @Published var showsGrid = false
    @Published var showsLevel = false

    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var isCapturing = false
    @Published private(set) var countdown = 0
    @Published private(set) var lastThumbnail: UIImage?
    @Published private(set) var shutterFlash = false
    /// 녹화 중이면 시작 시각, 아니면 nil
    @Published private(set) var recordingStartedAt: Date?

    var isRecording: Bool { recordingStartedAt != nil }

    /// 탭 포커스 표시용 (뷰 좌표계)
    @Published var focusIndicator: FocusIndicator?

    @Published var exposureBias: Float = 0 {
        didSet { applyExposureBias() }
    }
    @Published private(set) var exposureRange: ClosedRange<Float> = -2...2

    struct FocusIndicator: Equatable {
        let point: CGPoint
        let id: UUID
    }

    // MARK: - AVFoundation
    let renderer = PreviewRenderer()

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "snpcam.session")
    private let videoQueue = DispatchQueue(label: "snpcam.video", qos: .userInitiated)

    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    /// 비디오 모드에서만 붙인다 — 사진 모드에서 마이크 표시등이 켜지지 않게 (sessionQueue 전용)
    private var micInput: AVCaptureDeviceInput?
    private var wantsMicrophone = false

    /// 녹화 중인 파일 (videoQueue 전용)
    private var recorder: VideoRecorder?

    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var countdownTimer: Timer?
    private var frameSeed: Double = 0

    /// 현재 룩 파라미터 (백그라운드 큐에서도 읽으므로 별도 저장)
    private var currentParams = LookParameters.standard
    private var currentRatio: FrameRatio = .square
    private var isFrontCamera = false

    override init() {
        super.init()
        currentParams = lookPreset.parameters
        currentRatio = ratio
    }

    // MARK: - 라이프사이클

    func onAppear() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.cameraDenied = true }
                return
            }
            self.sessionQueue.async {
                self.configureSessionIfNeeded()
                self.startSession()
            }
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }

    func onDisappear() {
        stopRecording()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    private var isConfigured = false

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.device(for: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.setupFailed = true }
            return
        }
        session.addInput(input)
        videoInput = input

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        photoOutput.maxPhotoQualityPrioritization = .quality
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()

        configureConnections(front: false)
        updateExposureRange(for: device)
        isConfigured = true
    }

    private func startSession() {
        guard !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async { self.isSessionRunning = true }
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types,
                                                mediaType: .video,
                                                position: position).devices.first
    }

    /// 세로 고정 + 전면 미러링
    private func configureConnections(front: Bool) {
        for output in [videoOutput as AVCaptureOutput, photoOutput as AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
        }
        if let device = videoInput?.device,
           let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.last {
            session.beginConfiguration()
            photoOutput.maxPhotoDimensions = maxDimensions
            session.commitConfiguration()
        }
    }

    // MARK: - 설정 변경

    func syncLook() {
        currentParams = lookPreset.parameters
        currentRatio = ratio
    }

    func toggleRatio() {
        guard !isRecording else { return }
        ratio = ratio.next()
        currentRatio = ratio
    }

    func cycleLook() {
        let all = LookPreset.allCases
        if let i = all.firstIndex(of: lookPreset) {
            lookPreset = all[(i + 1) % all.count]
        }
        currentParams = lookPreset.parameters
    }

    func setCaptureMode(_ mode: CaptureMode) {
        guard mode != captureMode, !isRecording, countdown == 0 else { return }
        captureMode = mode

        let wants = (mode == .video)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsMicrophone = wants
            if !wants { self.detachMicrophone() }
        }
        guard wants else { return }

        // 권한이 없으면 소리 없이 녹화한다
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted, let self else { return }
            self.sessionQueue.async {
                // 권한 창이 떠 있는 동안 사진 모드로 돌아갔을 수 있다
                guard self.wantsMicrophone else { return }
                self.attachMicrophone()
            }
        }
    }

    private func attachMicrophone() {
        guard micInput == nil,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
            micInput = input
        }
        if !session.outputs.contains(where: { $0 === audioOutput }),
           session.canAddOutput(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(audioOutput)
        }
        session.commitConfiguration()
    }

    private func detachMicrophone() {
        guard let input = micInput else { return }
        session.beginConfiguration()
        session.removeInput(input)
        if session.outputs.contains(where: { $0 === audioOutput }) {
            session.removeOutput(audioOutput)
        }
        session.commitConfiguration()
        micInput = nil
    }

    func cycleFlash() {
        switch flashMode {
        case .off:  flashMode = .auto
        case .auto: flashMode = .on
        default:    flashMode = .off
        }
    }

    func cycleTimer() {
        switch timerSeconds {
        case 0:  timerSeconds = 3
        case 3:  timerSeconds = 10
        default: timerSeconds = 0
        }
    }

    func switchCamera() {
        guard !isRecording else { return }
        let target: AVCaptureDevice.Position = (position == .back) ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self,
                  let newDevice = Self.device(for: target),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
            } else if let old = self.videoInput {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()

            let isFront = (target == .front)
            self.configureConnections(front: isFront)
            self.isFrontCamera = isFront
            self.updateExposureRange(for: newDevice)

            DispatchQueue.main.async {
                self.position = target
                self.exposureBias = 0
            }
        }
    }

    private func updateExposureRange(for device: AVCaptureDevice) {
        let lower = max(device.minExposureTargetBias, -3)
        let upper = min(device.maxExposureTargetBias, 3)
        guard upper > lower else { return }
        DispatchQueue.main.async { self.exposureRange = lower...upper }
    }

    private func applyExposureBias() {
        let bias = exposureBias
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(bias, device.minExposureTargetBias),
                                  device.maxExposureTargetBias)
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - 탭 포커스

    /// - Parameter normalized: 프리뷰 뷰 기준 정규화 좌표 (좌상단 0,0)
    func focus(atViewPoint normalized: CGPoint, viewPoint: CGPoint) {
        DispatchQueue.main.async {
            self.focusIndicator = FocusIndicator(point: viewPoint, id: UUID())
        }

        // 뷰 → 세로 프레임 전체 → 센서 좌표
        let cropFraction = currentRatio == .square ? (3.0 / 4.0) : 1.0
        let topInset = (1 - cropFraction) / 2
        let pu = normalized.x
        let pv = topInset + normalized.y * cropFraction

        let poi: CGPoint = isFrontCamera
            ? CGPoint(x: pv, y: pu)
            : CGPoint(x: pv, y: 1 - pu)

        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = poi
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = poi
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func resetFocus() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
        DispatchQueue.main.async {
            self.focusIndicator = nil
            self.exposureBias = 0
        }
    }

    // MARK: - 촬영

    func shutterTapped() {
        if isRecording {
            stopRecording()
            return
        }
        guard !isCapturing, countdown == 0 else { return }
        guard timerSeconds > 0 else {
            fire()
            return
        }
        countdown = timerSeconds
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.fire()
            }
        }
    }

    func cancelTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 0
    }

    private func fire() {
        switch captureMode {
        case .photo: capture()
        case .video: startRecording()
        }
    }

    private func capture() {
        isCapturing = true
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.18)) { self.shutterFlash = false }
        }

        let params = currentParams
        let ratio = currentRatio
        let mirrored = isFrontCamera
        let flash = flashMode

        sessionQueue.async { [weak self] in
            guard let self else { return }

            var settings = AVCapturePhotoSettings()
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            if self.photoOutput.supportedFlashModes.contains(flash) {
                settings.flashMode = flash
            }

            let delegate = PhotoCaptureDelegate(
                ratio: ratio,
                params: params,
                mirrored: mirrored,
                context: self.renderer.ciContext
            ) { [weak self] thumbnail in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isCapturing = false
                    if let thumbnail { self.lastThumbnail = thumbnail }
                }
                self.sessionQueue.async {
                    self.captureDelegates[settings.uniqueID] = nil
                }
            }

            self.captureDelegates[settings.uniqueID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - 녹화

extension CameraManager {

    private func startRecording() {
        let size = currentRatio.videoSize
        let torch = Self.torchMode(for: flashMode)
        recordingStartedAt = Date()

        // 시작·정지 모두 sessionQueue → videoQueue 순서로 보내서, 빠르게 연타해도 순서가 꼬이지 않는다
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorch(torch)
            let audioSettings = self.micInput == nil ? nil
                : self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]

            self.videoQueue.async {
                do {
                    self.recorder = try VideoRecorder(size: size,
                                                      audioSettings: audioSettings,
                                                      context: self.renderer.ciContext)
                } catch {
                    DispatchQueue.main.async { self.recordingStartedAt = nil }
                    self.sessionQueue.async { self.setTorch(.off) }
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recordingStartedAt = nil

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorch(.off)

            self.videoQueue.async {
                guard let recorder = self.recorder else { return }
                self.recorder = nil
                recorder.finish { url, thumbnail in
                    if let url { PhotoSaver.saveVideo(at: url) }
                    guard let thumbnail else { return }
                    DispatchQueue.main.async { self.lastThumbnail = thumbnail }
                }
            }
        }
    }

    /// 비디오에서는 플래시 버튼이 조명(토치)으로 동작한다 — 기본 카메라와 같다
    private static func torchMode(for flash: AVCaptureDevice.FlashMode) -> AVCaptureDevice.TorchMode {
        switch flash {
        case .on:   return .on
        case .auto: return .auto
        default:    return .off
        }
    }

    /// sessionQueue 에서 호출
    private func setTorch(_ mode: AVCaptureDevice.TorchMode) {
        guard let device = videoInput?.device,
              device.hasTorch,
              device.isTorchModeSupported(mode) else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch { }
    }
}

// MARK: - 실시간 프리뷰

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    /// 영상·소리 모두 videoQueue 로 들어온다
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        if output === audioOutput {
            recorder?.appendAudio(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = PhotoProcessor.centerCrop(image, aspect: currentRatio.aspect)

        frameSeed += 1

        // 녹화 중: 1080 급으로 줄인 뒤 저장본 품질로 룩을 입히고, 같은 프레임을 화면에도 띄운다
        if let recorder {
            image = PhotoProcessor.resize(image, to: recorder.size)
            let looked = RetroLook.apply(to: image,
                                         params: currentParams,
                                         quality: .full,
                                         seed: frameSeed)
            recorder.appendVideo(looked,
                                 at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            renderer.enqueue(looked)
            return
        }

        let looked = RetroLook.apply(to: image,
                                     params: currentParams,
                                     quality: .preview,
                                     seed: frameSeed)
        renderer.enqueue(looked)
    }
}
