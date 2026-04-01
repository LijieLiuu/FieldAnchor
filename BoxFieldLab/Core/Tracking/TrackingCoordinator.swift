import ARKit
import Foundation

struct TrackingCoordinatorStatus {
    var providerState = "idle"
    var authorizationState = "not requested"
    var latestError: String?
    var objectTrackingSupported = ObjectTrackingProvider.isSupported
}

@MainActor
final class TrackingCoordinator {
    private let referenceCatalog: ReferenceObjectCatalog
    private let session = ARKitSession()

    private var objectTrackingProvider: ObjectTrackingProvider?
    private var anchorUpdatesTask: Task<Void, Never>?
    private var sessionEventsTask: Task<Void, Never>?
    private var referenceKindByID: [ReferenceObject.ID: TrackedObjectKind] = [:]

    private(set) var latestObservation: RawTrackedObservation?
    private(set) var status = TrackingCoordinatorStatus()

    init(referenceCatalog: ReferenceObjectCatalog) {
        self.referenceCatalog = referenceCatalog
    }

    func startTracking() async {
        await stop()

        guard ObjectTrackingProvider.isSupported else {
            status.objectTrackingSupported = false
            status.providerState = "unsupported"
            status.latestError = "Object tracking is not supported on the current runtime. Use Replay Scenario in the simulator."
            return
        }

        status = TrackingCoordinatorStatus()
        status.providerState = "loading reference object"

        do {
            let referenceObjects = try await referenceCatalog.loadReferenceObjects(for: [.box])
            referenceKindByID = Dictionary(uniqueKeysWithValues: referenceObjects.map { ($0.value.id, $0.key) })

            let provider = ObjectTrackingProvider(referenceObjects: Array(referenceObjects.values))
            objectTrackingProvider = provider

            let authorizationMap = await session.requestAuthorization(for: ObjectTrackingProvider.requiredAuthorizations)
            status.authorizationState = authorizationSummary(from: authorizationMap)

            let deniedTypes = authorizationMap.filter { $0.value != .allowed }
            guard deniedTypes.isEmpty else {
                status.providerState = "authorization denied"
                status.latestError = "Object tracking requires ARKit authorizations: \(authorizationSummary(from: authorizationMap))"
                return
            }

            beginListening(provider: provider)

            try await session.run([provider])
            status.providerState = provider.state.description
        } catch {
            status.providerState = "failed"
            status.latestError = error.localizedDescription
        }
    }

    func stop() async {
        anchorUpdatesTask?.cancel()
        anchorUpdatesTask = nil

        sessionEventsTask?.cancel()
        sessionEventsTask = nil

        objectTrackingProvider = nil
        latestObservation = nil
        referenceKindByID.removeAll()
        session.stop()
    }

    private func beginListening(provider: ObjectTrackingProvider) {
        anchorUpdatesTask = Task { [weak self] in
            guard let self else {
                return
            }

            for await update in provider.anchorUpdates {
                self.consume(anchorUpdate: update)
            }
        }

        sessionEventsTask = Task { [weak self] in
            guard let self else {
                return
            }

            for await event in session.events {
                self.consume(sessionEvent: event)
            }
        }
    }

    private func consume(anchorUpdate: AnchorUpdate<ObjectAnchor>) {
        let anchor = anchorUpdate.anchor
        let kind = referenceKindByID[anchor.referenceObject.id] ?? .box
        let boundingBox = anchor.boundingBox

        latestObservation = RawTrackedObservation(
            kind: kind,
            observationID: anchor.id,
            timestamp: anchorUpdate.timestamp,
            rawWorldTransform: anchor.originFromAnchorTransform,
            rawBoundingBoxCenter: boundingBox.center,
            rawBoundingBoxExtent: boundingBox.extent,
            isCurrentlyDetected: anchorUpdate.event != .removed && anchor.isTracked
        )

        status.providerState = objectTrackingProvider?.state.description ?? "running"
    }

    private func consume(sessionEvent: ARKitSession.Event) {
        switch sessionEvent {
        case let .authorizationChanged(type, statusValue):
            status.authorizationState = "\(type.description): \(statusValue.description)"
        case let .dataProviderStateChanged(_, newState, error):
            status.providerState = newState.description
            status.latestError = error?.localizedDescription
        @unknown default:
            break
        }
    }

    private func authorizationSummary(
        from authorizationMap: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus]
    ) -> String {
        if authorizationMap.isEmpty {
            return "not requested"
        }

        return authorizationMap
            .map { "\($0.key.description): \($0.value.description)" }
            .sorted()
            .joined(separator: ", ")
    }
}
