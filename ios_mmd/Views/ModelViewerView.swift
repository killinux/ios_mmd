import SwiftUI
import MetalKit

struct ModelViewerView: UIViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.preferredFramesPerSecond = 30
        mtkView.clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.sampleCount = 4
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false

        guard let renderer = MetalMMDRenderer(mtkView: mtkView) else {
            fatalError("Failed to initialize MetalMMDRenderer")
        }

        mtkView.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.mtkView = mtkView

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        mtkView.addGestureRecognizer(panGesture)

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        mtkView.addGestureRecognizer(twoFingerPan)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        mtkView.addGestureRecognizer(pinchGesture)

        if let path = state.modelPath {
            renderer.loadModel(path: path)
        }

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if let path = state.modelPath, context.coordinator.loadedPath != path {
            context.coordinator.renderer?.loadModel(path: path)
            context.coordinator.loadedPath = path
            context.coordinator.loadedVMD = nil
        }
        if let vmdPath = state.vmdPath, context.coordinator.loadedVMD != vmdPath {
            context.coordinator.renderer?.loadAnimation(path: vmdPath)
            context.coordinator.loadedVMD = vmdPath
        }
    }

    class Coordinator: NSObject {
        var renderer: MetalMMDRenderer?
        var mtkView: MTKView?
        var loadedPath: String?
        var loadedVMD: String?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.camera.rotate(dx: Float(translation.x), dy: Float(-translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.camera.pan(dx: Float(translation.x), dy: Float(-translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let renderer = renderer else { return }
            let delta = Float(gesture.scale - 1.0) * 50.0
            renderer.camera.zoom(delta: delta)
            gesture.scale = 1.0
        }
    }
}
