import Foundation
import simd

class Camera {
    var distance: Float = 20.0
    var azimuth: Float = 0.0       // yaw in degrees
    var elevation: Float = 10.0    // pitch in degrees
    var target: SIMD3<Float> = SIMD3<Float>(0, 10, 0)

    var viewMatrix: simd_float4x4 {
        let azRad = azimuth * .pi / 180.0
        let elRad = elevation * .pi / 180.0

        let cosEl = cos(elRad)
        let sinEl = sin(elRad)
        let cosAz = cos(azRad)
        let sinAz = sin(azRad)

        let eye = target + SIMD3<Float>(
            distance * cosEl * sinAz,
            distance * sinEl,
            distance * cosEl * cosAz
        )

        return Camera.lookAt(eye: eye, center: target, up: SIMD3<Float>(0, 1, 0))
    }

    var cameraPosition: SIMD3<Float> {
        let azRad = azimuth * .pi / 180.0
        let elRad = elevation * .pi / 180.0
        let cosEl = cos(elRad)
        return target + SIMD3<Float>(
            distance * cosEl * sin(azRad),
            distance * sin(elRad),
            distance * cosEl * cos(azRad)
        )
    }

    func rotate(dx: Float, dy: Float) {
        azimuth += dx * 0.5
        elevation = max(-89, min(89, elevation + dy * 0.5))
    }

    func zoom(delta: Float) {
        distance = max(1.0, distance * (1.0 - delta * 0.01))
    }

    func pan(dx: Float, dy: Float) {
        let azRad = azimuth * .pi / 180.0
        let right = SIMD3<Float>(cos(azRad), 0, -sin(azRad))
        let up = SIMD3<Float>(0, 1, 0)
        let scale: Float = distance * 0.002
        target += right * (-dx * scale) + up * (dy * scale)
    }

    // MARK: - Matrix Helpers

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        var m = matrix_identity_float4x4
        m[0][0] = s.x;  m[1][0] = s.y;  m[2][0] = s.z;  m[3][0] = -dot(s, eye)
        m[0][1] = u.x;  m[1][1] = u.y;  m[2][1] = u.z;  m[3][1] = -dot(u, eye)
        m[0][2] = -f.x; m[1][2] = -f.y; m[2][2] = -f.z; m[3][2] =  dot(f, eye)
        return m
    }

    static func perspective(fovYDegrees: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let fovRad = fovYDegrees * .pi / 180.0
        let y = 1.0 / tan(fovRad * 0.5)
        let x = y / aspect
        let z = far / (near - far)

        var m = simd_float4x4(0)
        m[0][0] = x
        m[1][1] = y
        m[2][2] = z
        m[2][3] = -1.0
        m[3][2] = z * near
        return m
    }
}
