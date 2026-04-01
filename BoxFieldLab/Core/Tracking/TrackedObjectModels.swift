import Foundation
import simd

enum TrackedObjectKind: String, CaseIterable, Identifiable, Sendable {
    case box

    var id: String { rawValue }
}

enum TrackingInputMode: String, CaseIterable, Identifiable {
    case manualDemo
    case objectTracking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manualDemo:
            return "Manual Demo"
        case .objectTracking:
            return "Object Tracking"
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

struct DebugOptions {
    var showRawAnchorGizmo = true
    var showDisplayAnchorGizmo = true
    var showBoundingBox = true
}

struct TrackingDiagnostics {
    let rawDisplayPositionDeltaMeters: Float
    let rawDisplayYawDeltaDegrees: Float
    let fieldOpacity: Float

    static let zero = TrackingDiagnostics(
        rawDisplayPositionDeltaMeters: 0,
        rawDisplayYawDeltaDegrees: 0,
        fieldOpacity: 0
    )

    init(state: StabilizedTrackedState, fieldOpacity: Float) {
        rawDisplayPositionDeltaMeters = simd_length(
            state.rawWorldTransform.translation - state.displayWorldTransform.translation
        )
        rawDisplayYawDeltaDegrees = radiansToDegrees(
            abs(shortestAngleDifference(
                from: state.displayWorldTransform.yawRadians,
                to: state.rawWorldTransform.yawRadians
            ))
        )
        self.fieldOpacity = fieldOpacity
    }

    init(rawDisplayPositionDeltaMeters: Float, rawDisplayYawDeltaDegrees: Float, fieldOpacity: Float) {
        self.rawDisplayPositionDeltaMeters = rawDisplayPositionDeltaMeters
        self.rawDisplayYawDeltaDegrees = rawDisplayYawDeltaDegrees
        self.fieldOpacity = fieldOpacity
    }

    var formattedPositionDelta: String {
        String(format: "%.3f m", rawDisplayPositionDeltaMeters)
    }

    var formattedYawDelta: String {
        String(format: "%.1f°", rawDisplayYawDeltaDegrees)
    }

    var formattedOpacity: String {
        String(format: "%.2f", fieldOpacity)
    }
}

struct TrackingRuntimeSummary {
    let inputMode: TrackingInputMode
    let referenceAssetName: String
    let providerState: String
    let authorizationState: String
    let latestError: String?
    let objectTrackingSupported: Bool

    static func initial(mode: TrackingInputMode) -> TrackingRuntimeSummary {
        TrackingRuntimeSummary(
            inputMode: mode,
            referenceAssetName: "Box.referenceObject",
            providerState: "idle",
            authorizationState: "not requested",
            latestError: nil,
            objectTrackingSupported: true
        )
    }
}
