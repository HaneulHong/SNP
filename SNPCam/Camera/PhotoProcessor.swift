import CoreImage
import UIKit

/// 촬영된 원본 → 크롭 → 기종 해상도(8/12MP)로 다운스케일 → 룩 적용 → JPEG.
enum PhotoProcessor {

    struct Output {
        let jpeg: Data
        let thumbnail: UIImage
    }

    static func process(photoData: Data,
                        ratio: FrameRatio,
                        params: LookParameters,
                        mirrored: Bool,
                        context: CIContext) -> Output? {

        guard var image = CIImage(data: photoData,
                                  options: [.applyOrientationProperty: true]) else {
            return nil
        }

        if mirrored {
            // 프리뷰에서 본 그대로 저장 (셀피 좌우 반전 유지)
            image = image.oriented(.upMirrored)
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x,
                                                        y: -image.extent.origin.y))

        // 1. 목표 비율로 센터 크롭
        image = centerCrop(image, aspect: ratio.aspect)

        // 2. 흉내내는 기종의 센서 해상도로 다운스케일 (5s = 8MP, 6s = 12MP)
        //    셀카(mirrored = 전면 카메라)는 그 시절 전면 카메라 해상도로 (5s = 1.2MP, 6s = 5MP)
        let longSide = mirrored ? params.frontSensorLongSide : params.sensorLongSide
        image = resize(image, to: ratio.outputSize(sensorLongSide: CGFloat(longSide)))

        // 3. 룩 적용
        let looked = RetroLook.apply(to: image,
                                     params: params,
                                     quality: .full,
                                     seed: Date().timeIntervalSinceReferenceDate)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let jpeg = context.jpegRepresentation(
            of: looked,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(
                rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92]
        ) else { return nil }

        let thumbSide: CGFloat = 240
        let thumbScale = thumbSide / max(looked.extent.width, looked.extent.height)
        let thumbImage = looked.transformed(by: CGAffineTransform(scaleX: thumbScale, y: thumbScale))
        let thumbnail: UIImage
        if let cg = context.createCGImage(thumbImage, from: thumbImage.extent) {
            thumbnail = UIImage(cgImage: cg)
        } else {
            thumbnail = UIImage()
        }

        return Output(jpeg: jpeg, thumbnail: thumbnail)
    }

    /// 세로 기준 가로/세로 비에 맞춰 가운데를 잘라낸다.
    static func centerCrop(_ image: CIImage, aspect: CGFloat) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }

        let current = e.width / e.height
        var rect = e
        if current > aspect {
            let w = e.height * aspect
            rect = CGRect(x: e.midX - w / 2, y: e.minY, width: w, height: e.height)
        } else if current < aspect {
            let h = e.width / aspect
            rect = CGRect(x: e.minX, y: e.midY - h / 2, width: e.width, height: h)
        }
        return image.cropped(to: rect.integral)
            .transformed(by: CGAffineTransform(translationX: -rect.integral.origin.x,
                                               y: -rect.integral.origin.y))
    }

    static func resize(_ image: CIImage, to size: CGSize) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }
        let scale = size.width / e.width
        guard abs(scale - 1) > 0.001 else { return image }

        let resized = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0
        ])
        return resized.cropped(to: CGRect(origin: .zero, size: size))
    }
}
