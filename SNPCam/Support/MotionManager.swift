import Combine
import CoreMotion
import Foundation

/// 수평계용 — 기기의 좌우 기울기(롤)만 사용한다.
final class MotionManager: ObservableObject {

    @Published private(set) var rollDegrees: Double = 0
    /// ±1° 이내면 수평
    var isLevel: Bool { abs(rollDegrees) < 1.0 }

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
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
