import CoreMotion

class MotionManager {
    static let shared = MotionManager()
    private let motionManager = CMMotionManager()
    private(set) var gravity: (x: Float, y: Float, z: Float) = (0, -9.8 * 10, 0)
    private(set) var isAvailable = false

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        isAvailable = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let g = motion.gravity
            let scale: Float = 9.8 * 10
            self.gravity = (
                x: Float(g.x) * scale,
                y: Float(g.y) * scale,
                z: Float(-g.z) * scale
            )
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
