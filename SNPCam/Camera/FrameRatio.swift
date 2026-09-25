import CoreGraphics
import Foundation

/// 이 앱이 지원하는 두 가지 프레임. 16:9 같은 다른 비율은 의도적으로 없다.
enum FrameRatio: String, CaseIterable, Identifiable {
    /// 5:5 정사각 — 기본 프레임
    case square
    /// 센서 전체를 쓰는 4:3 (세로 방향에서는 3:4)
    case fourThree

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square:    return "5:5"
        case .fourThree: return "4:3"
        }
    }

    /// 세로 방향 기준 가로/세로 비
    var aspect: CGFloat {
        switch self {
        case .square:    return 1.0
        case .fourThree: return 3.0 / 4.0
        }
    }

    /// 저장 해상도 — 긴 변을 흉내내는 기종의 4:3 센서에 맞춘 크기
    /// (5s = 8MP 3264×2448, 6s = 12MP 4032×3024)
    func outputSize(sensorLongSide: CGFloat) -> CGSize {
        let short = (sensorLongSide * 3 / 4).rounded()
        switch self {
        case .square:    return CGSize(width: short, height: short)
        case .fourThree: return CGSize(width: short, height: sensorLongSide)
        }
    }

    /// 비디오 해상도 — 5s 의 1080p 급. 가로 1080 에 비율만 바꾼다.
    var videoSize: CGSize {
        switch self {
        case .square:    return CGSize(width: 1080, height: 1080)
        case .fourThree: return CGSize(width: 1080, height: 1440)
        }
    }

    func next() -> FrameRatio {
        self == .square ? .fourThree : .square
    }
}
