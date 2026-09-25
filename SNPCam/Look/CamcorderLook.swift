import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 비디오용 룩 엔진. 카메라 → 테이프로 신호가 흘러가는 순서대로 열화를 쌓는다.
/// 프리뷰와 녹화 파일에 같은 CIImage 를 쓰므로 보이는 그대로 기록된다.
enum CamcorderLook {

    /// 기록 해상도 — SD 4:3. 세로로 들면 480×640, 가로로 들면 640×480.
    static let portraitSize = CGSize(width: 480, height: 640)
    /// 세로 기준 가로/세로 비
    static let aspect: CGFloat = 3.0 / 4.0

    /// 파라미터가 튜닝된 기준 해상도 (긴 변)
    private static let referenceLongSide: Double = 640

    static func apply(to input: CIImage,
                      params: CamcorderParameters,
                      stamp: CIImage?) -> CIImage {

        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return input }

        let scale = Double(max(extent.width, extent.height)) / referenceLongSide
        var image = input

        // ── 1. CCD 색감
        if params.targetTemperature != 6500 || params.targetTint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: params.targetTemperature,
                                               y: params.targetTint)
            ])
        }
        if params.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: params.saturation,
                kCIInputContrastKey: 1.0,
                kCIInputBrightnessKey: 0.0
            ])
        }

        // ── 2. 좁은 비디오 레인지: 들린 블랙 + 쉽게 날아가는 하이라이트
        image = applyToneCurve(image, params: params)
        // 비디오 신호는 0~1 에서 잘린다. 채도를 올려 음수가 된 채널을 남겨두면
        // 뒤 블렌드 단계에서 NaN 이 생기고 샤프닝이 그걸 검은 원으로 번지게 한다.
        image = image.applyingFilter("CIColorClamp")

        // ── 3. 렌즈: 소프트 + 비네팅
        if params.softness > 0 {
            image = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: params.softness * scale
                ])
                .cropped(to: extent)
        }
        if params.vignetteIntensity > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputRadiusKey: params.vignetteRadius,
                kCIInputIntensityKey: params.vignetteIntensity
            ])
        }

        // ── 4. 센서 노이즈
        if params.noiseAmount > 0 || params.chromaNoise > 0 {
            image = applyNoise(image, params: params, scale: scale, extent: extent)
        }

        // ── 5. 에지 강조 — 노이즈까지 같이 날카로워지는 게 캠코더답다
        if params.edgeEnhance > 0 {
            image = image.clampedToExtent()
                .applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: params.edgeRadius * scale,
                    kCIInputIntensityKey: params.edgeEnhance
                ])
                .cropped(to: extent)
                .applyingFilter("CIColorClamp")
        }

        // ── 6. 날짜 스탬프 — 테이프에 같이 기록되므로 아래 번짐을 똑같이 먹는다
        if let stamp {
            image = stamp.composited(over: image)
        }

        // ── 7. 테이프: 색 번짐 + 색 어긋남 (밝기는 선명하게 두고 색만 흘린다)
        if params.chromaBleed > 0 || params.chromaShift > 0 {
            var smear = image.clampedToExtent()
            if params.chromaBleed > 0 {
                smear = smear.applyingFilter("CIMotionBlur", parameters: [
                    kCIInputRadiusKey: params.chromaBleed * scale,
                    kCIInputAngleKey: 0
                ])
            }
            smear = smear
                .transformed(by: CGAffineTransform(translationX: params.chromaShift * scale, y: 0))
                .cropped(to: extent)
            // Color 블렌드: 색상·채도는 번진 쪽, 밝기는 원본
            image = smear.applyingFilter("CIColorBlendMode", parameters: [
                kCIInputBackgroundImageKey: image
            ])
        }

        // ── 8. 인터레이스 가로줄
        if params.scanlines > 0 {
            image = applyScanlines(image, params: params, scale: scale, extent: extent)
        }

        // ── 9. 트래킹 흔들림
        if params.jitter > 0 {
            let offset = Double.random(in: -1...1) * params.jitter * scale
            image = image.clampedToExtent()
                .transformed(by: CGAffineTransform(translationX: offset, y: 0))
        }

        return image.cropped(to: extent)
    }

    // MARK: - 톤 커브

    private static func applyToneCurve(_ image: CIImage,
                                       params: CamcorderParameters) -> CIImage {
        let lo = params.blackLift
        let hi = params.whiteLevel
        let c  = params.contrast
        guard lo != 0 || hi != 1 || c != 1 else { return image }

        func map(_ x: Double) -> Double {
            let contrasted = min(max(0.5 + (x - 0.5) * c, 0), 1)
            return lo + (hi - lo) * contrasted
        }

        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0.00, y: map(0.00)),
            "inputPoint1": CIVector(x: 0.25, y: map(0.25)),
            "inputPoint2": CIVector(x: 0.50, y: map(0.50)),
            "inputPoint3": CIVector(x: 0.75, y: map(0.75)),
            "inputPoint4": CIVector(x: 1.00, y: map(1.00))
        ])
    }

    // MARK: - 노이즈

    /// 생성기는 알파까지 무작위라서, 그대로 색 행렬에 넣으면 알파로 나누는 과정에서 값이 수천 배로 튄다.
    /// 검정 위에 얹어 알파를 1 로 고정한다.
    private static let randomNoise: CIImage = {
        (CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray))
            .composited(over: CIImage(color: .black))
    }()

    private static func applyNoise(_ image: CIImage,
                                   params: CamcorderParameters,
                                   scale: Double,
                                   extent: CGRect) -> CIImage {

        // 채널마다 = 휘도 성분(세 채널 공통) + 색 성분(채널별). 평균은 0.5 로 맞춘다.
        let l = params.noiseAmount
        let c = params.chromaNoise
        let bias = 0.5 * (1 - l - c)
        let noise = randomNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.299 * l + c, y: 0.587 * l, z: 0.114 * l, w: 0),
            "inputGVector": CIVector(x: 0.299 * l, y: 0.587 * l + c, z: 0.114 * l, w: 0),
            "inputBVector": CIVector(x: 0.299 * l, y: 0.587 * l, z: 0.114 * l + c, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)
        ])

        // 매 프레임 다른 위치를 잘라 써서 노이즈가 지글거리게 한다 (정수 오프셋이라 알갱이가 선명)
        let cell = max(1.0, params.noiseSize * scale)
        let dx = Double(Int.random(in: 0..<512))
        let dy = Double(Int.random(in: 0..<512))
        let grain = noise
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .transformed(by: CGAffineTransform(scaleX: cell * max(1, params.noiseStretch), y: cell))
            .cropped(to: extent)

        return grain.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)
    }

    // MARK: - 가로줄

    private static func applyScanlines(_ image: CIImage,
                                       params: CamcorderParameters,
                                       scale: Double,
                                       extent: CGRect) -> CIImage {
        let dark = 1 - params.scanlines
        let stripes = CIFilter.stripesGenerator()
        stripes.center = .zero
        stripes.color0 = CIColor(red: 1, green: 1, blue: 1)
        stripes.color1 = CIColor(red: dark, green: dark, blue: dark)
        stripes.width = Float(max(1, scale.rounded()))
        stripes.sharpness = 1

        // 생성기는 세로줄 → 90° 돌려 가로줄로
        guard let lines = stripes.outputImage?
            .transformed(by: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0))
            .cropped(to: extent) else { return image }

        return lines.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ])
    }
}

// MARK: - 날짜 스탬프

/// 캠코더 날짜 스탬프. 비트맵 폰트처럼 보이도록 저해상도에 안티에일리어싱 없이 그린 뒤
/// 최근접 보간으로 키운다. 문자열이 바뀔 때(1초에 한 번)만 다시 그린다.
/// - Note: 카메라 비디오 큐에서만 쓴다.
final class DateStamp {

    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    private var cacheKey = ""
    private var cached: CIImage?

    init() {
        let posix = Locale(identifier: "en_US_POSIX")
        timeFormatter.locale = posix
        timeFormatter.dateFormat = "h:mm:ss a"
        dateFormatter.locale = posix
        dateFormatter.dateFormat = "MMM. d yyyy"
    }

    /// 프레임 오른쪽 아래 자리까지 잡힌 스탬프
    ///
    ///       10:16:32 PM
    ///      SEP. 25 2026
    func image(for date: Date, in frame: CGRect) -> CIImage? {
        let lines = [timeFormatter.string(from: date),
                     dateFormatter.string(from: date).uppercased()]
        let key = lines.joined(separator: "\n") + "@\(Int(frame.width))x\(Int(frame.height))"
        if key == cacheKey { return cached }
        cacheKey = key
        cached = render(lines, in: frame)
        return cached
    }

    private func render(_ lines: [String], in frame: CGRect) -> CIImage? {
        let short = min(frame.width, frame.height)
        let dot = max(1, (short / 240).rounded())                // 480px → 2px 도트
        let fontSize = max(6, (short * 0.05 / dot).rounded())
        let font = UIFont(name: "Menlo-Bold", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let face: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor(white: 0.97, alpha: 1)
        ]
        let shadow: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black
        ]

        let widths = lines.map { ceil(($0 as NSString).size(withAttributes: face).width) }
        let lineHeight = ceil(font.lineHeight)
        let size = CGSize(width: (widths.max() ?? 0) + 1,
                          height: lineHeight * CGFloat(lines.count) + 1)
        guard size.width > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setShouldAntialias(false)
            cg.setAllowsAntialiasing(false)
            cg.setShouldSmoothFonts(false)
            for (i, line) in lines.enumerated() {
                // 오른쪽 정렬 + 1px 검은 그림자
                let origin = CGPoint(x: size.width - 1 - widths[i],
                                     y: CGFloat(i) * lineHeight)
                (line as NSString).draw(at: CGPoint(x: origin.x + 1, y: origin.y + 1),
                                        withAttributes: shadow)
                (line as NSString).draw(at: origin, withAttributes: face)
            }
        }
        guard let cgImage = bitmap.cgImage else { return nil }

        let stamp = CIImage(cgImage: cgImage)
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: dot, y: dot))
        let margin = (short * 0.06).rounded()
        return stamp.transformed(by: CGAffineTransform(
            translationX: frame.maxX - margin - stamp.extent.width,
            y: frame.minY + margin))
    }
}
