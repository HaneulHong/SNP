import AVFoundation
import CoreImage
import UIKit

/// 룩이 입혀진 프레임 + 마이크 소리를 임시 .mov 파일로 기록한다.
/// 모든 메서드는 같은 직렬 큐(CameraManager 의 videoQueue)에서 호출해야 한다.
final class VideoRecorder {

    enum RecorderError: Error {
        case cannotStart
    }

    let size: CGSize

    private let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private var sessionStarted = false
    private var thumbnail: UIImage?

    /// - Parameter audioSettings: nil 이면 소리 없이 기록한다 (마이크 권한 거부 등)
    init(size: CGSize, audioSettings: [String: Any]?, context: CIContext) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // 5s 시절처럼 H.264 — 프레임은 이미 세로로 회전돼 들어오므로 변환 없이 그대로 쓴다
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecorderError.cannotStart }
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
        )

        var audioInput: AVAssetWriterInput?
        if let audioSettings,
           writer.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else { throw RecorderError.cannotStart }

        self.size = size
        self.url = url
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
        self.context = context
    }

    /// 룩이 적용된 프레임 한 장. extent 는 (0, 0, size) 여야 한다.
    func appendVideo(_ image: CIImage, at time: CMTime) {
        guard writer.status == .writing else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
            thumbnail = makeThumbnail(image)
        }

        guard videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }

        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }

        context.render(image,
                       to: buffer,
                       bounds: CGRect(origin: .zero, size: size),
                       colorSpace: colorSpace)
        adaptor.append(buffer, withPresentationTime: time)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        // 첫 영상 프레임 전에 들어온 소리는 버린다 — 앞부분에 검은 화면이 생기지 않게
        guard sessionStarted,
              writer.status == .writing,
              let audioInput,
              audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    /// 기록을 끝낸다. 성공하면 완성된 파일 URL 과 첫 프레임 썸네일을 넘긴다.
    func finish(completion: @escaping (URL?, UIImage?) -> Void) {
        let url = self.url
        let writer = self.writer

        guard sessionStarted, writer.status == .writing else {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)
            completion(nil, nil)
            return
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        let thumbnail = self.thumbnail
        writer.finishWriting {
            if writer.status == .completed {
                completion(url, thumbnail)
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(nil, nil)
            }
        }
    }

    private func makeThumbnail(_ image: CIImage) -> UIImage? {
        let side: CGFloat = 240
        let scale = side / max(image.extent.width, image.extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(small, from: small.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
