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
        withAddAccess {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.jpeg.identifier
                request.addResource(with: .photo, data: jpeg, options: options)
            } completionHandler: { _, _ in }
        }
    }

    /// 임시 파일을 보관함으로 옮긴다. 실패하거나 권한이 없으면 임시 파일을 지운다.
    static func save(videoAt url: URL) {
        let cleanUp: () -> Void = { try? FileManager.default.removeItem(at: url) }
        withAddAccess(denied: cleanUp) {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .video, fileURL: url, options: options)
            } completionHandler: { success, _ in
                if !success { cleanUp() }
            }
        }
    }

    private static func withAddAccess(denied: @escaping () -> Void = {},
                                      _ write: @escaping () -> Void) {
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
