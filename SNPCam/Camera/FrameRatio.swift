import CoreGraphics
import Foundation

/// 이 앱이 지원하는 두 가지 프레임 — 둘 다 필름 시절 비율. 16:9 같은 다른 비율은 의도적으로 없다.
enum FrameRatio: String, CaseIterable, Identifiable {
    /// 5:5 정사각 — 기본 프레임 (중형 6×6 필름)
    case square
    /// 3:2 — 35mm 필름 한 컷 (36×24mm). 4:3 센서의 긴 변은 그대로 두고 짧은 변을 잘라 쓴다
    /// (세로 방향에서는 2:3)
    case threeTwo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square:   return "5:5"
        case .threeTwo: return "3:2"
        }
    }

    /// 세로 방향 기준 가로/세로 비
    var aspect: CGFloat {
        switch self {
        case .square:   return 1.0
        case .threeTwo: return 2.0 / 3.0
        }
    }

    /// 저장 해상도 — 흉내내는 기종의 4:3 센서(긴 변 sensorLongSide)에서 잘라낸 크기
    /// (5s = 8MP 3264×2448 → 5:5 2448², 3:2 2176×3264 / 6s = 12MP 4032×3024 → 5:5 3024², 3:2 2688×4032)
    func outputSize(sensorLongSide: CGFloat) -> CGSize {
        switch self {
        case .square:
            let short = (sensorLongSide * 3 / 4).rounded()
            return CGSize(width: short, height: short)
        case .threeTwo:
            return CGSize(width: (sensorLongSide * 2 / 3).rounded(), height: sensorLongSide)
        }
    }

    func next() -> FrameRatio {
        self == .square ? .threeTwo : .square
    }
}
