import CoreImage
import CoreVideo
import Vision

/// 필름 카메라의 얕은 심도와 거리감 — 사람 뒤 배경만 흐리고 옅게.
///
/// 폰 카메라는 센서가 작아서 배경까지 다 선명하게 찍힌다. 레퍼런스 필름 사진은 인물 뒤 모래·파라솔이
/// 부드럽게 흐려지고, 먼 곳은 공기 때문에 옅고 뿌옇다. 렌즈 하나(광각)만 쓰므로 깊이 센서 대신
/// Vision 의 사람 분리 마스크로 사람과 배경을 나눈다.
///
/// - 사람이 없거나 너무 작게 찍히면 아무것도 하지 않는다 (풍경·정물은 그대로 선명하게)
/// - 사람이 화면을 크게 차지할수록(가까울수록) 배경을 더 흐린다 — 실제 렌즈와 같은 거동
/// - 찍는 순간에만 계산하므로 저장본에만 걸리고 프리뷰에는 없다
enum DepthEffect {

    /// 파라미터가 튜닝된 기준 해상도 (RetroLook 과 같은 기준)
    private static let referenceWidth: Double = 3264

    /// 이보다 작게 찍힌 사람은 무시한다 (화면 대비 비율)
    private static let minimumCoverage = 0.02

    static func apply(to image: CIImage, params: LookParameters) -> CIImage {
        guard params.depthBlur > 0 || params.depthHaze > 0 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              let person = personMask(for: image),
              person.coverage > minimumCoverage else { return image }

        let scale = max(0.15, Double(extent.width) / referenceWidth)
        // 화면의 30% 이상을 차지하면(상반신 인물) 최대, 작을수록 약하게
        let closeness = min(1, max(0.35, person.coverage / 0.3))

        // 배경 마스크 = 사람 마스크 반전, 경계는 살짝 풀어서 오려 붙인 티가 나지 않게
        let background = person.mask
            .applyingFilter("CIColorInvert")
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4 * scale])
            .cropped(to: extent)

        var result = image

        // 1. 배경 흐림 — 마스크가 흰 곳(배경)일수록 반경이 커진다
        if params.depthBlur > 0 {
            result = image.clampedToExtent()
                .applyingFilter("CIMaskedVariableBlur", parameters: [
                    "inputMask": background,
                    kCIInputRadiusKey: params.depthBlur * scale * closeness
                ])
                .cropped(to: extent)
        }

        // 2. 공기 원근 — 배경을 밝은 크림빛 공기 쪽으로 옅게
        if params.depthHaze > 0 {
            let air = CIImage(color: CIColor(red: 0.86, green: 0.84, blue: 0.80)).cropped(to: extent)
            let hazed = result.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: air,
                kCIInputTimeKey: min(1, params.depthHaze * closeness)
            ])
            result = hazed.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: background
            ])
        }

        return result.cropped(to: extent)
    }

    // MARK: - 사람 마스크

    /// 사람 = 흰색, 배경 = 검정. 이미지와 같은 크기로 맞춰서 돌려준다.
    private static func personMask(for image: CIImage) -> (mask: CIImage, coverage: Double)? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }

        let coverage = averageValue(of: buffer)

        // 마스크는 사진보다 작게 나오므로 사진 크기로 키운다
        var mask = CIImage(cvPixelBuffer: buffer)
        let sx = image.extent.width / mask.extent.width
        let sy = image.extent.height / mask.extent.height
        mask = mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX,
                                               y: image.extent.minY))
        return (mask, coverage)
    }

    /// 한 채널 8비트 마스크의 평균 (0...1) — 사람이 화면에서 차지하는 비율
    private static func averageValue(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        var sum = 0
        var count = 0
        for y in stride(from: 0, to: height, by: 4) {
            let row = bytes + y * rowBytes
            for x in stride(from: 0, to: width, by: 4) {
                sum += Int(row[x])
                count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count * 255) : 0
    }
}
