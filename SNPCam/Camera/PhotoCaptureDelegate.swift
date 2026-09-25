import AVFoundation
import AudioToolbox
import CoreImage
import Photos
import UIKit
import UniformTypeIdentifiers

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let ratio: FrameRatio
    private let params: LookParameters
    private let mirrored: Bool
    private let context: CIContext
    private let completion: (UIImage?) -> Void
    private let workQueue = DispatchQueue(label: "snpcam.process", qos: .userInitiated)

    init(ratio: FrameRatio,
         params: LookParameters,
         mirrored: Bool,
         context: CIContext,
         completion: @escaping (UIImage?) -> Void) {
        self.ratio = ratio
        self.params = params
        self.mirrored = mirrored
        self.context = context
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        AudioServicesPlaySystemSound(1108)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil)
            return
        }

        // 플래시가 실제로 터졌을 때만 플래시 룩 (자동 모드에서 안 터지면 그대로)
        let look = photo.resolvedSettings.isFlashEnabled ? params.withFlash() : params

        workQueue.async { [self] in
            guard let result = PhotoProcessor.process(photoData: data,
                                                      ratio: ratio,
                                                      params: look,
                                                      mirrored: mirrored,
                                                      context: context) else {
                completion(nil)
                return
            }
            PhotoSaver.save(jpeg: result.jpeg)
            completion(result.thumbnail)
        }
    }
}

enum PhotoSaver {
    static func save(jpeg: Data) {
        whenAuthorized {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.jpeg.identifier
                request.addResource(with: .photo, data: jpeg, options: options)
            } completionHandler: { _, _ in }
        } denied: {}
    }

    /// 임시 동영상 파일을 보관함으로 옮긴다. 성공·실패와 상관없이 임시 파일은 남지 않는다.
    static func saveVideo(at url: URL) {
        let cleanUp: () -> Void = { try? FileManager.default.removeItem(at: url) }
        whenAuthorized {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .video, fileURL: url, options: options)
            } completionHandler: { _, _ in cleanUp() }
        } denied: {
            cleanUp()
        }
    }

    private static func whenAuthorized(_ write: @escaping () -> Void,
                                       denied: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited {
            write()
        } else {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited { write() } else { denied() }
            }
        }
    }
}
