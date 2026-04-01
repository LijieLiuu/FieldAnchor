import Foundation
import simd

@MainActor
final class TrackingStabilizer {
    var parameters: StabilizerParameters

    private var state: StabilizedTrackedState
    private var hasEverTracked = false
    private var lastDeadbandEventTimestamp: TimeInterval?
    private var lastYawRejectEventTimestamp: TimeInterval?

    init(parameters: StabilizerParameters = .defaults) {
        self.parameters = parameters
        state = .notSeen(kind: .box)
    }

    func reset(for kind: TrackedObjectKind) {
        hasEverTracked = false
        lastDeadbandEventTimestamp = nil
        lastYawRejectEventTimestamp = nil
        state = .notSeen(kind: kind)
    }

    func advance(rawObservation: RawTrackedObservation?, now: TimeInterval) -> TrackingStepResult {
        if let rawObservation, rawObservation.isCurrentlyDetected {
            return advanceWithObservation(rawObservation, now: now)
        }

        return advanceWithoutObservation(now: now)
    }

    private func advanceWithObservation(
        _ rawObservation: RawTrackedObservation,
        now: TimeInterval
    ) -> TrackingStepResult {
        let previousState = state.trackingState
        var events: [TrackingEvent] = []

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
            events.append(
                TrackingEvent(
                    timestamp: now,
                    title: "First Detection",
                    detail: "First raw observation entered the tracking pipeline."
                )
            )
            events.append(stateTransitionEvent(from: previousState, to: .tracked, at: now))
            return makeStepResult(now: now, events: events)
        }

        let previousDisplayPosition = state.displayWorldTransform.translation
        let positionDelta = rawPosition - previousDisplayPosition
        let nextDisplayPosition: SIMD3<Float>

        if simd_length(positionDelta) > parameters.positionDeadbandMeters {
            nextDisplayPosition = previousDisplayPosition + positionDelta * parameters.positionLerpFactor
        } else {
            nextDisplayPosition = previousDisplayPosition
            if shouldEmit(now: now, lastTimestamp: &lastDeadbandEventTimestamp) {
                events.append(
                    TrackingEvent(
                        timestamp: now,
                        title: "Deadband Suppressed",
                        detail: String(
                            format: "Position delta %.4fm stayed under %.4fm.",
                            simd_length(positionDelta),
                            parameters.positionDeadbandMeters
                        )
                    )
                )
            }
        }

        let previousDisplayYaw = state.displayWorldTransform.yawRadians
        let yawDelta = shortestAngleDifference(from: previousDisplayYaw, to: rawYaw)
        let nextDisplayYaw: Float

        if abs(yawDelta) <= parameters.yawFlipThresholdRadians {
            nextDisplayYaw = normalizeAngle(previousDisplayYaw + yawDelta * parameters.yawLerpFactor)
        } else {
            nextDisplayYaw = previousDisplayYaw
            if shouldEmit(now: now, lastTimestamp: &lastYawRejectEventTimestamp) {
                events.append(
                    TrackingEvent(
                        timestamp: now,
                        title: "Yaw Flip Rejected",
                        detail: String(
                            format: "Rejected %.1f° yaw jump beyond %.1f° threshold.",
                            radiansToDegrees(abs(yawDelta)),
                            radiansToDegrees(parameters.yawFlipThresholdRadians)
                        )
                    )
                )
            }
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

        if previousState == .temporarilyLost {
            events.append(
                TrackingEvent(
                    timestamp: now,
                    title: "Reacquired",
                    detail: "Object returned during the temporary-loss freeze window."
                )
            )
        }

        if previousState != .tracked {
            events.append(stateTransitionEvent(from: previousState, to: .tracked, at: now))
        }

        return makeStepResult(now: now, events: events)
    }

    private func advanceWithoutObservation(now: TimeInterval) -> TrackingStepResult {
        let previousState = state.trackingState
        var events: [TrackingEvent] = []

        switch state.trackingState {
        case .notSeen:
            break
        case .tracked, .temporarilyLost:
            let elapsedSinceLastSeen = now - (state.lastSeenTimestamp ?? now)
            let nextLifecycle: TrackingLifecycleState = elapsedSinceLastSeen <= parameters.temporaryLossDuration
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

            if previousState != nextLifecycle {
                events.append(stateTransitionEvent(from: previousState, to: nextLifecycle, at: now))
            }
        case .lost:
            state = StabilizedTrackedState(
                kind: state.kind,
                timestamp: now,
                rawWorldTransform: state.rawWorldTransform,
                displayWorldTransform: state.displayWorldTransform,
                rawBoundingBoxCenter: state.rawBoundingBoxCenter,
                rawBoundingBoxExtent: state.rawBoundingBoxExtent,
                trackingState: .lost,
                lastSeenTimestamp: state.lastSeenTimestamp
            )
        }

        return makeStepResult(now: now, events: events)
    }

    private func makeStepResult(now: TimeInterval, events: [TrackingEvent]) -> TrackingStepResult {
        let rawPosition = state.rawWorldTransform.translation
        let displayPosition = state.displayWorldTransform.translation
        let rawYawDegrees = radiansToDegrees(state.rawWorldTransform.yawRadians)
        let displayYawDegrees = radiansToDegrees(state.displayWorldTransform.yawRadians)

        let snapshot = TrackingDebugSnapshot(
            rawPosition: rawPosition,
            displayPosition: displayPosition,
            rawYawDegrees: rawYawDegrees,
            displayYawDegrees: displayYawDegrees,
            rawDisplayPositionDeltaMeters: simd_length(rawPosition - displayPosition),
            rawDisplayYawDeltaDegrees: radiansToDegrees(
                abs(shortestAngleDifference(
                    from: state.displayWorldTransform.yawRadians,
                    to: state.rawWorldTransform.yawRadians
                ))
            ),
            lastSeenAgeSeconds: state.lastSeenTimestamp.map { now - $0 },
            lifecycleState: state.trackingState,
            activeScenarioName: "",
            isSyntheticInput: false,
            fieldOpacity: 0
        )

        return TrackingStepResult(state: state, debugSnapshot: snapshot, events: events)
    }

    private func stateTransitionEvent(
        from oldState: TrackingLifecycleState,
        to newState: TrackingLifecycleState,
        at timestamp: TimeInterval
    ) -> TrackingEvent {
        TrackingEvent(
            timestamp: timestamp,
            title: "State Transition",
            detail: "\(oldState.label) -> \(newState.label)"
        )
    }

    private func shouldEmit(now: TimeInterval, lastTimestamp: inout TimeInterval?) -> Bool {
        let minimumInterval: TimeInterval = 0.75
        guard let previousTimestamp = lastTimestamp else {
            lastTimestamp = now
            return true
        }

        guard now - previousTimestamp >= minimumInterval else {
            return false
        }

        lastTimestamp = now
        return true
    }
}
