import QuartzCore
import RealityKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let immersiveSpaceID = "TrackingImmersiveSpace"

    @Published var inputMode: TrackingInputMode = .manualDemo
    @Published var debugOptions = DebugOptions()
    @Published var manualObjectVisible = true
    @Published private(set) var diagnostics = TrackingDiagnostics.zero
    @Published private(set) var runtimeSummary = TrackingRuntimeSummary.initial(mode: .manualDemo)
    @Published private(set) var stabilizedState = StabilizedTrackedState.notSeen(kind: .box)

    let sceneRootEntity = Entity()

    private let referenceCatalog = ReferenceObjectCatalog()
    private lazy var trackingCoordinator = TrackingCoordinator(referenceCatalog: referenceCatalog)
    private let manualTrackingDriver = ManualTrackingDriver()
    private let trackingStabilizer = TrackingStabilizer()
    private let fieldRenderer = FieldRenderer()

    private var immersiveSpaceOpened = false
    private var runtimeLoopTask: Task<Void, Never>?

    init() {
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
            diagnostics: diagnostics,
            runtimeSummary: runtimeSummary,
            now: CACurrentMediaTime()
        )
    }

    func startRuntimeLoopIfNeeded() async {
        guard runtimeLoopTask == nil else {
            return
        }

        await trackingCoordinator.stop()
        if inputMode == .objectTracking {
            await trackingCoordinator.startTracking()
        }

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
        trackingStabilizer.reset(for: .box)

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.trackingCoordinator.stop()
            if mode == .objectTracking {
                await self.trackingCoordinator.startTracking()
            }
            await self.tick(now: CACurrentMediaTime())
        }
    }

    private func tick(now: TimeInterval) async {
        let rawObservation = await currentRawObservation(at: now)
        stabilizedState = trackingStabilizer.advance(rawObservation: rawObservation, now: now)
        diagnostics = TrackingDiagnostics(state: stabilizedState, fieldOpacity: fieldRenderer.currentOpacity)
        refreshRuntimeSummary()

        fieldRenderer.update(
            state: stabilizedState,
            debugOptions: debugOptions,
            diagnostics: diagnostics,
            runtimeSummary: runtimeSummary,
            now: now
        )
    }

    private func currentRawObservation(at now: TimeInterval) async -> RawTrackedObservation? {
        switch inputMode {
        case .manualDemo:
            guard manualObjectVisible else {
                return nil
            }
            return manualTrackingDriver.observation(at: now)
        case .objectTracking:
            return trackingCoordinator.latestObservation
        }
    }

    private func refreshRuntimeSummary() {
        runtimeSummary = TrackingRuntimeSummary(
            inputMode: inputMode,
            referenceAssetName: referenceCatalog.descriptor(for: .box).displayName,
            providerState: trackingCoordinator.status.providerState,
            authorizationState: trackingCoordinator.status.authorizationState,
            latestError: trackingCoordinator.status.latestError,
            objectTrackingSupported: trackingCoordinator.status.objectTrackingSupported
        )
    }
}
