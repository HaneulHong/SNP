import AVFoundation
import CoreImage
import UIKit

/// 룩이 입혀진 프레임과 마이크 소리를 .mov 로 기록한다.
/// 기본 카메라처럼 `AVCaptureMovieFileOutput` 을 쓰면 필터를 걸 수 없어서, 프레임을 직접 인코딩한다.
/// - Note: 생성부터 `finish` 까지 모든 호출은 카메라 비디오 큐(직렬)에서만 한다.
final class VideoRecorder {

    /// 녹화를 시작할 때 기기를 든 방향. 녹화 중에는 바뀌지 않는다.
    let orientation: CaptureOrientation

    private let url: URL
    private let size: CGSize
    private let context: CIContext
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private var sessionStart: CMTime?
    private var lastVideoTime: CMTime = .invalid
    private var isFinishing = false
    private var thumbnail: UIImage?

    /// - Parameter audioSettings: nil 이면 소리 없이 기록한다 (마이크 권한 거부 등)
    init?(size: CGSize,
          orientation: CaptureOrientation,
          audioSettings: [String: Any]?,
          context: CIContext) {

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SNP-\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }

        let width = Int(size.width), height = Int(size.height)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ])

        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if let audioSettings {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else { return nil }

        self.orientation = orientation
        self.url = url
        self.size = size
        self.context = context
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
    }

    func appendVideo(_ image: CIImage, at time: CMTime) {
        guard !isFinishing, writer.status == .writing else { return }

        if sessionStart == nil {
            writer.startSession(atSourceTime: time)
            sessionStart = time
        }
        guard videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }

        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }

        context.render(image, to: buffer,
                       bounds: CGRect(origin: .zero, size: size),
                       colorSpace: colorSpace)
        if adaptor.append(buffer, withPresentationTime: time) {
            lastVideoTime = time
        }

        if thumbnail == nil {
            thumbnail = makeThumbnail(from: image)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing,
              writer.status == .writing,
              let start = sessionStart,
              let audioInput,
              audioInput.isReadyForMoreMediaData,
              CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= start else { return }
        audioInput.append(sampleBuffer)
    }

    /// 파일을 마무리한다. 한 프레임도 못 찍었으면 파일을 지우고 nil 을 넘긴다.
    func finish(completion: @escaping (URL?, UIImage?) -> Void) {
        guard !isFinishing else { return }
        isFinishing = true

        guard sessionStart != nil, lastVideoTime.isValid, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(nil, nil)
            return
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        // 영상 마지막 프레임에서 끊어서 끝에 소리만 남는 구간이 없게 한다
        writer.endSession(atSourceTime: lastVideoTime)

        let thumbnail = thumbnail
        writer.finishWriting { [writer, url] in
            if writer.status == .completed {
                completion(url, thumbnail)
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(nil, nil)
            }
        }
    }

    private func makeThumbnail(from image: CIImage) -> UIImage? {
        let side: CGFloat = 240
        let scale = side / max(image.extent.width, image.extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(small, from: small.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
