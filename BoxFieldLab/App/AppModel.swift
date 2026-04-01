import QuartzCore
import RealityKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let immersiveSpaceID = "TrackingImmersiveSpace"
    static let maxTimelineEvents = 12

    @Published var inputMode: TrackingInputMode = .manualScripted
    @Published var selectedScenario: TrackingScenario = .steadyOrbit
    @Published var debugOptions = DebugOptions()
    @Published var manualObjectVisible = true
    @Published var stabilizerParameters = StabilizerParameters.defaults
    @Published private(set) var debugSnapshot = TrackingDebugSnapshot.empty(
        mode: .manualScripted,
        scenarioName: TrackingScenario.steadyOrbit.label
    )
    @Published private(set) var runtimeSummary = TrackingRuntimeSummary.initial(mode: .manualScripted)
    @Published private(set) var stabilizedState = StabilizedTrackedState.notSeen(kind: .box)
    @Published private(set) var trackingTimeline: [TrackingEvent] = []

    let sceneRootEntity = Entity()

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
        trackingTimeline.removeAll()
        trackingStabilizer.reset(for: .box)
        inputClockOrigin = CACurrentMediaTime()

        Task { [weak self] in
            guard let self else {
                return
            }
            await self.tick(now: CACurrentMediaTime())
        }
    }

    func updateStabilizerParameters(_ update: (inout StabilizerParameters) -> Void) {
        var nextParameters = stabilizerParameters
        update(&nextParameters)
        stabilizerParameters = nextParameters
        trackingStabilizer.parameters = nextParameters
    }

    private func tick(now: TimeInterval) async {
        manualInputSource.isEnabled = manualObjectVisible
        replayInputSource.scenario = selectedScenario
        trackingStabilizer.parameters = stabilizerParameters

        let rawObservation = await currentRawObservation(at: now)
        let stepResult = trackingStabilizer.advance(rawObservation: rawObservation, now: now)
        stabilizedState = stepResult.state

        fieldRenderer.update(
            state: stabilizedState,
            debugOptions: debugOptions,
            runtimeSummary: runtimeSummary,
            now: now
        )

        appendTimelineEvents(stepResult.events)
        refreshRuntimeSummary()
        debugSnapshot = enrich(
            snapshot: stepResult.debugSnapshot,
            fieldOpacity: fieldRenderer.currentOpacity
        )
    }

    private func currentRawObservation(at now: TimeInterval) async -> RawTrackedObservation? {
        let clockOrigin = inputClockOrigin ?? now
        let elapsedTime = now - clockOrigin
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
        }
        if resetClock {
            inputClockOrigin = CACurrentMediaTime()
        }

        trackingStabilizer.reset(for: .box)
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
            referenceAssetName: referenceCatalog.descriptor(for: .box).displayName,
            providerState: trackingCoordinator.status.providerState,
            authorizationState: trackingCoordinator.status.authorizationState,
            latestError: trackingCoordinator.status.latestError,
            objectTrackingSupported: trackingCoordinator.status.objectTrackingSupported,
            activeScenarioName: inputMode == .replayScenario ? selectedScenario.label : "n/a",
            isSyntheticInput: inputMode.isSynthetic
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
            fieldOpacity: fieldOpacity
        )
    }
}
