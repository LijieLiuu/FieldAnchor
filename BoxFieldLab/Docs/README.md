# BoxFieldLab

`BoxFieldLab` is a phase-1 visionOS prototype for stable attachment of a simple magnetic-field model to one known tabletop box, with a simulator-first validation lab for no-hardware tuning.

## What is implemented
- `visionOS + SwiftUI + RealityKit` app shell with an immersive space
- `Replay Scenario` mode as the recommended simulator validation workflow
- `Manual Scripted` mode as a simple simulator smoke test
- `Object Tracking` mode wired to `ARKit ObjectTrackingProvider`
- replaceable reference-object catalog instead of a hard-coded USDZ pipeline
- separate `rawWorldTransform` and `displayWorldTransform`
- yaw-only stabilized display pose for symmetric boxes
- `notSeen / tracked / temporarilyLost / lost` lifecycle states
- magnetic-field placeholder model attached at `center + top offset`
- replay controls, stabilizer presets, rolling metrics, and event timeline
- debug toggles and raw/display delta readouts
- a bundled third-party `Box.referenceObject` so phase-1 tracking can run immediately on device

## Project structure
- `BoxFieldLab/App`
  SwiftUI app entry, control window, and immersive scene
- `BoxFieldLab/Core/Tracking`
  reference-object loading, object tracking, manual driver, and stabilizer
- `BoxFieldLab/Core/Rendering`
  RealityKit entities and magnetic-field rendering
- `BoxFieldLab/Resources/ReferenceObjects`
  place `Box.referenceObject` here for real object tracking

## How to run
1. Open [BoxFieldLab.xcodeproj](/Users/lijieliu/Desktop/vip_project/BoxFieldLab.xcodeproj) in Xcode.
2. Run `Replay Scenario` first to validate the immersive scene, stabilizer, and lifecycle behavior.
3. The repo already includes `Box.referenceObject` in [ReferenceObjects](/Users/lijieliu/Desktop/vip_project/BoxFieldLab/Resources/ReferenceObjects).
4. Switch the input source to `Object Tracking` on Vision Pro hardware.
5. If the bundled box does not match your physical box closely enough, replace it with your own trained reference object without changing code.
6. Use [docs/HARDWARE_VALIDATION_CHECKLIST.md](/Users/lijieliu/Desktop/vip_project/docs/HARDWARE_VALIDATION_CHECKLIST.md) before the first device day.


## Third-party asset
- [THIRD_PARTY_NOTICES.md](/Users/lijieliu/Desktop/vip_project/THIRD_PARTY_NOTICES.md)

## Device-day checklist
- [docs/HARDWARE_VALIDATION_CHECKLIST.md](/Users/lijieliu/Desktop/vip_project/docs/HARDWARE_VALIDATION_CHECKLIST.md)
