# BoxFieldLab Object Tracking

This repo contains a visionOS prototype for attaching a magnetic-field visual to a real tracked object with ARKit object tracking.

## Requirements

- Apple Vision Pro hardware
- Xcode with visionOS support
- A physical object that matches one of the bundled reference objects

Object tracking must run on device. The visionOS simulator can build the app, but it cannot reproduce ARKit `ObjectTrackingProvider` tracking.

## Reference Objects

Bundled reference objects live in:

```text
BoxFieldLab/Resources/ReferenceObjects
```

The app currently looks for these files:

- `Box.referenceObject`
- `Phone.referenceObject`
- `Keyboard.referenceObject`

To reproduce with your own object, add a trained `.referenceObject` file to that folder and update `ReferenceObjectCatalog.swift` if the file name or object kind is different.

## Run On Vision Pro

1. Open `BoxFieldLab.xcodeproj` in Xcode.
2. Select the `BoxFieldLab` visionOS app scheme.
3. Connect or pair Apple Vision Pro as the run destination.
4. Build and run the app on the device.
5. In the app controls, choose `Object Tracking (Hardware)`.
6. Keep the matching physical object visible in mixed immersive mode.
7. Confirm the runtime panel shows loaded reference assets and a running object-tracking provider.

When tracking succeeds, the app uses the raw ARKit object pose, stabilizes the display pose, and attaches the magnetic-field visual to the tracked object.
