# Hardware Validation Checklist

Use this checklist on the first `Apple Vision Pro` test day after simulator tuning is complete.

## Before switching off simulator
- Record which replay scenario and stabilizer preset gave the best stability.
- Note the approximate acceptable ranges for:
  - `Position Lerp`
  - `Position Deadband`
  - `Yaw Lerp`
  - `Yaw Flip Threshold`
  - `Loss Freeze`
- Capture at least one screenshot or short recording showing:
  - raw vs stabilized diagnostics
  - event timeline behavior
  - temporary-loss or yaw-flip stress behavior

## On the first APV run
- Confirm `Box.referenceObject` loads successfully.
- Confirm `Object Tracking` mode can be selected without app failure.
- Confirm the known box is detected at least once.
- Confirm the magnetic field appears at `center + top offset`.

## Tracking checks
- Stationary stability:
  - keep the box still for 10 seconds
  - look for shimmer, drift, or orientation noise
- Slow translation:
  - slide the box slowly on the table
  - look for lag vs overshoot
- Slow rotation:
  - rotate the box gradually
  - watch for yaw jumps or flip rejection artifacts
- Short occlusion:
  - partially block the box briefly
  - check `temporarilyLost` behavior
- Reacquisition:
  - remove and reintroduce the box
  - check whether the field resumes smoothly

## Record after device testing
- Which simulator preset matched device behavior most closely
- Whether the current reference object is good enough or needs replacement
- Whether instability comes mostly from:
  - raw detection quality
  - stabilizer parameters
  - attachment rendering
