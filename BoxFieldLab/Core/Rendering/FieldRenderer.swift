import RealityKit
import SwiftUI

@MainActor
final class FieldRenderer {
    let rootEntity = Entity()

    private let rawAnchorEntity = Entity()
    private let rawGizmoEntity = Entity()
    private let boundingBoxEntity: ModelEntity

    private let displayAnchorEntity = Entity()
    private let fieldMountEntity = Entity()
    private let displayGizmoEntity = Entity()
    private let fieldVisualEntity = Entity()

    private let attachmentSpec = FieldAttachmentSpec.phaseOneBox
    private var lastUpdateTime: TimeInterval?
    private(set) var currentOpacity: Float = 0

    init() {
        let boxMaterial = SimpleMaterial(color: .cyan.withAlphaComponent(0.15), isMetallic: false)
        boundingBoxEntity = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)), materials: [boxMaterial])

        rootEntity.name = "FieldRendererRoot"
        rawAnchorEntity.name = "RawAnchorEntity"
        displayAnchorEntity.name = "DisplayAnchorEntity"
        fieldMountEntity.name = "FieldMountEntity"

        configureHierarchy()
    }

    func update(
        state: StabilizedTrackedState,
        debugOptions: DebugOptions,
        diagnostics: TrackingDiagnostics,
        runtimeSummary: TrackingRuntimeSummary,
        now: TimeInterval
    ) {
        let deltaTime = max(Float(now - (lastUpdateTime ?? now)), 0.016)
        lastUpdateTime = now

        rawAnchorEntity.setTransformMatrix(state.rawWorldTransform, relativeTo: nil)
        displayAnchorEntity.setTransformMatrix(state.displayWorldTransform, relativeTo: nil)

        let topOffset = max(state.rawBoundingBoxExtent.y * 0.5 + attachmentSpec.localOffset.y, 0.03)
        fieldMountEntity.position = SIMD3<Float>(attachmentSpec.localOffset.x, topOffset, attachmentSpec.localOffset.z)

        boundingBoxEntity.position = state.rawBoundingBoxCenter
        boundingBoxEntity.scale = max(state.rawBoundingBoxExtent, SIMD3<Float>(repeating: 0.001))

        rawGizmoEntity.isEnabled = debugOptions.showRawAnchorGizmo && state.trackingState == .tracked
        displayGizmoEntity.isEnabled = debugOptions.showDisplayAnchorGizmo
            && state.trackingState != .notSeen
            && state.trackingState != .lost
        boundingBoxEntity.isEnabled = debugOptions.showBoundingBox && state.trackingState == .tracked

        let targetOpacity: Float
        switch state.trackingState {
        case .tracked, .temporarilyLost:
            targetOpacity = 1.0
        case .notSeen, .lost:
            targetOpacity = 0.0
        }

        currentOpacity += (targetOpacity - currentOpacity) * min(deltaTime * 8.0, 1.0)
        fieldVisualEntity.components.set(OpacityComponent(opacity: currentOpacity))
        fieldVisualEntity.isEnabled = currentOpacity > 0.01

        // Keep the field visually alive without changing the attachment contract.
        fieldVisualEntity.orientation *= simd_quatf(angle: deltaTime * 0.35, axis: SIMD3<Float>(0, 1, 0))

        if state.trackingState == .notSeen && runtimeSummary.inputMode == .objectTracking {
            rawGizmoEntity.isEnabled = false
            boundingBoxEntity.isEnabled = false
        }

        _ = diagnostics
    }

    private func configureHierarchy() {
        rawGizmoEntity.addChild(makeAxisGizmo(scale: 0.12))
        displayGizmoEntity.addChild(makeAxisGizmo(scale: 0.09, thickness: 0.003))
        displayGizmoEntity.position = .zero
        boundingBoxEntity.components.set(OpacityComponent(opacity: 0.2))

        rawAnchorEntity.addChild(rawGizmoEntity)
        rawAnchorEntity.addChild(boundingBoxEntity)

        fieldVisualEntity.addChild(makeMagneticFieldModel())
        fieldVisualEntity.components.set(OpacityComponent(opacity: 0))
        fieldVisualEntity.isEnabled = false

        fieldMountEntity.addChild(fieldVisualEntity)
        fieldMountEntity.addChild(displayGizmoEntity)
        displayAnchorEntity.addChild(fieldMountEntity)

        rootEntity.addChild(rawAnchorEntity)
        rootEntity.addChild(displayAnchorEntity)
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
