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
            return "Replay Scenario (Recommended)"
        case .objectTracking:
            return "Object Tracking (Hardware)"
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

enum ValidationMode: String, CaseIterable, Identifiable {
    case normalField
    case diagnosticsOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normalField:
            return "Normal Field"
        case .diagnosticsOnly:
            return "Diagnostics First"
        }
    }

    var summary: String {
        switch self {
        case .normalField:
            return "Show the magnetic field together with tracking diagnostics."
        case .diagnosticsOnly:
            return "Hide the magnetic field and focus on raw vs stabilized tracking behavior."
        }
    }
}

struct ReplayPlaybackState: Sendable {
    var isPlaying: Bool
    var elapsedSeconds: TimeInterval
    var speedMultiplier: Double

    static let defaults = ReplayPlaybackState(
        isPlaying: true,
        elapsedSeconds: 0,
        speedMultiplier: 1.0
    )

    var speedLabel: String {
        String(format: "%.1fx", speedMultiplier)
    }

    var statusLabel: String {
        isPlaying ? "Playing" : "Paused"
    }

    var formattedElapsed: String {
        String(format: "%.2fs", elapsedSeconds)
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

enum StabilizerPreset: String, CaseIterable, Identifiable {
    case balanced
    case smooth
    case responsive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .smooth:
            return "Smooth"
        case .responsive:
            return "Responsive"
        }
    }

    var parameters: StabilizerParameters {
        switch self {
        case .balanced:
            return .defaults
        case .smooth:
            return StabilizerParameters(
                positionLerpFactor: 0.12,
                positionDeadbandMeters: 0.0045,
                yawLerpFactor: 0.10,
                yawFlipThresholdRadians: .pi * 0.48,
                temporaryLossDuration: 0.95
            )
        case .responsive:
            return StabilizerParameters(
                positionLerpFactor: 0.32,
                positionDeadbandMeters: 0.0015,
                yawLerpFactor: 0.28,
                yawFlipThresholdRadians: .pi * 0.70,
                temporaryLossDuration: 0.55
            )
        }
    }
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
    let replayElapsedSeconds: TimeInterval?

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
            fieldOpacity: fieldOpacity,
            replayElapsedSeconds: nil
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

    var formattedReplayElapsed: String {
        guard let replayElapsedSeconds else {
            return "n/a"
        }
        return String(format: "%.2fs", replayElapsedSeconds)
    }
}

struct TrackingMetricsSnapshot: Sendable {
    let windowDurationSeconds: TimeInterval
    let sampleCount: Int
    let maxPositionDeltaMeters: Float
    let averagePositionDeltaMeters: Float
    let maxYawDeltaDegrees: Float
    let temporaryLossCount: Int
    let recentTransitionCount: Int
    let yawRejectCount: Int

    static func empty(windowDurationSeconds: TimeInterval = 8.0) -> TrackingMetricsSnapshot {
        TrackingMetricsSnapshot(
            windowDurationSeconds: windowDurationSeconds,
            sampleCount: 0,
            maxPositionDeltaMeters: 0,
            averagePositionDeltaMeters: 0,
            maxYawDeltaDegrees: 0,
            temporaryLossCount: 0,
            recentTransitionCount: 0,
            yawRejectCount: 0
        )
    }

    var formattedWindow: String {
        String(format: "%.0fs", windowDurationSeconds)
    }

    var formattedMaxPositionDelta: String {
        String(format: "%.3f m", maxPositionDeltaMeters)
    }

    var formattedAveragePositionDelta: String {
        String(format: "%.3f m", averagePositionDeltaMeters)
    }

    var formattedMaxYawDelta: String {
        String(format: "%.1f°", maxYawDeltaDegrees)
    }
}

enum ValidationRunVerdict: String, Sendable {
    case pass
    case attention

    var label: String {
        switch self {
        case .pass:
            return "Pass"
        case .attention:
            return "Attention"
        }
    }
}

struct ValidationRunDefinition: Identifiable, Sendable {
    let scenario: TrackingScenario
    let preset: StabilizerPreset
    let durationSeconds: TimeInterval

    var id: String {
        "\(scenario.rawValue)-\(preset.rawValue)"
    }
}

struct ValidationRunResult: Identifiable, Sendable {
    let id = UUID()
    let scenario: TrackingScenario
    let preset: StabilizerPreset
    let durationSeconds: TimeInterval
    let averagePositionDeltaMeters: Float
    let maxPositionDeltaMeters: Float
    let maxYawDeltaDegrees: Float
    let stateTransitionCount: Int
    let yawRejectCount: Int
    let temporaryLossCount: Int
    let lostCount: Int
    let verdict: ValidationRunVerdict
    let summary: String

    var formattedDuration: String {
        String(format: "%.1fs", durationSeconds)
    }

    var formattedAveragePositionDelta: String {
        String(format: "%.3f m", averagePositionDeltaMeters)
    }

    var formattedMaxPositionDelta: String {
        String(format: "%.3f m", maxPositionDeltaMeters)
    }

    var formattedMaxYawDelta: String {
        String(format: "%.1f°", maxYawDeltaDegrees)
    }
}

struct ValidationSuiteStatus: Sendable {
    enum Phase: String, Sendable {
        case idle
        case running
        case completed

        var label: String {
            rawValue.capitalized
        }
    }

    let phase: Phase
    let currentRunIndex: Int
    let totalRuns: Int
    let currentScenarioName: String
    let currentPresetName: String
    let currentRunElapsed: TimeInterval
    let totalElapsed: TimeInterval
    let summary: String

    static let idle = ValidationSuiteStatus(
        phase: .idle,
        currentRunIndex: 0,
        totalRuns: 0,
        currentScenarioName: "n/a",
        currentPresetName: "n/a",
        currentRunElapsed: 0,
        totalElapsed: 0,
        summary: "Validation suite has not started."
    )

    var progressFraction: Double {
        guard totalRuns > 0 else {
            return 0
        }
        return Double(currentRunIndex) / Double(totalRuns)
    }

    var formattedCurrentElapsed: String {
        String(format: "%.1fs", currentRunElapsed)
    }

    var formattedTotalElapsed: String {
        String(format: "%.1fs", totalElapsed)
    }
}

struct ValidationCaseDefinition: Identifiable, Sendable {
    let scenario: TrackingScenario
    let preset: StabilizerPreset

    var id: String {
        "\(scenario.rawValue)-\(preset.rawValue)"
    }

    var label: String {
        "\(scenario.label) / \(preset.label)"
    }
}

enum ValidationVerdict: String, Sendable {
    case pass
    case warning
    case fail

    var label: String {
        rawValue.capitalized
    }
}

enum ValidationRunStatus: String, Sendable {
    case idle
    case running
    case completed
    case cancelled

    var label: String {
        rawValue.capitalized
    }
}

struct ValidationSuiteProgress: Sendable {
    let status: ValidationRunStatus
    let completedCases: Int
    let totalCases: Int
    let currentCaseLabel: String?
    let currentCaseElapsedSeconds: TimeInterval

    static let idle = ValidationSuiteProgress(
        status: .idle,
        completedCases: 0,
        totalCases: 0,
        currentCaseLabel: nil,
        currentCaseElapsedSeconds: 0
    )

    var progressLabel: String {
        "\(completedCases)/\(max(totalCases, 1))"
    }

    var formattedElapsed: String {
        String(format: "%.2fs", currentCaseElapsedSeconds)
    }
}

struct ValidationCaseResult: Identifiable, Sendable {
    let id = UUID()
    let scenario: TrackingScenario
    let preset: StabilizerPreset
    let verdict: ValidationVerdict
    let metrics: TrackingMetricsSnapshot
    let notes: String

    var title: String {
        "\(scenario.label) / \(preset.label)"
    }
}

struct ValidationSuiteSummary: Sendable {
    let totalCases: Int
    let passedCases: Int
    let warningCases: Int
    let failedCases: Int
    let bestStabilityPreset: StabilizerPreset?

    static let empty = ValidationSuiteSummary(
        totalCases: 0,
        passedCases: 0,
        warningCases: 0,
        failedCases: 0,
        bestStabilityPreset: nil
    )
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
    let validationMode: ValidationMode

    static func initial(mode: TrackingInputMode) -> TrackingRuntimeSummary {
        TrackingRuntimeSummary(
            inputMode: mode,
            referenceAssetName: "Box.referenceObject",
            providerState: "idle",
            authorizationState: "not requested",
            latestError: nil,
            objectTrackingSupported: true,
            activeScenarioName: TrackingScenario.steadyOrbit.label,
            isSyntheticInput: mode.isSynthetic,
            validationMode: .normalField
        )
    }
}

extension SIMD3 where Scalar == Float {
    var formattedVector: String {
        String(format: "(%.3f, %.3f, %.3f)", x, y, z)
    }
}
