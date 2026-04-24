import Foundation
import simd

@MainActor
final class TrackingStabilizer {
    var parameters: StabilizerParameters

    private var state: StabilizedTrackedState
    private var hasEverTracked = false
    private var predictedPosition = SIMD3<Float>.zero
    private var estimatedVelocity = SIMD3<Float>.zero
    private var lastObservationTimestamp: TimeInterval?
    private var lastPredictionTimestamp: TimeInterval?
    private var lastDeadbandEventTimestamp: TimeInterval?
    private var lastYawRejectEventTimestamp: TimeInterval?

    init(parameters: StabilizerParameters = .defaults) {
        self.parameters = parameters
        state = .notSeen(kind: .box)
    }

    func reset(for kind: TrackedObjectKind) {
        hasEverTracked = false
        predictedPosition = .zero
        estimatedVelocity = .zero
        lastObservationTimestamp = nil
        lastPredictionTimestamp = nil
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
        if state.kind != rawObservation.kind {
            reset(for: rawObservation.kind)
        }

        let previousState = state.trackingState
        var events: [TrackingEvent] = []

        let rawPosition = rawObservation.rawWorldTransform.translation
        let rawYaw = normalizeAngle(rawObservation.rawWorldTransform.yawRadians)

        if hasEverTracked == false || state.trackingState == .notSeen {
            predictedPosition = rawPosition
            estimatedVelocity = .zero
            lastObservationTimestamp = now
            lastPredictionTimestamp = now

            let displayTransform = rawObservation.kind == .phone
                ? rawObservation.rawWorldTransform.replacingTranslation(rawPosition)
                : simd_float4x4.worldUp(position: rawPosition, yaw: rawYaw)
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

        let filteredPosition = filteredPredictedPosition(
            measurement: rawPosition,
            now: now
        )
        let previousDisplayPosition = state.displayWorldTransform.translation
        let positionDelta = filteredPosition - previousDisplayPosition
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

        let displayWorldTransform = rawObservation.kind == .phone
            ? rawObservation.rawWorldTransform.replacingTranslation(nextDisplayPosition)
            : simd_float4x4.worldUp(position: nextDisplayPosition, yaw: nextDisplayYaw)

        state = StabilizedTrackedState(
            kind: rawObservation.kind,
            timestamp: now,
            rawWorldTransform: rawObservation.rawWorldTransform,
            displayWorldTransform: displayWorldTransform,
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
            let predictedDisplayTransform = nextLifecycle == .temporarilyLost
                ? transformPredictedThroughLoss(now: now)
                : state.displayWorldTransform

            state = StabilizedTrackedState(
                kind: state.kind,
                timestamp: now,
                rawWorldTransform: state.rawWorldTransform,
                displayWorldTransform: predictedDisplayTransform,
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

    private func filteredPredictedPosition(
        measurement: SIMD3<Float>,
        now: TimeInterval
    ) -> SIMD3<Float> {
        let deltaTime = clampedDeltaTime(since: lastObservationTimestamp, now: now)
        let predicted = predictedPosition + estimatedVelocity * Float(deltaTime)
        let residual = measurement - predicted

        predictedPosition = predicted + residual * parameters.predictionAlpha
        estimatedVelocity += residual * (parameters.predictionBeta / max(Float(deltaTime), 0.001))
        lastObservationTimestamp = now
        lastPredictionTimestamp = now

        let leadOffset = clampedVector(
            estimatedVelocity * Float(parameters.predictionLeadTime),
            maxLength: parameters.maxPredictionStepMeters
        )
        return predictedPosition + leadOffset
    }

    private func transformPredictedThroughLoss(now: TimeInterval) -> simd_float4x4 {
        let deltaTime = clampedDeltaTime(since: lastPredictionTimestamp, now: now)
        lastPredictionTimestamp = now

        let step = clampedVector(
            estimatedVelocity * Float(deltaTime),
            maxLength: parameters.maxPredictionStepMeters
        )
        predictedPosition += step

        return state.displayWorldTransform.replacingTranslation(predictedPosition)
    }

    private func clampedDeltaTime(since timestamp: TimeInterval?, now: TimeInterval) -> TimeInterval {
        min(max(now - (timestamp ?? now), 1.0 / 120.0), 0.25)
    }

    private func clampedVector(_ vector: SIMD3<Float>, maxLength: Float) -> SIMD3<Float> {
        let length = simd_length(vector)
        guard length > maxLength, length > 0 else {
            return vector
        }

        return vector / length * maxLength
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
            fieldOpacity: 0,
            replayElapsedSeconds: nil
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
