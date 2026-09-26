import AVFoundation
import Foundation

/// 렌즈 하나짜리 옛날 아이폰처럼 — 요즘 아이폰의 초광각·망원·가상 멀티카메라는 쓰지 않고
/// 메인 광각 물리 렌즈 하나만 고른 뒤, 화각을 iPhone 5s~6s 에 맞춘다.
enum LegacyLens {

    /// 35mm 환산 초점거리 — iPhone 6 / 6s 후면 29mm, 전면 FaceTime HD 31mm.
    /// 요즘 메인 카메라(24~26mm)는 더 넓어서, 가운데를 디지털로 잘라 이 화각에 맞춘다.
    /// 후면은 룩마다 다를 수 있다 (FILM = Leica minilux zoom 의 35mm).
    static let backFocalLength: Double = 29
    static let frontFocalLength: Double = 31

    /// 풀프레임(36×24mm) 대각선의 절반
    private static let fullFrameHalfDiagonal: Double = 21.633

    /// 물리 광각 렌즈 하나. `.builtInTripleCamera` 같은 가상 장치는 줌/접사 때
    /// 렌즈를 알아서 바꾸므로 절대 쓰지 않는다.
    static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                         mediaType: .video,
                                         position: position).devices.first
    }

    /// 앱 전체에 한 번 — 전면 카메라가 얼굴을 따라 알아서 프레이밍하는 센터 스테이지를 끈다.
    static func disableAutoFraming() {
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
    }

    /// 활성 포맷 기준으로 목표 화각을 맞춘다. 세션 프리셋·렌즈가 바뀔 때마다 다시 호출해야 한다.
    /// - Note: `lockForConfiguration` 은 호출하는 쪽에서 잡는다.
    static func applyFieldOfView(to device: AVCaptureDevice,
                                 backFocal: Double = LegacyLens.backFocalLength) {
        let focal = device.position == .front ? frontFocalLength : backFocal
        let format = device.activeFormat
        let fov = Double(format.videoFieldOfView) * .pi / 180
        guard fov > 0 else { return }

        // videoFieldOfView 는 포맷 긴 변의 화각. 16:9 포맷이면 4:3 으로 잘라 쓰는 폭으로 환산한다.
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        var halfTan = tan(fov / 2)
        if dims.height > 0 {
            let formatAspect = Double(dims.width) / Double(dims.height)
            if formatAspect > 4.0 / 3.0 { halfTan *= (4.0 / 3.0) / formatAspect }
        }

        // 4:3 프레임의 가로는 대각선의 0.8
        let targetHalfTan = 0.8 * fullFrameHalfDiagonal / focal
        let zoom = halfTan / targetHalfTan

        let upper = Double(format.videoMaxZoomFactor)
        device.videoZoomFactor = CGFloat(min(max(zoom, 1), upper))
    }

    /// 옛날 기기에 없던 비디오 HDR 을 끈다.
    /// - Note: `lockForConfiguration` 은 호출하는 쪽에서 잡는다.
    static func disableVideoHDR(on device: AVCaptureDevice) {
        guard device.activeFormat.isVideoHDRSupported else { return }
        device.automaticallyAdjustsVideoHDREnabled = false
        device.isVideoHDREnabled = false
    }
}
