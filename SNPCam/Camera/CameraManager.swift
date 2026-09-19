import AVFoundation
import CoreImage
import Photos
import SwiftUI

final class CameraManager: NSObject, ObservableObject {

    // MARK: - 상태
    @Published private(set) var isSessionRunning = false
    @Published private(set) var setupFailed = false
    @Published private(set) var cameraDenied = false

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
        guard !isCapturing, countdown == 0 else { return }
        guard timerSeconds > 0 else {
            capture()
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
                self.capture()
            }
        }
    }

    func cancelTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 0
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

// MARK: - 실시간 프리뷰

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = PhotoProcessor.centerCrop(image, aspect: currentRatio.aspect)

        frameSeed += 1
        let looked = RetroLook.apply(to: image,
                                     params: currentParams,
                                     quality: .preview,
                                     seed: frameSeed)
        renderer.enqueue(looked)
    }
}
