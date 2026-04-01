import Foundation
import simd

private func makeSyntheticObservation(
    observationID: UUID,
    timestamp: TimeInterval,
    position: SIMD3<Float>,
    yaw: Float,
    bboxCenter: SIMD3<Float>,
    bboxExtent: SIMD3<Float>
) -> RawTrackedObservation {
    RawTrackedObservation(
        kind: .box,
        observationID: observationID,
        timestamp: timestamp,
        rawWorldTransform: simd_float4x4.worldUp(position: position, yaw: yaw),
        rawBoundingBoxCenter: bboxCenter,
        rawBoundingBoxExtent: bboxExtent,
        isCurrentlyDetected: true
    )
}

@MainActor
protocol TrackingInputSource: AnyObject {
    var isSynthetic: Bool { get }
    var label: String { get }

    func activate() async
    func deactivate() async
    func observation(at elapsedTime: TimeInterval, absoluteTime: TimeInterval) async -> RawTrackedObservation?
}

@MainActor
final class ManualScriptedInputSource: TrackingInputSource {
    let isSynthetic = true
    let label = "Manual Scripted"

    var isEnabled = true

    private let observationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    private let bboxCenter = SIMD3<Float>(0, 0.06, 0)
    private let bboxExtent = SIMD3<Float>(0.18, 0.12, 0.18)
    private let basePosition = SIMD3<Float>(0, 1.05, -1.0)

    func activate() async {}

    func deactivate() async {}

    func observation(at elapsedTime: TimeInterval, absoluteTime: TimeInterval) async -> RawTrackedObservation? {
        guard isEnabled else {
            return nil
        }

        let x = basePosition.x + Float(sin(elapsedTime * 0.55) * 0.03)
        let y = basePosition.y + Float(sin(elapsedTime * 0.27) * 0.015)
        let z = basePosition.z + Float(cos(elapsedTime * 0.33) * 0.02)
        let yaw = Float(sin(elapsedTime * 0.42) * 0.25)

        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: SIMD3<Float>(x, y, z),
            yaw: yaw,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }
}

@MainActor
final class ReplayScenarioInputSource: TrackingInputSource {
    let isSynthetic = true
    let label = "Replay Scenario"

    var scenario: TrackingScenario = .steadyOrbit

    private let observationID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
    private let bboxCenter = SIMD3<Float>(0, 0.06, 0)
    private let bboxExtent = SIMD3<Float>(0.18, 0.12, 0.18)
    private let basePosition = SIMD3<Float>(0, 1.0, -1.0)

    func activate() async {}

    func deactivate() async {}

    func observation(at elapsedTime: TimeInterval, absoluteTime: TimeInterval) async -> RawTrackedObservation? {
        switch scenario {
        case .steadyOrbit:
            return steadyOrbit(elapsedTime: elapsedTime, absoluteTime: absoluteTime)
        case .microJitter:
            return microJitter(elapsedTime: elapsedTime, absoluteTime: absoluteTime)
        case .yawFlipStress:
            return yawFlipStress(elapsedTime: elapsedTime, absoluteTime: absoluteTime)
        case .temporaryLoss:
            return temporaryLoss(elapsedTime: elapsedTime, absoluteTime: absoluteTime)
        case .hardLoss:
            return hardLoss(elapsedTime: elapsedTime, absoluteTime: absoluteTime)
        case .reacquireOffset:
            return reacquireOffset(elapsedTime: elapsedTime, absoluteTime: absoluteTime)
        }
    }

    private func steadyOrbit(elapsedTime: TimeInterval, absoluteTime: TimeInterval) -> RawTrackedObservation {
        let x = basePosition.x + Float(sin(elapsedTime * 0.45) * 0.07)
        let y = basePosition.y + Float(sin(elapsedTime * 0.20) * 0.01)
        let z = basePosition.z + Float(cos(elapsedTime * 0.30) * 0.04)
        let yaw = Float(sin(elapsedTime * 0.35) * 0.32)
        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: SIMD3<Float>(x, y, z),
            yaw: yaw,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }

    private func microJitter(elapsedTime: TimeInterval, absoluteTime: TimeInterval) -> RawTrackedObservation {
        let jitterX = Float(sin(elapsedTime * 14.0) * 0.004 + sin(elapsedTime * 23.0) * 0.002)
        let jitterY = Float(sin(elapsedTime * 11.0) * 0.002)
        let jitterZ = Float(cos(elapsedTime * 17.0) * 0.004 + sin(elapsedTime * 29.0) * 0.0015)
        let yaw = Float(sin(elapsedTime * 12.0) * 0.03 + cos(elapsedTime * 21.0) * 0.02)

        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: basePosition + SIMD3<Float>(jitterX, jitterY, jitterZ),
            yaw: yaw,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }

    private func yawFlipStress(elapsedTime: TimeInterval, absoluteTime: TimeInterval) -> RawTrackedObservation {
        let x = basePosition.x + Float(sin(elapsedTime * 0.55) * 0.04)
        let z = basePosition.z + Float(cos(elapsedTime * 0.40) * 0.03)
        let baseYaw = Float(sin(elapsedTime * 0.33) * 0.18)
        let phase = elapsedTime.truncatingRemainder(dividingBy: 5.5)
        let injectedYaw = phase > 2.4 && phase < 2.8 ? baseYaw + .pi : baseYaw

        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: SIMD3<Float>(x, basePosition.y, z),
            yaw: injectedYaw,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }

    private func temporaryLoss(elapsedTime: TimeInterval, absoluteTime: TimeInterval) -> RawTrackedObservation? {
        let phase = elapsedTime.truncatingRemainder(dividingBy: 6.0)
        guard phase < 3.8 || phase > 4.25 else {
            return nil
        }

        let x = basePosition.x + Float(sin(elapsedTime * 0.35) * 0.02)
        let yaw = Float(sin(elapsedTime * 0.26) * 0.18)
        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: SIMD3<Float>(x, basePosition.y, basePosition.z),
            yaw: yaw,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }

    private func hardLoss(elapsedTime: TimeInterval, absoluteTime: TimeInterval) -> RawTrackedObservation? {
        let phase = elapsedTime.truncatingRemainder(dividingBy: 7.0)
        guard phase < 3.0 || phase > 4.3 else {
            return nil
        }

        let z = basePosition.z + Float(cos(elapsedTime * 0.22) * 0.02)
        let yaw = Float(sin(elapsedTime * 0.18) * 0.14)
        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: SIMD3<Float>(basePosition.x, basePosition.y, z),
            yaw: yaw,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }

    private func reacquireOffset(elapsedTime: TimeInterval, absoluteTime: TimeInterval) -> RawTrackedObservation? {
        let phase = elapsedTime.truncatingRemainder(dividingBy: 7.5)
        guard phase < 3.1 || phase > 4.0 else {
            return nil
        }

        let hasOffset = phase >= 4.0
        let offset = hasOffset ? SIMD3<Float>(0.07, 0.0, 0.04) : .zero
        let yawOffset: Float = hasOffset ? 0.22 : 0.0
        let x = basePosition.x + Float(sin(elapsedTime * 0.25) * 0.01)

        return makeSyntheticObservation(
            observationID: observationID,
            timestamp: absoluteTime,
            position: SIMD3<Float>(x, basePosition.y, basePosition.z) + offset,
            yaw: yawOffset,
            bboxCenter: bboxCenter,
            bboxExtent: bboxExtent
        )
    }
}

@MainActor
final class ObjectTrackingInputSource: TrackingInputSource {
    let isSynthetic = false
    let label = "Object Tracking"

    private let trackingCoordinator: TrackingCoordinator

    init(trackingCoordinator: TrackingCoordinator) {
        self.trackingCoordinator = trackingCoordinator
    }

    func activate() async {
        await trackingCoordinator.startTracking()
    }

    func deactivate() async {
        await trackingCoordinator.stop()
    }

    func observation(at elapsedTime: TimeInterval, absoluteTime: TimeInterval) async -> RawTrackedObservation? {
        let _ = elapsedTime
        let _ = absoluteTime
        return trackingCoordinator.latestObservation
    }
}
