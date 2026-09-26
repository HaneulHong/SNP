import CoreImage
import Foundation

/// 35mm 컬러 네거티브 필름 색 — 코드로 만든 3D LUT.
///
/// 레퍼런스(여름 해변 필름 사진)에서 뽑은 특징:
/// - 빨강·노랑은 진하게, 빨강은 살짝 주황 쪽으로
/// - 초록은 채도를 죽여 올리브로, 파랑은 청록 쪽으로
/// - 피부(주황 계열)는 채도를 건드리지 않아 황금빛만 남긴다
/// - 그림자는 살짝 청록, 하이라이트는 크림색 (흐린 하늘이 파랗지 않고 크림빛 회색)
/// - 아주 진한 색은 눌러서 형광처럼 뜨지 않게
enum FilmColor {

    private static let dimension = 33

    /// 한 번만 만들어 재사용한다 (33³ = 35,937칸)
    private static let cube: Data = makeCube()

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// - Parameter amount: 0 = 원본, 1 = 필름 색 100%
    static func apply(to image: CIImage, amount: Double) -> CIImage {
        guard amount > 0 else { return image }
        let filmed = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": cube,
            "inputColorSpace": colorSpace
        ])
        guard amount < 1 else { return filmed }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: filmed,
            kCIInputTimeKey: amount
        ])
    }

    // MARK: - LUT 만들기

    private static func makeCube() -> Data {
        let n = dimension
        var values = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        // CIColorCube 는 빨강이 가장 빨리 바뀌는 순서
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = grade(r: Double(r) / Double(n - 1),
                                    g: Double(g) / Double(n - 1),
                                    b: Double(b) / Double(n - 1))
                    values[i]     = Float(out.r)
                    values[i + 1] = Float(out.g)
                    values[i + 2] = Float(out.b)
                    values[i + 3] = 1
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// sRGB(감마) 값 하나를 필름 색으로
    private static func grade(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let (h0, s0, v) = hsv(r, g, b)

        // 1. 색상 이동 (원래 색상 기준으로 한 번에)
        var h = h0
            + 4 * bump(h0, 0, 18)       // 빨강 → 주황 쪽
            - 2 * bump(h0, 60, 18)      // 노랑 → 아주 살짝 따뜻하게 (레퍼런스 파라솔은 레몬빛)
            - 14 * bump(h0, 115, 28)    // 초록 → 올리브
            - 12 * bump(h0, 220, 25)    // 파랑 → 청록
        h = (h + 360).truncatingRemainder(dividingBy: 360)

        // 2. 색상별 채도
        let scale = 1
            + 0.12 * bump(h, 0, 20)     // 빨강 진하게
            + 0.12 * bump(h, 55, 18)    // 노랑 진하게
            - 0.08 * bump(h, 25, 10)    // 피부는 그대로
            - 0.18 * bump(h, 115, 30)   // 초록 죽이기
            - 0.06 * bump(h, 220, 30)   // 파랑 살짝 죽이기
        var s = s0 * scale
        if s > 0.8 { s = 0.8 + (s - 0.8) * 0.5 }
        s = min(max(s, 0), 1)

        var (nr, ng, nb) = rgb(h, s, v)

        // 3. 스플릿 톤 — 그림자는 청록, 하이라이트는 크림
        let luma = 0.2126 * nr + 0.7152 * ng + 0.0722 * nb
        let shadow = 1 - smoothstep(0.0, 0.45, luma)
        let highlight = smoothstep(0.55, 1.0, luma)
        nr += -0.018 * shadow + 0.022 * highlight
        ng +=  0.006 * shadow + 0.010 * highlight
        nb +=  0.016 * shadow - 0.025 * highlight

        return (clamp(nr), clamp(ng), clamp(nb))
    }

    /// 색상환 위에서 center 근처일수록 1 에 가까운 종 모양 가중치
    private static func bump(_ h: Double, _ center: Double, _ width: Double) -> Double {
        var d = abs(h - center).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return exp(-(d * d) / (2 * width * width))
    }

    private static func smoothstep(_ lo: Double, _ hi: Double, _ x: Double) -> Double {
        let t = min(max((x - lo) / (hi - lo), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// h: 0..<360, s·v: 0...1
    private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }
        if h < 0 { h += 360 }
        let s = maxC > 0 ? delta / maxC : 0
        return (h, s, maxC)
    }

    private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60:  (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default:     (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
