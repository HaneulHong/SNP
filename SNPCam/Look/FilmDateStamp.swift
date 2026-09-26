import CoreImage
import UIKit

/// 필름 똑딱이의 날짜 스탬프 — 오른쪽 아래 주황색 7세그먼트 숫자 `'26 9 26`.
///
/// 필름 카메라는 뒤판의 LED 로 필름에 날짜를 직접 굽는다. 그래서
/// - 빛이 더해지는 것이라 주황빛이 번지고 (글로)
/// - 사진의 일부가 되어 뒤따르는 소프트·그레인을 같이 먹는다 (RetroLook 안에서 합성)
///
/// 폰트에 기대지 않고 세그먼트를 직접 그린다. 날짜·크기가 같으면 다시 그리지 않는다.
/// - Note: 캐시가 있으므로 한 인스턴스는 한 큐에서만 쓴다.
final class FilmDateStamp {

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "''yy M d"   // '26 9 26
        return f
    }()

    private var cacheKey = ""
    private var cached: CIImage?

    /// frame 오른쪽 아래 자리에 놓인 스탬프 (프레임 밖으로 번지는 글로 포함)
    func image(for date: Date, in frame: CGRect) -> CIImage? {
        let text = formatter.string(from: date)
        let key = "\(text)@\(Int(frame.width))x\(Int(frame.height))"
        if key == cacheKey { return cached }
        cacheKey = key
        cached = render(text, in: frame)
        return cached
    }

    // MARK: - 그리기

    private func render(_ text: String, in frame: CGRect) -> CIImage? {
        let short = min(frame.width, frame.height)
        guard short > 0 else { return nil }

        // 숫자 높이는 짧은 변의 4% — 35mm 필름 한 컷에 찍히는 날짜 크기
        let height = max(8, (short * 0.04).rounded())
        let width = height * 0.52
        let thickness = max(1.5, height * 0.13)
        let gap = thickness * 0.18
        let advance = width + thickness * 0.9
        let spaceAdvance = width * 0.7
        let slant = height * 0.12

        var totalWidth: CGFloat = 0
        for ch in text {
            switch ch {
            case " ":  totalWidth += spaceAdvance
            case "'":  totalWidth += thickness * 2.2
            default:   totalWidth += advance
            }
        }
        let pad = ceil(slant + thickness)
        let size = CGSize(width: ceil(totalWidth + pad * 2), height: ceil(height + pad * 2))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 1.0, green: 0.40, blue: 0.08, alpha: 1).cgColor)   // 붉은 주황
            // 날짜 뒤판 숫자처럼 살짝 기울인다 (위쪽이 오른쪽으로)
            cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -slant / height, d: 1,
                                             tx: pad + slant, ty: pad))
            var x: CGFloat = 0
            for ch in text {
                switch ch {
                case " ":
                    x += spaceAdvance
                case "'":
                    cg.addPath(Self.verticalSegment(cx: x + thickness, cy: height * 0.14,
                                                    length: height * 0.28, thickness: thickness))
                    x += thickness * 2.2
                default:
                    if let digit = ch.wholeNumberValue {
                        Self.addDigit(digit, to: cg, x: x, width: width, height: height,
                                      thickness: thickness, gap: gap)
                    }
                    x += advance
                }
            }
            cg.fillPath()
        }
        guard let cgImage = bitmap.cgImage else { return nil }

        // 심 + 번짐: 흐린 사본을 밑에 더해 LED 로 구운 듯한 주황 글로
        let core = CIImage(cgImage: cgImage)
        let glow = core.applyingGaussianBlur(sigma: Double(thickness) * 0.9)
        let stamp = core.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: glow
        ])

        let margin = (short * 0.06).rounded()
        return stamp.transformed(by: CGAffineTransform(
            translationX: frame.maxX - margin - size.width + pad,
            y: frame.minY + margin - pad))
    }

    // MARK: - 7세그먼트

    //  a
    // f b
    //  g
    // e c
    //  d
    private static let segments: [Int: String] = [
        0: "abcdef", 1: "bc", 2: "abdeg", 3: "abcdg", 4: "bcfg",
        5: "acdfg", 6: "acdefg", 7: "abc", 8: "abcdefg", 9: "abcdfg"
    ]

    private static func addDigit(_ digit: Int, to cg: CGContext, x: CGFloat,
                                 width w: CGFloat, height h: CGFloat,
                                 thickness t: CGFloat, gap: CGFloat) {
        let horizontal = w - t - gap * 2
        let vertical = h / 2 - t / 2 - gap * 2
        let upperY = h / 4 + t / 4
        let lowerY = h * 3 / 4 - t / 4

        for segment in segments[digit] ?? "" {
            switch segment {
            case "a": cg.addPath(horizontalSegment(cx: x + w / 2, cy: t / 2, length: horizontal, thickness: t))
            case "g": cg.addPath(horizontalSegment(cx: x + w / 2, cy: h / 2, length: horizontal, thickness: t))
            case "d": cg.addPath(horizontalSegment(cx: x + w / 2, cy: h - t / 2, length: horizontal, thickness: t))
            case "f": cg.addPath(verticalSegment(cx: x + t / 2, cy: upperY, length: vertical, thickness: t))
            case "b": cg.addPath(verticalSegment(cx: x + w - t / 2, cy: upperY, length: vertical, thickness: t))
            case "e": cg.addPath(verticalSegment(cx: x + t / 2, cy: lowerY, length: vertical, thickness: t))
            case "c": cg.addPath(verticalSegment(cx: x + w - t / 2, cy: lowerY, length: vertical, thickness: t))
            default:  break
            }
        }
    }

    /// 양 끝이 뾰족한 가로 세그먼트
    private static func horizontalSegment(cx: CGFloat, cy: CGFloat,
                                          length l: CGFloat, thickness t: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: cx - l / 2, y: cy),
            CGPoint(x: cx - l / 2 + t / 2, y: cy - t / 2),
            CGPoint(x: cx + l / 2 - t / 2, y: cy - t / 2),
            CGPoint(x: cx + l / 2, y: cy),
            CGPoint(x: cx + l / 2 - t / 2, y: cy + t / 2),
            CGPoint(x: cx - l / 2 + t / 2, y: cy + t / 2)
        ])
        path.closeSubpath()
        return path
    }

    /// 양 끝이 뾰족한 세로 세그먼트
    private static func verticalSegment(cx: CGFloat, cy: CGFloat,
                                        length l: CGFloat, thickness t: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: cx, y: cy - l / 2),
            CGPoint(x: cx + t / 2, y: cy - l / 2 + t / 2),
            CGPoint(x: cx + t / 2, y: cy + l / 2 - t / 2),
            CGPoint(x: cx, y: cy + l / 2),
            CGPoint(x: cx - t / 2, y: cy + l / 2 - t / 2),
            CGPoint(x: cx - t / 2, y: cy - l / 2 + t / 2)
        ])
        path.closeSubpath()
        return path
    }
}
