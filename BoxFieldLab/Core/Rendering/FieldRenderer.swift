import RealityKit
import SwiftUI

@MainActor
final class FieldRenderer {
    let rootEntity = Entity()
    private(set) var fieldVisualSourceName = "Procedural Magnetic Field (Fallback)"

    private let rawAnchorEntity = Entity()
    private let rawGizmoEntity = Entity()
    private let boundingBoxEntity: ModelEntity

    private let displayAnchorEntity = Entity()
    private let fieldMountEntity = Entity()
    private let displayGizmoEntity = Entity()
    private let fieldVisualEntity = Entity()

    private let rawGhostAnchorEntity = Entity()
    private let rawGhostBoxEntity: ModelEntity
    private let displayGhostAnchorEntity = Entity()
    private let displayGhostBoxEntity: ModelEntity

    private let attachmentOffsetEntity: ModelEntity
    private let fieldMountMarkerEntity: ModelEntity

    private let rawTrailParent = Entity()
    private let displayTrailParent = Entity()
    private let rawTrailEntities: [ModelEntity]
    private let displayTrailEntities: [ModelEntity]

    private let attachmentSpec = FieldAttachmentSpec.phaseOneBox
    private var lastUpdateTime: TimeInterval?
    private(set) var currentOpacity: Float = 0
    private var rawTrailHistory: [SIMD3<Float>] = []
    private var displayTrailHistory: [SIMD3<Float>] = []
    private var hasAttemptedExternalLoad = false

    init() {
        let boxMaterial = SimpleMaterial(color: .cyan.withAlphaComponent(0.15), isMetallic: false)
        boundingBoxEntity = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)), materials: [boxMaterial])

        rawGhostBoxEntity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)),
            materials: [SimpleMaterial(color: .red.withAlphaComponent(0.18), isMetallic: false)]
        )
        displayGhostBoxEntity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)),
            materials: [SimpleMaterial(color: .green.withAlphaComponent(0.18), isMetallic: false)]
        )

        attachmentOffsetEntity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.006, 1.0, 0.006)),
            materials: [SimpleMaterial(color: .yellow.withAlphaComponent(0.7), isMetallic: false)]
        )
        fieldMountMarkerEntity = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [SimpleMaterial(color: .yellow, isMetallic: false)]
        )

        rawTrailEntities = (0..<18).map { index in
            let alpha = max(0.15, 0.8 - Float(index) * 0.035)
            return ModelEntity(
                mesh: .generateSphere(radius: 0.008),
                materials: [SimpleMaterial(color: .red.withAlphaComponent(CGFloat(alpha)), isMetallic: false)]
            )
        }
        displayTrailEntities = (0..<18).map { index in
            let alpha = max(0.15, 0.8 - Float(index) * 0.035)
            return ModelEntity(
                mesh: .generateSphere(radius: 0.008),
                materials: [SimpleMaterial(color: .green.withAlphaComponent(CGFloat(alpha)), isMetallic: false)]
            )
        }

        rootEntity.name = "FieldRendererRoot"
        rawAnchorEntity.name = "RawAnchorEntity"
        displayAnchorEntity.name = "DisplayAnchorEntity"
        fieldMountEntity.name = "FieldMountEntity"

        configureHierarchy()
    }

    func loadPreferredFieldVisualIfNeeded() async {
        guard hasAttemptedExternalLoad == false else {
            return
        }

        hasAttemptedExternalLoad = true

        guard let url = Bundle.main.url(
            forResource: "ParticleField",
            withExtension: "usda",
            subdirectory: "EffectAssets/demo_static_trim"
        ) else {
            fieldVisualSourceName = "Procedural Magnetic Field (Fallback)"
            return
        }

        do {
            let loadedEntity = try await Entity(contentsOf: url)
            let normalizedEntity = Entity()
            normalizedEntity.name = "ExternalFieldAsset"
            normalizedEntity.addChild(loadedEntity)
            normalizedEntity.position = SIMD3<Float>(0, 0.055, 0)
            normalizedEntity.scale = SIMD3<Float>(repeating: 0.18)

            replaceFieldVisualContent(with: normalizedEntity)
            fieldVisualSourceName = "demo_static_trim Particle Trace"
        } catch {
            fieldVisualSourceName = "Procedural Magnetic Field (Fallback)"
        }
    }

    func update(
        state: StabilizedTrackedState,
        debugOptions: DebugOptions,
        runtimeSummary: TrackingRuntimeSummary,
        validationMode: ValidationMode,
        now: TimeInterval
    ) {
        let deltaTime = max(Float(now - (lastUpdateTime ?? now)), 0.016)
        lastUpdateTime = now

        rawAnchorEntity.setTransformMatrix(state.rawWorldTransform, relativeTo: nil)
        displayAnchorEntity.setTransformMatrix(state.displayWorldTransform, relativeTo: nil)
        rawGhostAnchorEntity.setTransformMatrix(state.rawWorldTransform, relativeTo: nil)
        displayGhostAnchorEntity.setTransformMatrix(state.displayWorldTransform, relativeTo: nil)

        let topOffset = max(state.rawBoundingBoxExtent.y * 0.5 + attachmentSpec.localOffset.y, 0.03)
        fieldMountEntity.position = SIMD3<Float>(attachmentSpec.localOffset.x, topOffset, attachmentSpec.localOffset.z)
        fieldMountMarkerEntity.position = .zero

        attachmentOffsetEntity.position = SIMD3<Float>(0, topOffset * 0.5, 0)
        attachmentOffsetEntity.scale = SIMD3<Float>(1, max(topOffset, 0.001), 1)

        let fieldScale = runtimeSummary.isSyntheticInput ? attachmentSpec.scale * 2.8 : attachmentSpec.scale
        fieldVisualEntity.scale = SIMD3<Float>(repeating: fieldScale)

        boundingBoxEntity.position = state.rawBoundingBoxCenter
        boundingBoxEntity.scale = max(state.rawBoundingBoxExtent, SIMD3<Float>(repeating: 0.001))
        rawGhostBoxEntity.position = state.rawBoundingBoxCenter
        rawGhostBoxEntity.scale = boundingBoxEntity.scale
        displayGhostBoxEntity.position = state.rawBoundingBoxCenter
        displayGhostBoxEntity.scale = boundingBoxEntity.scale

        rawGizmoEntity.isEnabled = debugOptions.showRawAnchorGizmo && state.trackingState == .tracked
        displayGizmoEntity.isEnabled = debugOptions.showDisplayAnchorGizmo
            && state.trackingState != .notSeen
            && state.trackingState != .lost
        boundingBoxEntity.isEnabled = debugOptions.showBoundingBox && state.trackingState == .tracked
        rawGhostAnchorEntity.isEnabled = debugOptions.showRawPoseGhost && state.trackingState != .notSeen
        displayGhostAnchorEntity.isEnabled = debugOptions.showDisplayPoseGhost && state.trackingState != .notSeen
        attachmentOffsetEntity.isEnabled = debugOptions.showAttachmentOffsetMarker && state.trackingState != .notSeen
        fieldMountMarkerEntity.isEnabled = debugOptions.showFieldMountMarker && state.trackingState != .notSeen

        let targetOpacity: Float
        if validationMode == .diagnosticsOnly {
            targetOpacity = 0.0
        } else {
            switch state.trackingState {
            case .tracked, .temporarilyLost:
                targetOpacity = 1.0
            case .notSeen, .lost:
                targetOpacity = 0.0
            }
        }

        currentOpacity += (targetOpacity - currentOpacity) * min(deltaTime * 8.0, 1.0)
        fieldVisualEntity.components.set(OpacityComponent(opacity: currentOpacity))
        fieldVisualEntity.isEnabled = currentOpacity > 0.01
        fieldVisualEntity.orientation *= simd_quatf(angle: deltaTime * 0.35, axis: SIMD3<Float>(0, 1, 0))

        updateTrails(state: state, debugOptions: debugOptions)

        if state.trackingState == .notSeen && runtimeSummary.inputMode == .objectTracking {
            rawGizmoEntity.isEnabled = false
            boundingBoxEntity.isEnabled = false
            rawGhostAnchorEntity.isEnabled = false
            displayGhostAnchorEntity.isEnabled = false
        }
    }

    private func configureHierarchy() {
        rawGizmoEntity.addChild(makeAxisGizmo(scale: 0.12))
        displayGizmoEntity.addChild(makeAxisGizmo(scale: 0.09, thickness: 0.003))
        boundingBoxEntity.components.set(OpacityComponent(opacity: 0.2))
        rawGhostBoxEntity.components.set(OpacityComponent(opacity: 0.28))
        displayGhostBoxEntity.components.set(OpacityComponent(opacity: 0.28))

        rawAnchorEntity.addChild(rawGizmoEntity)
        rawAnchorEntity.addChild(boundingBoxEntity)
        rawGhostAnchorEntity.addChild(rawGhostBoxEntity)
        displayGhostAnchorEntity.addChild(displayGhostBoxEntity)

        fieldVisualEntity.addChild(makeMagneticFieldModel())
        fieldVisualEntity.components.set(OpacityComponent(opacity: 0))
        fieldVisualEntity.isEnabled = false

        displayAnchorEntity.addChild(attachmentOffsetEntity)
        fieldMountEntity.addChild(fieldVisualEntity)
        fieldMountEntity.addChild(displayGizmoEntity)
        fieldMountEntity.addChild(fieldMountMarkerEntity)
        displayAnchorEntity.addChild(fieldMountEntity)

        for entity in rawTrailEntities {
            rawTrailParent.addChild(entity)
        }
        for entity in displayTrailEntities {
            displayTrailParent.addChild(entity)
        }

        rootEntity.addChild(rawAnchorEntity)
        rootEntity.addChild(displayAnchorEntity)
        rootEntity.addChild(rawGhostAnchorEntity)
        rootEntity.addChild(displayGhostAnchorEntity)
        rootEntity.addChild(rawTrailParent)
        rootEntity.addChild(displayTrailParent)
    }

    private func replaceFieldVisualContent(with entity: Entity) {
        for child in fieldVisualEntity.children {
            child.removeFromParent()
        }

        fieldVisualEntity.addChild(entity)
    }

    private func updateTrails(state: StabilizedTrackedState, debugOptions: DebugOptions) {
        let rawCenter = state.rawWorldTransform.transformPoint(state.rawBoundingBoxCenter)
        let displayCenter = state.displayWorldTransform.transformPoint(state.rawBoundingBoxCenter)

        if state.trackingState != .notSeen {
            rawTrailHistory.insert(rawCenter, at: 0)
            displayTrailHistory.insert(displayCenter, at: 0)
            rawTrailHistory = Array(rawTrailHistory.prefix(rawTrailEntities.count))
            displayTrailHistory = Array(displayTrailHistory.prefix(displayTrailEntities.count))
        }

        for (index, entity) in rawTrailEntities.enumerated() {
            if debugOptions.showRawTrail, index < rawTrailHistory.count {
                entity.isEnabled = true
                entity.position = rawTrailHistory[index]
            } else {
                entity.isEnabled = false
            }
        }

        for (index, entity) in displayTrailEntities.enumerated() {
            if debugOptions.showDisplayTrail, index < displayTrailHistory.count {
                entity.isEnabled = true
                entity.position = displayTrailHistory[index]
            } else {
                entity.isEnabled = false
            }
        }
    }

    private func makeAxisGizmo(scale: Float, thickness: Float = 0.005) -> Entity {
        let gizmo = Entity()

        let xAxis = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(scale, thickness, thickness)),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.position = SIMD3<Float>(scale * 0.5, 0, 0)

        let yAxis = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(thickness, scale, thickness)),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.position = SIMD3<Float>(0, scale * 0.5, 0)

        let zAxis = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(thickness, thickness, scale)),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.position = SIMD3<Float>(0, 0, scale * 0.5)

        gizmo.addChild(xAxis)
        gizmo.addChild(yAxis)
        gizmo.addChild(zAxis)
        return gizmo
    }

    private func makeMagneticFieldModel() -> Entity {
        let root = Entity()

        let core = ModelEntity(
            mesh: .generateCylinder(height: 0.12, radius: 0.012),
            materials: [SimpleMaterial(color: .orange, roughness: 0.2, isMetallic: true)]
        )
        core.position = SIMD3<Float>(0, 0.06, 0)
        root.addChild(core)

        let ringHeights: [Float] = [0.02, 0.06, 0.10]
        for (index, height) in ringHeights.enumerated() {
            let radiusX: Float = 0.09 + Float(index) * 0.04
            let radiusZ: Float = 0.05 + Float(index) * 0.025
            let orbit = Entity()
            orbit.position = SIMD3<Float>(0, height, 0)

            for step in 0..<18 {
                let angle = (Float(step) / 18.0) * (.pi * 2)
                let point = ModelEntity(
                    mesh: .generateSphere(radius: 0.006),
                    materials: [SimpleMaterial(color: .cyan, roughness: 0.35, isMetallic: false)]
                )
                point.position = SIMD3<Float>(cos(angle) * radiusX, 0, sin(angle) * radiusZ)
                orbit.addChild(point)
            }

            root.addChild(orbit)
        }

        return root
    }
}
