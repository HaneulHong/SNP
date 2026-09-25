import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// 프리뷰(실시간)와 최종 저장본에 동일한 레시피를 적용하는 룩 엔진.
/// - 프리뷰는 `.preview` 품질로 무거운 단계(마스킹된 그레인 등)를 단순화한다.
enum LookQuality {
    case preview
    case full
}

enum RetroLook {

    /// 파라미터가 튜닝된 기준 해상도. 실제 이미지 크기에 맞춰 반경 값을 스케일한다.
    private static let referenceWidth: Double = 3264

    static func apply(to input: CIImage,
                      params: LookParameters,
                      quality: LookQuality,
                      seed: Double) -> CIImage {

        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return input }

        let scale = max(0.15, Double(extent.width) / referenceWidth)
        var image = input

        // ── 1. 화이트밸런스: 차갑고 살짝 마젠타 기운
        if params.targetTemperature != 6500 || params.targetTint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: params.targetTemperature,
                                               y: params.targetTint)
            ])
        }

        // ── 2. 옅은 채도
        if params.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: params.saturation,
                kCIInputContrastKey: 1.0,
                kCIInputBrightnessKey: 0.0
            ])
        }

        // ── 3. 낮은 다이나믹 레인지: 들린 블랙 + 눌린 하이라이트
        image = applyToneCurve(image, params: params)

        // ── 4. 베일링 글레어(플레어): 하이라이트가 주변으로 번짐
        if params.glareAmount > 0 {
            image = image.clampedToExtent()
                .applyingFilter("CIBloom", parameters: [
                    kCIInputRadiusKey: params.glareRadius * scale,
                    kCIInputIntensityKey: params.glareAmount
                ])
                .cropped(to: extent)
        }

        // ── 4-1. 뿌연 헤이즈: 흐린 사본 중 밝은 쪽만 남겨 섞는다
        //         → 피부의 어두운 잡티가 주변 살색에 묻히고, 전체가 살짝 뽀얗게 뜬다
        if params.hazeAmount > 0 {
            let blurred = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: params.hazeRadius * scale
                ])
                .cropped(to: extent)
            let lightened = blurred.applyingFilter("CILightenBlendMode", parameters: [
                kCIInputBackgroundImageKey: image
            ])
            image = image.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: lightened,
                kCIInputTimeKey: min(params.hazeAmount, 1)
            ])
        }

        // ── 5. 소프트 디테일 → ISP 샤프닝 헤일로
        if params.softness > 0 {
            image = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: params.softness * scale
                ])
                .cropped(to: extent)
        }
        if params.sharpenIntensity > 0 {
            image = image.clampedToExtent()
                .applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: params.sharpenRadius * scale,
                    kCIInputIntensityKey: params.sharpenIntensity
                ])
                .cropped(to: extent)
        }

        // ── 6. 8MP 센서 노이즈
        if params.grainAmount > 0 {
            image = applyGrain(image, params: params, scale: scale,
                               quality: quality, seed: seed, extent: extent)
        }

        // ── 7. 비네팅
        if params.vignetteIntensity > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputRadiusKey: params.vignetteRadius,
                kCIInputIntensityKey: params.vignetteIntensity
            ])
        }

        return image.cropped(to: extent)
    }

    // MARK: - 톤 커브

    private static func applyToneCurve(_ image: CIImage,
                                       params: LookParameters) -> CIImage {
        let lo = params.blackLift
        let hi = params.highlightRolloff
        let c  = params.midContrast
        let g  = params.midGamma

        func map(_ x: Double) -> Double {
            let contrasted = min(max(0.5 + (x - 0.5) * c, 0), 1)
            return lo + (hi - lo) * pow(contrasted, g)
        }

        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0.00, y: map(0.00)),
            "inputPoint1": CIVector(x: 0.25, y: map(0.25)),
            "inputPoint2": CIVector(x: 0.50, y: map(0.50)),
            "inputPoint3": CIVector(x: 0.75, y: map(0.75)),
            "inputPoint4": CIVector(x: 1.00, y: map(1.00))
        ])
    }

    // MARK: - 그레인

    /// 무한 범위의 랜덤 노이즈. 매 호출마다 offset 만 바꿔 재사용한다.
    private static let randomNoise: CIImage = {
        CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray)
    }()

    private static func applyGrain(_ image: CIImage,
                                   params: LookParameters,
                                   scale: Double,
                                   quality: LookQuality,
                                   seed: Double,
                                   extent: CGRect) -> CIImage {

        // 컬러 노이즈 → 휘도 노이즈로 변환하면서 진폭(0.5 기준)을 조절
        let s = params.grainAmount
        let bias = 0.5 * (1 - s)
        let mono = randomNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.299 * s, y: 0.587 * s, z: 0.114 * s, w: 0),
            "inputGVector": CIVector(x: 0.299 * s, y: 0.587 * s, z: 0.114 * s, w: 0),
            "inputBVector": CIVector(x: 0.299 * s, y: 0.587 * s, z: 0.114 * s, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)
        ])

        // 알갱이 크기 = 출력 해상도에 비례 → 프리뷰와 저장본의 결이 비슷해진다
        let cell = max(1.0, params.grainSize * scale)
        let dx = (seed * 977).truncatingRemainder(dividingBy: 512)
        let dy = (seed * 1583).truncatingRemainder(dividingBy: 512)

        let grain = mono
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .cropped(to: extent)

        // 소프트라이트로 얹으면 중간톤을 유지한 채 결만 올라간다
        let grained = grain.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)

        guard quality == .full, params.shadowGrainBias > 0 else { return grained }

        // 하이라이트에는 노이즈를 덜 얹는다 (실제 센서와 같은 거동)
        let floor = 1 - params.shadowGrainBias
        let range = params.shadowGrainBias
        let mask = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -0.299 * range, y: -0.587 * range, z: -0.114 * range, w: 0),
            "inputGVector": CIVector(x: -0.299 * range, y: -0.587 * range, z: -0.114 * range, w: 0),
            "inputBVector": CIVector(x: -0.299 * range, y: -0.587 * range, z: -0.114 * range, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: floor + range, y: floor + range, z: floor + range, w: 1)
        ])

        return grained.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }
}
