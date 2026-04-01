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
    case missingResource(ReferenceObjectAssetDescriptor)
    case loadFailed(ReferenceObjectAssetDescriptor, Error)

    var errorDescription: String? {
        switch self {
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
            )
        ]
    ) {
        self.descriptors = descriptors
    }

    func descriptor(for kind: TrackedObjectKind) -> ReferenceObjectAssetDescriptor {
        descriptors[kind]!
    }

    func loadReferenceObjects(for kinds: [TrackedObjectKind]) async throws -> [TrackedObjectKind: ReferenceObject] {
        var loadedObjects: [TrackedObjectKind: ReferenceObject] = [:]

        for kind in kinds {
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
