import ARKit
import Foundation

struct ReferenceObjectAssetDescriptor: Sendable {
    let resourceName: String
    let fileExtension: String
    let subdirectory: String?
    let bundle: Bundle

    var displayName: String {
        "\(resourceName).\(fileExtension)"
    }
}

enum ReferenceObjectCatalogError: LocalizedError {
    case noAvailableReferenceObjects([TrackedObjectKind])
    case missingResource(ReferenceObjectAssetDescriptor)
    case loadFailed(ReferenceObjectAssetDescriptor, Error)

    var errorDescription: String? {
        switch self {
        case let .noAvailableReferenceObjects(kinds):
            return "No reference objects found for: \(kinds.map(\.label).joined(separator: ", "))."
        case let .missingResource(descriptor):
            if let subdirectory = descriptor.subdirectory {
                return "Missing reference object: \(subdirectory)/\(descriptor.displayName)"
            }
            return "Missing reference object: \(descriptor.displayName)"
        case let .loadFailed(descriptor, error):
            return "Failed to load \(descriptor.displayName): \(error.localizedDescription)"
        }
    }
}

struct ReferenceObjectCatalog {
    private let descriptors: [TrackedObjectKind: ReferenceObjectAssetDescriptor]

    init(
        descriptors: [TrackedObjectKind: ReferenceObjectAssetDescriptor] = [
            .box: ReferenceObjectAssetDescriptor(
                resourceName: "Box",
                fileExtension: "referenceObject",
                subdirectory: "ReferenceObjects",
                bundle: .main
            ),
            .phone: ReferenceObjectAssetDescriptor(
                resourceName: "Phone",
                fileExtension: "referenceObject",
                subdirectory: "ReferenceObjects",
                bundle: .main
            ),
            .keyboard: ReferenceObjectAssetDescriptor(
                resourceName: "Keyboard",
                fileExtension: "referenceObject",
                subdirectory: "ReferenceObjects",
                bundle: .main
            )
        ]
    ) {
        self.descriptors = descriptors
    }

    func descriptor(for kind: TrackedObjectKind) -> ReferenceObjectAssetDescriptor {
        descriptors[kind]!
    }

    func availableKinds(for kinds: [TrackedObjectKind] = TrackedObjectKind.allCases) -> [TrackedObjectKind] {
        kinds.filter { kind in
            let descriptor = descriptor(for: kind)
            return descriptor.bundle.url(
                forResource: descriptor.resourceName,
                withExtension: descriptor.fileExtension,
                subdirectory: descriptor.subdirectory
            ) != nil
        }
    }

    func availableDescriptorDisplayNames(for kinds: [TrackedObjectKind] = TrackedObjectKind.allCases) -> [String] {
        availableKinds(for: kinds).map { descriptor(for: $0).displayName }
    }

    func descriptorAvailabilitySummary(for kinds: [TrackedObjectKind] = TrackedObjectKind.allCases) -> String {
        kinds.map { kind in
            let descriptor = descriptor(for: kind)
            let isAvailable = availableKinds(for: [kind]).isEmpty == false
            return "\(descriptor.displayName) \(isAvailable ? "(loaded)" : "(missing)")"
        }
        .joined(separator: ", ")
    }

    func loadReferenceObjects(for kinds: [TrackedObjectKind]) async throws -> [TrackedObjectKind: ReferenceObject] {
        var loadedObjects: [TrackedObjectKind: ReferenceObject] = [:]

        let availableKinds = availableKinds(for: kinds)
        guard availableKinds.isEmpty == false else {
            throw ReferenceObjectCatalogError.noAvailableReferenceObjects(kinds)
        }

        for kind in availableKinds {
            let descriptor = descriptor(for: kind)

            guard
                let url = descriptor.bundle.url(
                    forResource: descriptor.resourceName,
                    withExtension: descriptor.fileExtension,
                    subdirectory: descriptor.subdirectory
                )
            else {
                throw ReferenceObjectCatalogError.missingResource(descriptor)
            }

            do {
                loadedObjects[kind] = try await ReferenceObject(from: url)
            } catch {
                throw ReferenceObjectCatalogError.loadFailed(descriptor, error)
            }
        }

        return loadedObjects
    }
}
