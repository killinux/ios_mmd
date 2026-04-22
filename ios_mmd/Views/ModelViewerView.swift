import SwiftUI
import MetalKit

struct ModelViewerView: UIViewRepresentable {
    let modelPath: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.preferredFramesPerSecond = 60

        guard let renderer = MetalMMDRenderer(mtkView: mtkView) else {
            fatalError("Failed to initialize MetalMMDRenderer")
        }

        mtkView.delegate = renderer
        context.coordinator.renderer = renderer

        // Gesture recognizers
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

        if let path = modelPath {
            renderer.loadModel(path: path)
        }

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if let path = modelPath, context.coordinator.loadedPath != path {
            context.coordinator.renderer?.loadModel(path: path)
            context.coordinator.loadedPath = path
        }
    }

    class Coordinator: NSObject {
        var renderer: MetalMMDRenderer?
        var loadedPath: String?

        private var lastPanLocation: CGPoint = .zero
        private var lastTwoFingerLocation: CGPoint = .zero

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
