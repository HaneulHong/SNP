import AVFoundation
import AudioToolbox
import CoreImage
import Photos
import SwiftUI

final class CameraManager: NSObject, ObservableObject {

    // MARK: - 상태
    @Published private(set) var isSessionRunning = false
    @Published private(set) var setupFailed = false
    @Published private(set) var cameraDenied = false

    @Published private(set) var mode: CaptureMode = .photo

    @Published var ratio: FrameRatio = .square
    @Published var lookPreset: LookPreset = .film
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var timerSeconds: Int = 0
    @Published var showsGrid = false
    @Published var showsLevel = false

    @Published private(set) var camcorderPreset: CamcorderPreset = .dv
    @Published private(set) var showsDateStamp = true
    @Published private(set) var torchOn = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0

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
    /// 영상·소리 버퍼와 녹화기는 모두 이 직렬 큐에서만 다룬다
    private let videoQueue = DispatchQueue(label: "snpcam.video", qos: .userInitiated)

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var countdownTimer: Timer?
    private var recordingTimer: Timer?
    private var frameSeed: Double = 0

    /// 현재 룩 파라미터 (백그라운드 큐에서도 읽으므로 별도 저장)
    private var currentParams = LookParameters.film
    private var currentRatio: FrameRatio = .square
    private var currentMode: CaptureMode = .photo
    private var currentCamcorder = CamcorderParameters.dv
    private var currentShowsDate = true
    private var liveOrientation: CaptureOrientation = .portrait
    private var isFrontCamera = false

    /// 비디오 큐 전용
    private var recorder: VideoRecorder?
    private let dateStamp = DateStamp()

    override init() {
        super.init()
        currentParams = lookPreset.parameters
        currentRatio = ratio

        // 앱이 내려가거나 전화가 오면 녹화를 끊어서 파일이 깨지지 않게 한다
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stopRecordingIfNeeded),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stopRecordingIfNeeded),
                                               name: AVCaptureSession.wasInterruptedNotification,
                                               object: session)
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
        stopRecordingIfNeeded()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    private var isConfigured = false

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        LegacyLens.disableAutoFraming()

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = LegacyLens.device(for: .back),
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

        // 오디오 출력은 비디오 모드에서만 세션에 붙인다
        audioOutput.setSampleBufferDelegate(self, queue: videoQueue)

        photoOutput.maxPhotoQualityPrioritization = .quality
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()
        isConfigured = true

        configureConnections(front: false)
        configureLens(device)
        updateExposureRange(for: device)

        // 권한 대기 중에 비디오로 넘어갔을 수도 있다
        if currentMode == .video { applyModeConfiguration() }
    }

    private func startSession() {
        guard !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async { self.isSessionRunning = true }
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

    /// 렌즈 하나 고정 + 5s~6s 화각. 포맷이 바뀌면 줌이 풀리므로 세션을 건드릴 때마다 다시 건다.
    private func configureLens(_ device: AVCaptureDevice) {
        // 사진은 룩이 정한 화각 (FILM = 35mm), 비디오는 옛날 아이폰 29mm
        let focal = currentMode == .photo ? currentParams.focalLength : LegacyLens.backFocalLength
        do {
            try device.lockForConfiguration()
            LegacyLens.applyFieldOfView(to: device, backFocal: focal)
            LegacyLens.disableVideoHDR(on: device)
            device.unlockForConfiguration()
        } catch { }
    }

    // MARK: - 모드 (사진 / 비디오)

    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode, !isRecording else { return }
        cancelTimer()
        if torchOn { setTorch(false) }
        mode = newMode
        currentMode = newMode
        exposureBias = 0

        let apply = { [weak self] in
            guard let self else { return }
            self.sessionQueue.async { self.applyModeConfiguration() }
        }
        if newMode == .video, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in apply() }
        } else {
            apply()
        }
    }

    /// 사진: 고해상도 `.photo` 프리셋. 비디오: SD(640×480) 프리셋 + 마이크.
    /// 실행 시점의 `currentMode` 를 따르므로 여러 번 불려도 안전하다.
    private func applyModeConfiguration() {
        guard isConfigured else { return }
        let video = currentMode == .video

        session.beginConfiguration()
        if video {
            addAudioIfAuthorized()
            if session.canSetSessionPreset(.vga640x480) {
                session.sessionPreset = .vga640x480
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
        } else {
            removeAudio()
            session.sessionPreset = .photo
        }
        session.commitConfiguration()

        configureConnections(front: isFrontCamera)
        if let device = videoInput?.device {
            configureLens(device)
            updateExposureRange(for: device)
        }
    }

    private func addAudioIfAuthorized() {
        guard audioInput == nil,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else { return }
        session.addInput(input)
        audioInput = input
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
    }

    /// 사진 모드에선 마이크를 놓아서 상단 주황 점이 뜨지 않게 한다
    private func removeAudio() {
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
        if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
    }

    // MARK: - 설정 변경

    func syncLook() {
        currentParams = lookPreset.parameters
        currentRatio = ratio
    }

    func toggleRatio() {
        // 녹화 중에는 파일 크기가 정해져 있어서 비율을 바꿀 수 없다
        guard !isRecording else { return }
        ratio = ratio.next()
        currentRatio = ratio
    }

    func cycleLook() {
        let all = LookPreset.allCases
        if let i = all.firstIndex(of: lookPreset) {
            lookPreset = all[(i + 1) % all.count]
        }
        let focalChanged = currentParams.focalLength != lookPreset.parameters.focalLength
        currentParams = lookPreset.parameters

        // 룩마다 화각이 다르면 렌즈를 다시 맞춘다 (프리뷰도 같이 좁아진다)
        guard focalChanged else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            self.configureLens(device)
        }
    }

    func cycleCamcorder() {
        let all = CamcorderPreset.allCases
        if let i = all.firstIndex(of: camcorderPreset) {
            camcorderPreset = all[(i + 1) % all.count]
        }
        currentCamcorder = camcorderPreset.parameters
    }

    func toggleDateStamp() {
        showsDateStamp.toggle()
        currentShowsDate = showsDateStamp
    }

    func updateOrientation(_ orientation: CaptureOrientation) {
        liveOrientation = orientation
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

    func toggleTorch() {
        guard mode == .video, position == .back else { return }
        setTorch(!torchOn)
    }

    private func setTorch(_ on: Bool) {
        torchOn = on
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device, device.hasTorch else { return }
            let torchMode: AVCaptureDevice.TorchMode = on ? .on : .off
            guard device.isTorchModeSupported(torchMode) else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = torchMode
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func switchCamera() {
        guard !isRecording else { return }
        if torchOn { setTorch(false) }
        let target: AVCaptureDevice.Position = (position == .back) ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self,
                  let newDevice = LegacyLens.device(for: target),
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
            self.configureLens(newDevice)
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

        // 뷰 → 세로 프레임 전체 → 센서 좌표. 세로 버퍼는 3:4 라서
        // 더 넓은 비율(5:5)이면 위아래를, 더 좁은 비율(3:2)이면 좌우를 잘라 쓴다
        let bufferAspect: CGFloat = 3.0 / 4.0
        let fractionX = min(1, currentRatio.aspect / bufferAspect)
        let fractionY = min(1, bufferAspect / currentRatio.aspect)
        let pu = (1 - fractionX) / 2 + normalized.x * fractionX
        let pv = (1 - fractionY) / 2 + normalized.y * fractionY

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
        guard mode == .photo, !isCapturing, countdown == 0 else { return }
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

    // MARK: - 녹화

    func recordTapped() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard mode == .video, !isRecording else { return }
        isRecording = true
        recordingDuration = 0
        let startedAt = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.recordingDuration = Date().timeIntervalSince(startedAt)
        }
        AudioServicesPlaySystemSound(1117)

        // 녹화 중에는 방향을 고정한다 — 도중에 돌려도 파일은 처음 방향 그대로
        let orientation = liveOrientation
        let portrait = CamcorderLook.portraitSize(for: currentRatio)
        let size = orientation.isLandscape
            ? CGSize(width: portrait.height, height: portrait.width)
            : portrait

        // 시작·정지 모두 세션 큐 → 비디오 큐 순서로 보내서, 빨리 눌러도 순서가 뒤집히지 않게 한다
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let audioSettings = self.audioInput == nil ? nil : self.makeAudioSettings()
            self.videoQueue.async {
                self.recorder = VideoRecorder(size: size,
                                              orientation: orientation,
                                              audioSettings: audioSettings,
                                              context: self.renderer.ciContext)
                if self.recorder == nil {
                    DispatchQueue.main.async { self.endRecordingUI() }
                }
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        endRecordingUI()

        sessionQueue.async { [weak self] in
            self?.videoQueue.async {
                guard let self, let recorder = self.recorder else { return }
                self.recorder = nil
                recorder.finish { url, thumbnail in
                    if let url { PhotoSaver.save(videoAt: url) }
                    DispatchQueue.main.async {
                        AudioServicesPlaySystemSound(1118)
                        if let thumbnail { self.lastThumbnail = thumbnail }
                    }
                }
            }
        }
    }

    @objc private func stopRecordingIfNeeded() {
        DispatchQueue.main.async {
            if self.isRecording { self.stopRecording() }
        }
    }

    private func endRecordingUI() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        recordingDuration = 0
    }

    /// 입력 포맷에 맞춘 AAC. 세션 큐에서 호출한다.
    private func makeAudioSettings() -> [String: Any] {
        if let recommended = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) {
            return recommended
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000
        ]
    }
}

// MARK: - 실시간 프리뷰 / 녹화 프레임

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        if output === audioOutput {
            recorder?.appendAudio(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        frameSeed += 1

        if currentMode == .video {
            renderCamcorderFrame(image, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            return
        }

        let cropped = PhotoProcessor.centerCrop(image, aspect: currentRatio.aspect)
        let looked = RetroLook.apply(to: cropped,
                                     params: currentParams,
                                     quality: .preview,
                                     seed: frameSeed)
        renderer.enqueue(looked)
    }

    /// 룩을 입힌 한 장을 파일과 프리뷰에 똑같이 쓴다 (보이는 그대로 기록)
    private func renderCamcorderFrame(_ image: CIImage, at time: CMTime) {
        let orientation = recorder?.orientation ?? liveOrientation

        var frame = PhotoProcessor.centerCrop(image, aspect: currentRatio.aspect)
        frame = PhotoProcessor.resize(frame, to: CamcorderLook.portraitSize(for: currentRatio))
        // 가로로 들었으면 세상 기준으로 세워서 룩·스탬프를 입힌다
        frame = orientation.upright(frame)

        let stamp = currentShowsDate ? dateStamp.image(for: Date(), in: frame.extent) : nil
        let looked = CamcorderLook.apply(to: frame, params: currentCamcorder, stamp: stamp)

        recorder?.appendVideo(looked, at: time)
        renderer.enqueue(orientation.backToPortrait(looked))
    }
}
