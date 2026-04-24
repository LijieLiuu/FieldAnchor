import Foundation
import simd

extension simd_float4x4 {
    static func worldUp(position: SIMD3<Float>, yaw: Float) -> simd_float4x4 {
        let rotation = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)))
        var transform = rotation
        transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return transform
    }

    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }

    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let homogenous = self * SIMD4<Float>(point.x, point.y, point.z, 1)
        return SIMD3<Float>(homogenous.x, homogenous.y, homogenous.z)
    }

    func replacingTranslation(_ translation: SIMD3<Float>) -> simd_float4x4 {
        var transform = self
        transform.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        return transform
    }

    var yawRadians: Float {
        let forward = SIMD3<Float>(columns.2.x, 0, columns.2.z)
        if simd_length_squared(forward) < 0.000_001 {
            return 0
        }

        let normalizedForward = simd_normalize(forward)
        return atan2(normalizedForward.x, normalizedForward.z)
    }
}

func shortestAngleDifference(from start: Float, to end: Float) -> Float {
    normalizeAngle(end - start)
}

func normalizeAngle(_ angle: Float) -> Float {
    var normalized = fmod(angle + .pi, .pi * 2)
    if normalized < 0 {
        normalized += .pi * 2
    }
    return normalized - .pi
}

func radiansToDegrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}
