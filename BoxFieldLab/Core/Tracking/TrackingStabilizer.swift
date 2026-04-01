import Foundation
import simd

@MainActor
final class TrackingStabilizer {
    struct Configuration {
        var positionLerpFactor: Float = 0.18
        var positionDeadbandMeters: Float = 0.003
        var yawLerpFactor: Float = 0.16
        var yawFlipThresholdRadians: Float = .pi * 0.55
        var temporaryLossDuration: TimeInterval = 0.75
    }

    private let configuration: Configuration
    private var state: StabilizedTrackedState
    private var hasEverTracked = false

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.state = .notSeen(kind: .box)
    }

    func reset(for kind: TrackedObjectKind) {
        hasEverTracked = false
        state = .notSeen(kind: kind)
    }

    func advance(rawObservation: RawTrackedObservation?, now: TimeInterval) -> StabilizedTrackedState {
        guard let rawObservation, rawObservation.isCurrentlyDetected else {
            return advanceWithoutObservation(now: now)
        }

        let rawPosition = rawObservation.rawWorldTransform.translation
        let rawYaw = normalizeAngle(rawObservation.rawWorldTransform.yawRadians)

        if hasEverTracked == false || state.trackingState == .notSeen {
            let displayTransform = simd_float4x4.worldUp(position: rawPosition, yaw: rawYaw)
            hasEverTracked = true
            state = StabilizedTrackedState(
                kind: rawObservation.kind,
                timestamp: now,
                rawWorldTransform: rawObservation.rawWorldTransform,
                displayWorldTransform: displayTransform,
                rawBoundingBoxCenter: rawObservation.rawBoundingBoxCenter,
                rawBoundingBoxExtent: rawObservation.rawBoundingBoxExtent,
                trackingState: .tracked,
                lastSeenTimestamp: now
            )
            return state
        }

        let previousDisplayPosition = state.displayWorldTransform.translation
        let positionDelta = rawPosition - previousDisplayPosition
        let nextDisplayPosition: SIMD3<Float>

        if simd_length(positionDelta) > configuration.positionDeadbandMeters {
            nextDisplayPosition = previousDisplayPosition + positionDelta * configuration.positionLerpFactor
        } else {
            nextDisplayPosition = previousDisplayPosition
        }

        let previousDisplayYaw = state.displayWorldTransform.yawRadians
        let yawDelta = shortestAngleDifference(from: previousDisplayYaw, to: rawYaw)
        let nextDisplayYaw: Float

        if abs(yawDelta) <= configuration.yawFlipThresholdRadians {
            nextDisplayYaw = normalizeAngle(previousDisplayYaw + yawDelta * configuration.yawLerpFactor)
        } else {
            nextDisplayYaw = previousDisplayYaw
        }

        state = StabilizedTrackedState(
            kind: rawObservation.kind,
            timestamp: now,
            rawWorldTransform: rawObservation.rawWorldTransform,
            displayWorldTransform: simd_float4x4.worldUp(position: nextDisplayPosition, yaw: nextDisplayYaw),
            rawBoundingBoxCenter: rawObservation.rawBoundingBoxCenter,
            rawBoundingBoxExtent: rawObservation.rawBoundingBoxExtent,
            trackingState: .tracked,
            lastSeenTimestamp: now
        )
        return state
    }

    private func advanceWithoutObservation(now: TimeInterval) -> StabilizedTrackedState {
        switch state.trackingState {
        case .notSeen:
            return state
        case .tracked, .temporarilyLost:
            let elapsedSinceLastSeen = now - (state.lastSeenTimestamp ?? now)
            let nextLifecycle: TrackingLifecycleState = elapsedSinceLastSeen <= configuration.temporaryLossDuration
                ? .temporarilyLost
                : .lost

            state = StabilizedTrackedState(
                kind: state.kind,
                timestamp: now,
                rawWorldTransform: state.rawWorldTransform,
                displayWorldTransform: state.displayWorldTransform,
                rawBoundingBoxCenter: state.rawBoundingBoxCenter,
                rawBoundingBoxExtent: state.rawBoundingBoxExtent,
                trackingState: nextLifecycle,
                lastSeenTimestamp: state.lastSeenTimestamp
            )
            return state
        case .lost:
            return state
        }
    }
}
