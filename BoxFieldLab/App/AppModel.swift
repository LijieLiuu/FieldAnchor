import QuartzCore
import RealityKit
import SwiftUI

private struct MetricsSample {
    let timestamp: TimeInterval
    let positionDeltaMeters: Float
    let yawDeltaDegrees: Float
}

private struct ValidationRunAccumulator {
    var sampleCount = 0
    var positionDeltaSum: Float = 0
    var maxPositionDeltaMeters: Float = 0
    var maxYawDeltaDegrees: Float = 0
    var stateTransitionCount = 0
    var yawRejectCount = 0
    var temporaryLossCount = 0
    var lostCount = 0
}

@MainActor
final class AppModel: ObservableObject {
    static let immersiveSpaceID = "TrackingImmersiveSpace"
    static let maxTimelineEvents = 12
    static let metricsWindowDuration: TimeInterval = 8.0

    @Published var inputMode: TrackingInputMode = .replayScenario
    @Published var selectedScenario: TrackingScenario = .steadyOrbit
    @Published var validationMode: ValidationMode = .normalField
    @Published var debugOptions = DebugOptions()
    @Published var manualObjectVisible = true
    @Published var stabilizerParameters = StabilizerParameters.defaults
    @Published private(set) var replayPlaybackState = ReplayPlaybackState.defaults
    @Published private(set) var appliedPreset: StabilizerPreset? = .balanced
    @Published private(set) var debugSnapshot = TrackingDebugSnapshot.empty(
        mode: .replayScenario,
        scenarioName: TrackingScenario.steadyOrbit.label
    )
    @Published private(set) var runtimeSummary = TrackingRuntimeSummary.initial(mode: .replayScenario)
    @Published private(set) var stabilizedState = StabilizedTrackedState.notSeen(kind: .box)
    @Published private(set) var metricsSnapshot = TrackingMetricsSnapshot.empty(
        windowDurationSeconds: 8.0
    )
    @Published private(set) var trackingTimeline: [TrackingEvent] = []
    @Published private(set) var validationSuiteStatus = ValidationSuiteStatus.idle
    @Published private(set) var validationResults: [ValidationRunResult] = []
    @Published private(set) var validationOverview = ValidationOverview.empty
    @Published private(set) var validationAttentionResults: [ValidationRunResult] = []
    @Published private(set) var validationPresetSummaries: [ValidationPresetSummary] = []
    @Published private(set) var validationRecommendation = "Run the validation suite to compare presets automatically."
    @Published private(set) var validationReportText = "Run the validation suite to generate a readable validation report."
    @Published private(set) var fieldVisualSourceName = "Loading field asset..."

    let sceneRootEntity = Entity()
    private static let objectTrackingActivationDelay: Duration = .milliseconds(700)

    private let referenceCatalog = ReferenceObjectCatalog()
    private lazy var trackingCoordinator = TrackingCoordinator(referenceCatalog: referenceCatalog)
    private lazy var objectTrackingInputSource = ObjectTrackingInputSource(trackingCoordinator: trackingCoordinator)
    private let manualInputSource = ManualScriptedInputSource()
    private let replayInputSource = ReplayScenarioInputSource()
    private let trackingStabilizer: TrackingStabilizer
    private let fieldRenderer = FieldRenderer()

    private var immersiveSpaceOpened = false
    private var runtimeLoopTask: Task<Void, Never>?
    private var inputClockOrigin: TimeInterval?
    private var lastTickTime: TimeInterval?
    private var metricsSamples: [MetricsSample] = []
    private var metricsEvents: [TrackingEvent] = []
    private var validationDefinitions: [ValidationRunDefinition] = []
    private var validationCurrentIndex = 0
    private var validationSuiteStartTime: TimeInterval?
    private var validationAccumulator: ValidationRunAccumulator?

    init() {
        trackingStabilizer = TrackingStabilizer(parameters: .defaults)
        sceneRootEntity.name = "SceneRoot"
        sceneRootEntity.addChild(fieldRenderer.rootEntity)
        refreshRuntimeSummary()
    }

    deinit {
        runtimeLoopTask?.cancel()
    }

    func activate(openImmersiveSpace: OpenImmersiveSpaceAction) async {
        await fieldRenderer.loadPreferredFieldVisualIfNeeded()
        fieldVisualSourceName = fieldRenderer.fieldVisualSourceName

        if immersiveSpaceOpened == false {
            _ = await openImmersiveSpace(id: Self.immersiveSpaceID)
            immersiveSpaceOpened = true
        }

        await startRuntimeLoopIfNeeded()
    }

    func sceneInstalled() {
        fieldRenderer.update(
            state: stabilizedState,
            debugOptions: debugOptions,
            runtimeSummary: runtimeSummary,
            validationMode: validationMode,
            now: CACurrentMediaTime()
        )
    }

    func startRuntimeLoopIfNeeded() async {
        guard runtimeLoopTask == nil else {
            return
        }

        await resetActiveInputSource(resetTimeline: true, resetClock: true)

        runtimeLoopTask = Task { [weak self] in
            guard let self else {
                return
            }

            while Task.isCancelled == false {
                await self.tick(now: CACurrentMediaTime())
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func setInputMode(_ mode: TrackingInputMode) {
        guard inputMode != mode else {
            return
        }

        inputMode = mode
        if mode != .replayScenario {
            replayPlaybackState = ReplayPlaybackState.defaults
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.resetActiveInputSource(resetTimeline: true, resetClock: true)
            await self.tick(now: CACurrentMediaTime())
        }
    }

    func setScenario(_ scenario: TrackingScenario) {
        guard selectedScenario != scenario else {
            return
        }

        selectedScenario = scenario
        replayInputSource.scenario = scenario
        restartReplayState(resetInputClock: false)

        Task { [weak self] in
            guard let self else {
                return
            }
            await self.tick(now: CACurrentMediaTime())
        }
    }

    func setValidationMode(_ mode: ValidationMode) {
        validationMode = mode
    }

    func startValidationSuite() {
        validationDefinitions = Self.makeValidationDefinitions()
        validationResults.removeAll()
        validationOverview = .empty
        validationAttentionResults = []
        validationPresetSummaries = []
        validationReportText = "Validation suite is running. The report will appear when the full matrix completes."
        validationRecommendation = "Validation suite is running."
        validationCurrentIndex = 0
        validationSuiteStartTime = CACurrentMediaTime()

        inputMode = .replayScenario
        validationMode = .diagnosticsOnly
        replayInputSource.scenario = selectedScenario

        beginValidationRun(at: 0)
    }

    func stopValidationSuite() {
        validationDefinitions.removeAll()
        validationAccumulator = nil
        validationCurrentIndex = 0
        validationSuiteStartTime = nil
        validationSuiteStatus = .idle
        refreshValidationPresentation()
        validationRecommendation = "Validation suite stopped."
    }

    func toggleReplayPlayback() {
        guard inputMode == .replayScenario else {
            return
        }
        replayPlaybackState.isPlaying.toggle()
    }

    func restartReplay() {
        restartReplayState(resetInputClock: false)
    }

    func setReplaySpeed(_ speedMultiplier: Double) {
        replayPlaybackState.speedMultiplier = speedMultiplier
    }

    func applyPreset(_ preset: StabilizerPreset) {
        stabilizerParameters = preset.parameters
        trackingStabilizer.parameters = preset.parameters
        appliedPreset = preset
    }

    func resetParametersToDefaults() {
        stabilizerParameters = .defaults
        trackingStabilizer.parameters = .defaults
        appliedPreset = .balanced
    }

    func updateStabilizerParameters(_ update: (inout StabilizerParameters) -> Void) {
        var nextParameters = stabilizerParameters
        update(&nextParameters)
        stabilizerParameters = nextParameters
        trackingStabilizer.parameters = nextParameters
        appliedPreset = nil
    }

    private func tick(now: TimeInterval) async {
        let deltaTime = max(now - (lastTickTime ?? now), 0)
        lastTickTime = now

        manualInputSource.isEnabled = manualObjectVisible
        replayInputSource.scenario = selectedScenario
        trackingStabilizer.parameters = stabilizerParameters

        if inputMode == .replayScenario, replayPlaybackState.isPlaying {
            replayPlaybackState.elapsedSeconds += deltaTime * replayPlaybackState.speedMultiplier
        }

        let rawObservation = await currentRawObservation(at: now)
        let stepResult = trackingStabilizer.advance(rawObservation: rawObservation, now: now)
        stabilizedState = stepResult.state

        fieldRenderer.update(
            state: stabilizedState,
            debugOptions: debugOptions,
            runtimeSummary: runtimeSummary,
            validationMode: validationMode,
            now: now
        )

        appendTimelineEvents(stepResult.events)
        accumulateMetrics(from: stepResult, now: now)
        advanceValidationSuite(with: stepResult, now: now)
        refreshRuntimeSummary()
        debugSnapshot = enrich(
            snapshot: stepResult.debugSnapshot,
            fieldOpacity: fieldRenderer.currentOpacity
        )
        metricsSnapshot = makeMetricsSnapshot()
    }

    private func currentRawObservation(at now: TimeInterval) async -> RawTrackedObservation? {
        let elapsedTime: TimeInterval
        if inputMode == .replayScenario {
            elapsedTime = replayPlaybackState.elapsedSeconds
        } else {
            let clockOrigin = inputClockOrigin ?? now
            elapsedTime = now - clockOrigin
        }
        return await activeInputSource.observation(at: elapsedTime, absoluteTime: now)
    }

    private var activeInputSource: TrackingInputSource {
        switch inputMode {
        case .manualScripted:
            return manualInputSource
        case .replayScenario:
            return replayInputSource
        case .objectTracking:
            return objectTrackingInputSource
        }
    }

    private func resetActiveInputSource(resetTimeline: Bool, resetClock: Bool) async {
        await manualInputSource.deactivate()
        await replayInputSource.deactivate()
        await objectTrackingInputSource.deactivate()

        if resetTimeline {
            trackingTimeline.removeAll()
            metricsEvents.removeAll()
            metricsSamples.removeAll()
            metricsSnapshot = TrackingMetricsSnapshot.empty(windowDurationSeconds: Self.metricsWindowDuration)
        }
        if resetClock {
            let currentTime = CACurrentMediaTime()
            inputClockOrigin = currentTime
            lastTickTime = currentTime
            if inputMode == .replayScenario {
                replayPlaybackState = ReplayPlaybackState.defaults
            }
        }

        trackingStabilizer.reset(for: .box)
        if inputMode == .objectTracking {
            try? await Task.sleep(for: Self.objectTrackingActivationDelay)
        }
        await activeInputSource.activate()
    }

    private func appendTimelineEvents(_ events: [TrackingEvent]) {
        guard events.isEmpty == false else {
            return
        }

        trackingTimeline = Array((events.reversed() + trackingTimeline).prefix(Self.maxTimelineEvents))
    }

    private func refreshRuntimeSummary() {
        runtimeSummary = TrackingRuntimeSummary(
            inputMode: inputMode,
            referenceAssetNames: referenceCatalog.descriptorAvailabilitySummary(),
            providerState: trackingCoordinator.status.providerState,
            authorizationState: trackingCoordinator.status.authorizationState,
            latestError: trackingCoordinator.status.latestError,
            objectTrackingSupported: trackingCoordinator.status.objectTrackingSupported,
            activeScenarioName: inputMode == .replayScenario ? selectedScenario.label : "n/a",
            isSyntheticInput: inputMode.isSynthetic,
            validationMode: validationMode
        )
    }

    private func enrich(snapshot: TrackingDebugSnapshot, fieldOpacity: Float) -> TrackingDebugSnapshot {
        TrackingDebugSnapshot(
            rawPosition: snapshot.rawPosition,
            displayPosition: snapshot.displayPosition,
            rawYawDegrees: snapshot.rawYawDegrees,
            displayYawDegrees: snapshot.displayYawDegrees,
            rawDisplayPositionDeltaMeters: snapshot.rawDisplayPositionDeltaMeters,
            rawDisplayYawDeltaDegrees: snapshot.rawDisplayYawDeltaDegrees,
            lastSeenAgeSeconds: snapshot.lastSeenAgeSeconds,
            lifecycleState: snapshot.lifecycleState,
            activeScenarioName: inputMode == .replayScenario ? selectedScenario.label : "n/a",
            isSyntheticInput: inputMode.isSynthetic,
            fieldOpacity: fieldOpacity,
            replayElapsedSeconds: inputMode == .replayScenario ? replayPlaybackState.elapsedSeconds : nil
        )
    }

    private func restartReplayState(resetInputClock: Bool) {
        trackingTimeline.removeAll()
        metricsEvents.removeAll()
        metricsSamples.removeAll()
        metricsSnapshot = TrackingMetricsSnapshot.empty(windowDurationSeconds: Self.metricsWindowDuration)
        replayPlaybackState = ReplayPlaybackState.defaults
        trackingStabilizer.reset(for: .box)
        if resetInputClock {
            inputClockOrigin = CACurrentMediaTime()
        }
        lastTickTime = CACurrentMediaTime()
    }

    private func accumulateMetrics(from stepResult: TrackingStepResult, now: TimeInterval) {
        metricsSamples.append(
            MetricsSample(
                timestamp: now,
                positionDeltaMeters: stepResult.debugSnapshot.rawDisplayPositionDeltaMeters,
                yawDeltaDegrees: stepResult.debugSnapshot.rawDisplayYawDeltaDegrees
            )
        )
        metricsEvents.append(contentsOf: stepResult.events)

        let cutoff = now - Self.metricsWindowDuration
        metricsSamples.removeAll { $0.timestamp < cutoff }
        metricsEvents.removeAll { $0.timestamp < cutoff }
    }

    private func makeMetricsSnapshot() -> TrackingMetricsSnapshot {
        guard metricsSamples.isEmpty == false else {
            return TrackingMetricsSnapshot.empty(windowDurationSeconds: Self.metricsWindowDuration)
        }

        let positionValues = metricsSamples.map(\.positionDeltaMeters)
        let yawValues = metricsSamples.map(\.yawDeltaDegrees)
        let averagePosition = positionValues.reduce(0, +) / Float(positionValues.count)
        let transitionCount = metricsEvents.filter { $0.title == "State Transition" }.count
        let yawRejectCount = metricsEvents.filter { $0.title == "Yaw Flip Rejected" }.count
        let temporaryLossCount = metricsEvents.filter {
            guard $0.title == "State Transition",
                  let (_, newState) = parseStateTransition(from: $0.detail) else {
                return false
            }

            return newState == .temporarilyLost
        }.count

        return TrackingMetricsSnapshot(
            windowDurationSeconds: Self.metricsWindowDuration,
            sampleCount: metricsSamples.count,
            maxPositionDeltaMeters: positionValues.max() ?? 0,
            averagePositionDeltaMeters: averagePosition,
            maxYawDeltaDegrees: yawValues.max() ?? 0,
            temporaryLossCount: temporaryLossCount,
            recentTransitionCount: transitionCount,
            yawRejectCount: yawRejectCount
        )
    }

    private func advanceValidationSuite(with stepResult: TrackingStepResult, now: TimeInterval) {
        guard validationDefinitions.isEmpty == false,
              validationCurrentIndex < validationDefinitions.count else {
            return
        }

        let definition = validationDefinitions[validationCurrentIndex]
        updateValidationStatus(now: now)
        accumulateValidation(stepResult.events, snapshot: stepResult.debugSnapshot)

        guard replayPlaybackState.elapsedSeconds >= definition.durationSeconds else {
            return
        }

        finalizeValidationRun(definition: definition)
    }

    private func accumulateValidation(_ events: [TrackingEvent], snapshot: TrackingDebugSnapshot) {
        guard var accumulator = validationAccumulator else {
            return
        }

        accumulator.sampleCount += 1
        accumulator.positionDeltaSum += snapshot.rawDisplayPositionDeltaMeters
        accumulator.maxPositionDeltaMeters = max(accumulator.maxPositionDeltaMeters, snapshot.rawDisplayPositionDeltaMeters)
        accumulator.maxYawDeltaDegrees = max(accumulator.maxYawDeltaDegrees, snapshot.rawDisplayYawDeltaDegrees)

        for event in events {
            switch event.title {
            case "State Transition":
                accumulator.stateTransitionCount += 1
                if let (_, newState) = parseStateTransition(from: event.detail),
                   newState == .temporarilyLost {
                    accumulator.temporaryLossCount += 1
                }
                if let (_, newState) = parseStateTransition(from: event.detail),
                   newState == .lost {
                    accumulator.lostCount += 1
                }
            case "Yaw Flip Rejected":
                accumulator.yawRejectCount += 1
            default:
                break
            }
        }

        validationAccumulator = accumulator
    }

    private func beginValidationRun(at index: Int) {
        guard validationDefinitions.indices.contains(index) else {
            completeValidationSuite()
            return
        }

        let definition = validationDefinitions[index]
        validationCurrentIndex = index
        validationAccumulator = ValidationRunAccumulator()
        selectedScenario = definition.scenario
        replayInputSource.scenario = definition.scenario
        applyPreset(definition.preset)
        restartReplayState(resetInputClock: false)
        updateValidationStatus(now: CACurrentMediaTime())
    }

    private func finalizeValidationRun(definition: ValidationRunDefinition) {
        guard let accumulator = validationAccumulator else {
            return
        }

        let averagePosition = accumulator.sampleCount > 0
            ? accumulator.positionDeltaSum / Float(accumulator.sampleCount)
            : 0
        let verdict = verdict(for: definition, accumulator: accumulator, averagePosition: averagePosition)
        let result = ValidationRunResult(
            scenario: definition.scenario,
            preset: definition.preset,
            durationSeconds: definition.durationSeconds,
            averagePositionDeltaMeters: averagePosition,
            maxPositionDeltaMeters: accumulator.maxPositionDeltaMeters,
            maxYawDeltaDegrees: accumulator.maxYawDeltaDegrees,
            stateTransitionCount: accumulator.stateTransitionCount,
            yawRejectCount: accumulator.yawRejectCount,
            temporaryLossCount: accumulator.temporaryLossCount,
            lostCount: accumulator.lostCount,
            verdict: verdict,
            summary: summary(for: definition, accumulator: accumulator, verdict: verdict)
        )

        validationResults.append(result)
        refreshValidationPresentation()
        validationAccumulator = nil

        let nextIndex = validationCurrentIndex + 1
        if nextIndex < validationDefinitions.count {
            beginValidationRun(at: nextIndex)
        } else {
            completeValidationSuite()
        }
    }

    private func completeValidationSuite() {
        replayPlaybackState.isPlaying = false
        validationCurrentIndex = validationDefinitions.count
        validationAccumulator = nil
        validationDefinitions.removeAll()
        validationSuiteStatus = ValidationSuiteStatus(
            phase: .completed,
            currentRunIndex: validationResults.count,
            totalRuns: validationResults.count,
            currentScenarioName: "n/a",
            currentPresetName: "n/a",
            currentRunElapsed: 0,
            totalElapsed: (validationSuiteStartTime.map { CACurrentMediaTime() - $0 }) ?? 0,
            summary: "Validation suite completed."
        )
        refreshValidationPresentation()
        validationRecommendation = makeValidationRecommendation()
    }

    private func updateValidationStatus(now: TimeInterval) {
        guard validationDefinitions.isEmpty == false,
              validationCurrentIndex < validationDefinitions.count else {
            return
        }

        let definition = validationDefinitions[validationCurrentIndex]
        validationSuiteStatus = ValidationSuiteStatus(
            phase: .running,
            currentRunIndex: validationCurrentIndex + 1,
            totalRuns: validationDefinitions.count,
            currentScenarioName: definition.scenario.label,
            currentPresetName: definition.preset.label,
            currentRunElapsed: replayPlaybackState.elapsedSeconds,
            totalElapsed: validationSuiteStartTime.map { now - $0 } ?? 0,
            summary: "Running \(definition.scenario.label) with \(definition.preset.label)."
        )
    }

    private func verdict(
        for definition: ValidationRunDefinition,
        accumulator: ValidationRunAccumulator,
        averagePosition: Float
    ) -> ValidationRunVerdict {
        switch definition.scenario {
        case .yawFlipStress:
            return accumulator.yawRejectCount > 0 ? .pass : .attention
        case .temporaryLoss:
            return accumulator.temporaryLossCount > 0 && accumulator.lostCount == 0 ? .pass : .attention
        case .hardLoss:
            return accumulator.lostCount > 0 ? .pass : .attention
        case .reacquireOffset:
            return averagePosition < 0.080 ? .pass : .attention
        case .steadyOrbit, .microJitter:
            return averagePosition < 0.050 && accumulator.maxYawDeltaDegrees < 35 ? .pass : .attention
        }
    }

    private func summary(
        for definition: ValidationRunDefinition,
        accumulator: ValidationRunAccumulator,
        verdict: ValidationRunVerdict
    ) -> String {
        switch definition.scenario {
        case .yawFlipStress:
            return "\(verdict.label): \(accumulator.yawRejectCount) yaw flips rejected."
        case .temporaryLoss:
            return "\(verdict.label): temporary loss count \(accumulator.temporaryLossCount), lost count \(accumulator.lostCount)."
        case .hardLoss:
            return "\(verdict.label): lost count \(accumulator.lostCount)."
        case .reacquireOffset:
            return "\(verdict.label): \(accumulator.stateTransitionCount) state transitions during offset reacquisition."
        case .steadyOrbit, .microJitter:
            return "\(verdict.label): max yaw delta \(String(format: "%.1f", accumulator.maxYawDeltaDegrees))°."
        }
    }

    private func makeValidationRecommendation() -> String {
        let ranked = rankedValidationPresets()
        guard let best = ranked.first else {
            return "No validation results available."
        }
        return "Best overall preset: \(best.0.label). Compare detailed run results below before changing hardware settings."
    }

    private func parseStateTransition(from detail: String) -> (TrackingLifecycleState, TrackingLifecycleState)? {
        let parts = detail.components(separatedBy: " -> ")
        guard parts.count == 2,
              let oldState = lifecycleState(for: parts[0]),
              let newState = lifecycleState(for: parts[1]) else {
            return nil
        }

        return (oldState, newState)
    }

    private func lifecycleState(for label: String) -> TrackingLifecycleState? {
        TrackingLifecycleState.allCases.first { $0.label == label }
    }

    private func rankedValidationPresets() -> [(StabilizerPreset, Float)] {
        let grouped = Dictionary(grouping: validationResults, by: \.preset)
        return grouped.map { preset, results -> (StabilizerPreset, Float) in
            let score = results.reduce(Float.zero) { partial, result in
                partial
                    + result.averagePositionDeltaMeters * 1000
                    + result.maxPositionDeltaMeters * 400
                    + result.maxYawDeltaDegrees * 0.7
                    + Float(result.lostCount * 20 + result.temporaryLossCount * 4)
            }
            return (preset, score / Float(results.count))
        }
        .sorted { $0.1 < $1.1 }
    }

    private func refreshValidationPresentation() {
        guard validationResults.isEmpty == false else {
            validationOverview = .empty
            validationAttentionResults = []
            validationPresetSummaries = []
            validationReportText = "Run the validation suite to generate a readable validation report."
            return
        }

        let passCount = validationResults.filter { $0.verdict == .pass }.count
        let attentionResults = validationResults.filter { $0.verdict == .attention }
        let attentionCount = attentionResults.count
        let totalRuns = validationResults.count
        let rankedPresets = rankedValidationPresets()
        let bestPresetName = rankedPresets.first?.0.label ?? "n/a"
        let primaryConcern = makePrimaryConcern(from: attentionResults)

        validationOverview = ValidationOverview(
            overallAssessment: makeOverallAssessment(passCount: passCount, attentionCount: attentionCount, totalRuns: totalRuns),
            bestPresetName: bestPresetName,
            totalRuns: totalRuns,
            passCount: passCount,
            attentionCount: attentionCount,
            primaryConcern: primaryConcern
        )
        validationAttentionResults = attentionResults
        validationPresetSummaries = StabilizerPreset.allCases.compactMap { preset in
            let results = validationResults.filter { $0.preset == preset }
            guard results.isEmpty == false else {
                return nil
            }

            let averagePosition = results.reduce(Float.zero) { $0 + $1.averagePositionDeltaMeters } / Float(results.count)
            let averageYaw = results.reduce(Float.zero) { $0 + $1.maxYawDeltaDegrees } / Float(results.count)
            let passCount = results.filter { $0.verdict == .pass }.count
            let attentionCount = results.count - passCount

            return ValidationPresetSummary(
                preset: preset,
                passCount: passCount,
                attentionCount: attentionCount,
                averagePositionDeltaMeters: averagePosition,
                averageMaxYawDeltaDegrees: averageYaw
            )
        }
        validationReportText = makeValidationReport(
            totalRuns: totalRuns,
            passCount: passCount,
            attentionResults: attentionResults,
            bestPresetName: bestPresetName
        )
    }

    private func makeOverallAssessment(passCount: Int, attentionCount: Int, totalRuns: Int) -> String {
        if attentionCount == 0 {
            return "Qualified for the current simulator-only phase."
        }
        if totalRuns > 0, passCount * 100 / totalRuns >= 80 {
            return "Mostly qualified for simulator validation. Fix the remaining attention items before moving to hardware."
        }
        return "Not yet qualified. Too many attention items remain in the simulator suite."
    }

    private func makePrimaryConcern(from attentionResults: [ValidationRunResult]) -> String {
        guard attentionResults.isEmpty == false else {
            return "No attention items. The current synthetic suite looks stable."
        }

        let grouped = Dictionary(grouping: attentionResults, by: \.scenario)
        guard let topIssue = grouped.max(by: { $0.value.count < $1.value.count }) else {
            return "Attention items exist, but no dominant scenario was detected."
        }

        return "\(topIssue.key.label) is the main weak point with \(topIssue.value.count) attention run(s)."
    }

    private func makeValidationReport(
        totalRuns: Int,
        passCount: Int,
        attentionResults: [ValidationRunResult],
        bestPresetName: String
    ) -> String {
        let attentionCount = attentionResults.count
        let presetLines = validationPresetSummaries.map { summary in
            "- \(summary.preset.label): \(summary.scoreSummary), avg pos \(summary.formattedAveragePositionDelta), avg max yaw \(summary.formattedAverageMaxYawDelta)"
        }
        let attentionLines = attentionResults.isEmpty
            ? ["- None"]
            : attentionResults.map { result in
                "- \(result.scenario.label) / \(result.preset.label): \(result.summary)"
            }
        let detailLines = validationResults.map { result in
            "- \(result.scenario.label) / \(result.preset.label) / \(result.verdict.label): avg pos \(result.formattedAveragePositionDelta), max pos \(result.formattedMaxPositionDelta), max yaw \(result.formattedMaxYawDelta)"
        }

        return [
            "# BoxFieldLab Validation Report",
            "",
            "Overall assessment: \(validationOverview.overallAssessment)",
            "Best overall preset: \(bestPresetName)",
            "Totals: \(passCount) pass, \(attentionCount) attention, \(totalRuns) run(s)",
            "Primary concern: \(validationOverview.primaryConcern)",
            "",
            "## Preset Comparison",
            presetLines.joined(separator: "\n"),
            "",
            "## Attention Items",
            attentionLines.joined(separator: "\n"),
            "",
            "## Detailed Runs",
            detailLines.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private static func makeValidationDefinitions() -> [ValidationRunDefinition] {
        let scenarios: [(TrackingScenario, TimeInterval)] = [
            (.steadyOrbit, 4.5),
            (.microJitter, 4.5),
            (.yawFlipStress, 5.5),
            (.temporaryLoss, 6.0),
            (.hardLoss, 6.5),
            (.reacquireOffset, 6.5),
        ]

        return StabilizerPreset.allCases.flatMap { preset in
            scenarios.map { scenario, duration in
                ValidationRunDefinition(
                    scenario: scenario,
                    preset: preset,
                    durationSeconds: duration
                )
            }
        }
    }
}
