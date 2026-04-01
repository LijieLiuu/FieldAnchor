import Foundation
import simd

struct ManualTrackingDriver {
    private let observationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    private let bboxCenter = SIMD3<Float>(0, 0.06, 0)
    private let bboxExtent = SIMD3<Float>(0.18, 0.12, 0.18)
    private let basePosition = SIMD3<Float>(0, 1.05, -1.0)

    func observation(at time: TimeInterval) -> RawTrackedObservation {
        let x = basePosition.x + Float(sin(time * 0.55) * 0.03)
        let y = basePosition.y + Float(sin(time * 0.27) * 0.015)
        let z = basePosition.z + Float(cos(time * 0.33) * 0.02)
        let yaw = Float(sin(time * 0.42) * 0.25)
        let position = SIMD3<Float>(x, y, z)
        let transform = simd_float4x4.worldUp(position: position, yaw: yaw)

        return RawTrackedObservation(
            kind: .box,
            observationID: observationID,
            timestamp: time,
            rawWorldTransform: transform,
            rawBoundingBoxCenter: bboxCenter,
            rawBoundingBoxExtent: bboxExtent,
            isCurrentlyDetected: true
        )
    }
}
