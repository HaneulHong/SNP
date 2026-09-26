import CoreImage
import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case video
    case photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .video: return "비디오"
        case .photo: return "사진"
        }
    }
}

/// 촬영 시 기기를 든 방향. UI 는 세로 고정이지만 비디오는 가로로 들면 가로로 기록한다.
enum CaptureOrientation: Equatable {
    case portrait
    /// 기기 윗부분이 왼쪽 (홈 인디케이터가 오른쪽)
    case landscapeLeft
    /// 기기 윗부분이 오른쪽
    case landscapeRight

    var isLandscape: Bool { self != .portrait }

    /// 세로 버퍼 → 세상 기준으로 똑바로 선 이미지
    func upright(_ image: CIImage) -> CIImage {
        switch self {
        case .portrait:       return image
        case .landscapeLeft:  return Self.rotateCounterClockwise(image)
        case .landscapeRight: return Self.rotateClockwise(image)
        }
    }

    /// `upright` 의 역변환 — 세로 UI 프리뷰에 다시 얹을 때 쓴다
    func backToPortrait(_ image: CIImage) -> CIImage {
        switch self {
        case .portrait:       return image
        case .landscapeLeft:  return Self.rotateClockwise(image)
        case .landscapeRight: return Self.rotateCounterClockwise(image)
        }
    }

    // 회전 행렬을 정수로 직접 써서 extent 에 소수 오차가 생기지 않게 한다 (CI 좌표계는 y 가 위)
    private static func rotateCounterClockwise(_ image: CIImage) -> CIImage {
        let e = image.extent
        return image.transformed(by: CGAffineTransform(a: 0, b: 1, c: -1, d: 0,
                                                       tx: e.maxY, ty: -e.minX))
    }

    private static func rotateClockwise(_ image: CIImage) -> CIImage {
        let e = image.extent
        return image.transformed(by: CGAffineTransform(a: 0, b: -1, c: 1, d: 0,
                                                       tx: -e.minY, ty: e.maxX))
    }
}
