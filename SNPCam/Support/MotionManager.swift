import Combine
import CoreMotion
import Foundation

/// 수평계용 기울기(롤) + 비디오 기록 방향. UI 가 세로 고정이라 기기 방향은 중력으로 직접 판단한다.
final class MotionManager: ObservableObject {

    @Published private(set) var rollDegrees: Double = 0
    /// ±1° 이내면 수평
    var isLevel: Bool { abs(rollDegrees) < 1.0 }

    @Published private(set) var captureOrientation: CaptureOrientation = .portrait

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let radians = atan2(g.x, -g.y)
            let degrees = radians * 180 / .pi
            // 살짝 스무딩
            self.rollDegrees += (degrees - self.rollDegrees) * 0.25
            self.updateOrientation(gravityX: g.x, gravityY: g.y)
        }
    }

    /// 45° 경계에서 깜빡이지 않도록 한쪽이 확실히 우세할 때만 바꾼다. 바닥에 눕히면 이전 방향 유지.
    private func updateOrientation(gravityX x: Double, gravityY y: Double) {
        let margin = 0.25
        let next: CaptureOrientation
        if y < -0.5, -y > abs(x) + margin {
            next = .portrait
        } else if abs(x) > 0.5, abs(x) > abs(y) + margin {
            // 기기 윗부분이 왼쪽 → 왼쪽 옆면이 바닥을 향하므로 중력 x 가 음수
            next = x < 0 ? .landscapeLeft : .landscapeRight
        } else {
            return
        }
        if next != captureOrientation { captureOrientation = next }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
