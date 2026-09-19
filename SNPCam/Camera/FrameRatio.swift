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

    /// 저장 해상도 — iPhone 5s/6s 의 8MP(3264×2448) 센서에 맞춘 크기
    var outputSize: CGSize {
        switch self {
        case .square:    return CGSize(width: 2448, height: 2448)
        case .fourThree: return CGSize(width: 2448, height: 3264)
        }
    }

    func next() -> FrameRatio {
        self == .square ? .fourThree : .square
    }
}
