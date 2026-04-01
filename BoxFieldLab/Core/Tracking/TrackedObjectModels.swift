import Foundation
import simd

enum TrackedObjectKind: String, CaseIterable, Identifiable, Sendable {
    case box

    var id: String { rawValue }
}

enum TrackingInputMode: String, CaseIterable, Identifiable {
    case manualScripted
    case replayScenario
    case objectTracking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manualScripted:
            return "Manual Scripted"
        case .replayScenario:
            return "Replay Scenario"
        case .objectTracking:
            return "Object Tracking"
        }
    }

    var isSynthetic: Bool {
        switch self {
        case .manualScripted, .replayScenario:
            return true
        case .objectTracking:
            return false
        }
    }
}

enum TrackingScenario: String, CaseIterable, Identifiable {
    case steadyOrbit
    case microJitter
    case yawFlipStress
    case temporaryLoss
    case hardLoss
    case reacquireOffset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steadyOrbit:
            return "Steady Orbit"
        case .microJitter:
            return "Micro Jitter"
        case .yawFlipStress:
            return "Yaw Flip Stress"
        case .temporaryLoss:
            return "Temporary Loss"
        case .hardLoss:
            return "Hard Loss"
        case .reacquireOffset:
            return "Reacquire Offset"
        }
    }

    var summary: String {
        switch self {
        case .steadyOrbit:
            return "Slow clean motion for baseline checks."
        case .microJitter:
            return "Mostly stationary object with small pose noise."
        case .yawFlipStress:
            return "Injects raw yaw flips to stress symmetric-box handling."
        case .temporaryLoss:
            return "Short disappearance that should recover before lost."
        case .hardLoss:
            return "Longer disappearance that should enter lost."
        case .reacquireOffset:
            return "Reappears after loss with a small position offset."
        }
    }
}

struct RawTrackedObservation: Sendable {
    let kind: TrackedObjectKind
    let observationID: UUID
    let timestamp: TimeInterval
    let rawWorldTransform: simd_float4x4
    let rawBoundingBoxCenter: SIMD3<Float>
    let rawBoundingBoxExtent: SIMD3<Float>
    let isCurrentlyDetected: Bool
}

enum TrackingLifecycleState: String, Sendable {
    case notSeen
    case tracked
    case temporarilyLost
    case lost

    var label: String {
        switch self {
        case .notSeen:
            return "Not Seen"
        case .tracked:
            return "Tracked"
        case .temporarilyLost:
            return "Temporarily Lost"
        case .lost:
            return "Lost"
        }
    }
}

struct StabilizedTrackedState: Sendable {
    let kind: TrackedObjectKind
    let timestamp: TimeInterval
    let rawWorldTransform: simd_float4x4
    let displayWorldTransform: simd_float4x4
    let rawBoundingBoxCenter: SIMD3<Float>
    let rawBoundingBoxExtent: SIMD3<Float>
    let trackingState: TrackingLifecycleState
    let lastSeenTimestamp: TimeInterval?

    static func notSeen(kind: TrackedObjectKind) -> StabilizedTrackedState {
        StabilizedTrackedState(
            kind: kind,
            timestamp: 0,
            rawWorldTransform: matrix_identity_float4x4,
            displayWorldTransform: matrix_identity_float4x4,
            rawBoundingBoxCenter: .zero,
            rawBoundingBoxExtent: .zero,
            trackingState: .notSeen,
            lastSeenTimestamp: nil
        )
    }
}

struct FieldAttachmentSpec: Sendable {
    let targetKind: TrackedObjectKind
    let localOffset: SIMD3<Float>
    let scale: Float

    static let phaseOneBox = FieldAttachmentSpec(
        targetKind: .box,
        localOffset: SIMD3<Float>(0, 0.08, 0),
        scale: 1.0
    )
}

struct StabilizerParameters: Sendable {
    var positionLerpFactor: Float = 0.18
    var positionDeadbandMeters: Float = 0.003
    var yawLerpFactor: Float = 0.16
    var yawFlipThresholdRadians: Float = .pi * 0.55
    var temporaryLossDuration: TimeInterval = 0.75

    static let defaults = StabilizerParameters()
}

struct DebugOptions {
    var showRawAnchorGizmo = true
    var showDisplayAnchorGizmo = true
    var showBoundingBox = true
    var showRawPoseGhost = true
    var showDisplayPoseGhost = true
    var showAttachmentOffsetMarker = true
    var showFieldMountMarker = true
    var showRawTrail = false
    var showDisplayTrail = false
}

struct TrackingEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: TimeInterval
    let title: String
    let detail: String

    var formattedTimestamp: String {
        String(format: "%.2fs", timestamp)
    }

    var line: String {
        "\(formattedTimestamp)  \(title): \(detail)"
    }
}

struct TrackingDebugSnapshot: Sendable {
    let rawPosition: SIMD3<Float>
    let displayPosition: SIMD3<Float>
    let rawYawDegrees: Float
    let displayYawDegrees: Float
    let rawDisplayPositionDeltaMeters: Float
    let rawDisplayYawDeltaDegrees: Float
    let lastSeenAgeSeconds: TimeInterval?
    let lifecycleState: TrackingLifecycleState
    let activeScenarioName: String
    let isSyntheticInput: Bool
    let fieldOpacity: Float

    static func empty(
        mode: TrackingInputMode,
        scenarioName: String,
        fieldOpacity: Float = 0
    ) -> TrackingDebugSnapshot {
        TrackingDebugSnapshot(
            rawPosition: .zero,
            displayPosition: .zero,
            rawYawDegrees: 0,
            displayYawDegrees: 0,
            rawDisplayPositionDeltaMeters: 0,
            rawDisplayYawDeltaDegrees: 0,
            lastSeenAgeSeconds: nil,
            lifecycleState: .notSeen,
            activeScenarioName: scenarioName,
            isSyntheticInput: mode.isSynthetic,
            fieldOpacity: fieldOpacity
        )
    }

    var formattedRawPosition: String {
        rawPosition.formattedVector
    }

    var formattedDisplayPosition: String {
        displayPosition.formattedVector
    }

    var formattedRawYaw: String {
        String(format: "%.1f°", rawYawDegrees)
    }

    var formattedDisplayYaw: String {
        String(format: "%.1f°", displayYawDegrees)
    }

    var formattedPositionDelta: String {
        String(format: "%.3f m", rawDisplayPositionDeltaMeters)
    }

    var formattedYawDelta: String {
        String(format: "%.1f°", rawDisplayYawDeltaDegrees)
    }

    var formattedLastSeenAge: String {
        guard let lastSeenAgeSeconds else {
            return "n/a"
        }
        return String(format: "%.2fs", lastSeenAgeSeconds)
    }

    var formattedFieldOpacity: String {
        String(format: "%.2f", fieldOpacity)
    }
}

struct TrackingStepResult: Sendable {
    let state: StabilizedTrackedState
    let debugSnapshot: TrackingDebugSnapshot
    let events: [TrackingEvent]
}

struct TrackingRuntimeSummary {
    let inputMode: TrackingInputMode
    let referenceAssetName: String
    let providerState: String
    let authorizationState: String
    let latestError: String?
    let objectTrackingSupported: Bool
    let activeScenarioName: String
    let isSyntheticInput: Bool

    static func initial(mode: TrackingInputMode) -> TrackingRuntimeSummary {
        TrackingRuntimeSummary(
            inputMode: mode,
            referenceAssetName: "Box.referenceObject",
            providerState: "idle",
            authorizationState: "not requested",
            latestError: nil,
            objectTrackingSupported: true,
            activeScenarioName: TrackingScenario.steadyOrbit.label,
            isSyntheticInput: mode.isSynthetic
        )
    }
}

extension SIMD3 where Scalar == Float {
    var formattedVector: String {
        String(format: "(%.3f, %.3f, %.3f)", x, y, z)
    }
}
