import CoreImage
import MetalKit
import SwiftUI

/// 카메라 버퍼에 룩을 입힌 CIImage 를 Metal 로 그려주는 뷰.
/// AVCaptureVideoPreviewLayer 대신 직접 그려야 프리뷰에도 동일한 필터가 걸린다. (WYSIWYG)
final class PreviewRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private var pendingImage: CIImage?
    private let lock = NSLock()

    weak var view: MTKView?

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal 을 사용할 수 없는 기기입니다.")
        }
        self.device = device
        self.commandQueue = queue
        var options: [CIContextOption: Any] = [.cacheIntermediates: false,
                                               .name: "SNPCam"]
        if let working = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
            options[.workingColorSpace] = working
        }
        self.ciContext = CIContext(mtlDevice: device, options: options)
        super.init()
    }

    /// 카메라 큐에서 호출된다. CIImage 는 아직 렌더되지 않은 레시피라 비용이 거의 없다.
    func enqueue(_ image: CIImage) {
        lock.lock()
        pendingImage = image
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.view?.setNeedsDisplay()
        }
    }

    func clear() {
        lock.lock()
        pendingImage = nil
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let image = pendingImage
        lock.unlock()

        guard let image,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let drawableSize = view.drawableSize
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, drawableSize.width > 0 else { return }

        // aspect fill
        let scale = max(drawableSize.width / extent.width,
                        drawableSize.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let originX = (scaled.extent.width - drawableSize.width) / 2
        let originY = (scaled.extent.height - drawableSize.height) / 2

        ciContext.render(scaled,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: CGRect(x: scaled.extent.origin.x + originX,
                                        y: scaled.extent.origin.y + originY,
                                        width: drawableSize.width,
                                        height: drawableSize.height),
                         colorSpace: colorSpace)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalPreviewView: UIViewRepresentable {
    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = renderer
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.backgroundColor = .black
        view.isOpaque = true
        view.contentMode = .scaleAspectFill
        renderer.view = view
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
