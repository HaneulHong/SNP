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
/// - 저장본은 찍는 순간 정확한 마스크를 새로 뽑고, 프리뷰는 LiveDepthMask 의 가벼운 마스크를 쓴다
enum DepthEffect {

    /// 사람 = 흰색, 배경 = 검정. 적용할 이미지와 같은 좌표·크기.
    struct PersonMask {
        let mask: CIImage
        /// 사람이 화면에서 차지하는 비율 (0...1)
        let coverage: Double
    }

    /// 파라미터가 튜닝된 기준 해상도 (RetroLook 과 같은 기준)
    private static let referenceWidth: Double = 3264

    /// 이보다 작게 찍힌 사람은 무시한다 (화면 대비 비율)
    private static let minimumCoverage = 0.02

    static func wants(_ params: LookParameters) -> Bool {
        params.depthBlur > 0 || params.depthHaze > 0
    }

    /// 저장본용 — 정확도 높은 마스크를 새로 뽑아 적용한다
    static func apply(to image: CIImage, params: LookParameters) -> CIImage {
        guard wants(params), let person = personMask(for: image) else { return image }
        return apply(to: image, params: params, person: person)
    }

    /// 이미 뽑아 둔 마스크로 적용한다 (프리뷰)
    static func apply(to image: CIImage, params: LookParameters, person: PersonMask) -> CIImage {
        let extent = image.extent
        guard wants(params),
              extent.width > 0, extent.height > 0,
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
    private static func personMask(for image: CIImage) -> PersonMask? {
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

        return PersonMask(mask: scaled(CIImage(cvPixelBuffer: buffer), to: image.extent),
                          coverage: coverage)
    }

    /// 마스크는 사진보다 작게 나오므로 사진 크기·위치로 맞춘다
    static func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// 한 채널 8비트 마스크의 평균 (0...1) — 사람이 화면에서 차지하는 비율
    static func averageValue(of buffer: CVPixelBuffer) -> Double {
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

/// 프리뷰용 사람 마스크 — 실시간용 가벼운 품질로, 몇 프레임에 한 번만 새로 뽑고 그 사이엔 재사용한다.
/// 저장본은 이것 대신 DepthEffect 가 정확한 마스크를 새로 뽑으므로 머리카락 경계가 더 깔끔하다.
/// - Note: 카메라 비디오 큐에서만 쓴다.
final class LiveDepthMask {

    /// 마스크를 새로 뽑는 간격 (프레임)
    private static let interval = 3

    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    /// 영상용 핸들러 — 앞 프레임 결과를 이어 써서 마스크가 덜 떨린다
    private let sequence = VNSequenceRequestHandler()

    private var frameCount = 0
    private var latest: (mask: CIImage, coverage: Double)?

    /// 카메라 버퍼 한 장을 넣으면 몇 프레임마다 마스크를 새로 뽑는다
    func update(with pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        guard latest == nil || frameCount % Self.interval == 0 else { return }
        do {
            try sequence.perform([request], on: pixelBuffer)
        } catch {
            return
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return }
        latest = (CIImage(cvPixelBuffer: buffer), DepthEffect.averageValue(of: buffer))
    }

    /// 마지막 마스크를 카메라 버퍼 크기(extent)로 맞춰서
    func mask(scaledTo extent: CGRect) -> DepthEffect.PersonMask? {
        guard let latest else { return nil }
        return DepthEffect.PersonMask(mask: DepthEffect.scaled(latest.mask, to: extent),
                                      coverage: latest.coverage)
    }

    /// FILM 이 아니거나 비디오 모드일 때 — 다시 켰을 때 묵은 마스크가 한순간 보이지 않게
    func reset() {
        latest = nil
        frameCount = 0
    }
}
