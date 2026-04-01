import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        NavigationStack {
            Form {
                Section("Runtime") {
                    Picker(
                        "Input Source",
                        selection: Binding(
                            get: { appModel.inputMode },
                            set: { appModel.setInputMode($0) }
                        )
                    ) {
                        ForEach(TrackingInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    if appModel.inputMode == .replayScenario {
                        Picker(
                            "Scenario",
                            selection: Binding(
                                get: { appModel.selectedScenario },
                                set: { appModel.setScenario($0) }
                            )
                        ) {
                            ForEach(TrackingScenario.allCases) { scenario in
                                Text(scenario.label).tag(scenario)
                            }
                        }

                        Text(appModel.selectedScenario.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if appModel.inputMode == .manualScripted {
                        Toggle(
                            "Show Manual Box",
                            isOn: Binding(
                                get: { appModel.manualObjectVisible },
                                set: { appModel.manualObjectVisible = $0 }
                            )
                        )
                    }

                    LabeledContent("Lifecycle", value: appModel.stabilizedState.trackingState.label)
                    LabeledContent("Synthetic Input", value: appModel.runtimeSummary.isSyntheticInput ? "Yes" : "No")
                    LabeledContent("Active Scenario", value: appModel.runtimeSummary.activeScenarioName)
                    LabeledContent("Reference Asset", value: appModel.runtimeSummary.referenceAssetName)
                    LabeledContent("Provider State", value: appModel.runtimeSummary.providerState)
                    LabeledContent("Authorization", value: appModel.runtimeSummary.authorizationState)

                    if let latestError = appModel.runtimeSummary.latestError, latestError.isEmpty == false {
                        Text(latestError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Stabilizer Parameters") {
                    parameterRow(
                        title: "Position Lerp",
                        value: positionLerpBinding,
                        formattedValue: String(format: "%.3f", appModel.stabilizerParameters.positionLerpFactor),
                        range: 0.05...0.6,
                        step: 0.01
                    )

                    parameterRow(
                        title: "Position Deadband",
                        value: positionDeadbandBinding,
                        formattedValue: String(format: "%.4f", appModel.stabilizerParameters.positionDeadbandMeters),
                        range: 0.0...0.02,
                        step: 0.0005
                    )

                    parameterRow(
                        title: "Yaw Lerp",
                        value: yawLerpBinding,
                        formattedValue: String(format: "%.3f", appModel.stabilizerParameters.yawLerpFactor),
                        range: 0.05...0.5,
                        step: 0.01
                    )

                    parameterRow(
                        title: "Yaw Flip Threshold",
                        value: yawFlipThresholdBinding,
                        formattedValue: String(format: "%.1f°", radiansToDegrees(appModel.stabilizerParameters.yawFlipThresholdRadians)),
                        range: 15...180,
                        step: 1
                    )

                    parameterRow(
                        title: "Loss Freeze",
                        value: temporaryLossBinding,
                        formattedValue: String(format: "%.2fs", appModel.stabilizerParameters.temporaryLossDuration),
                        range: 0.1...2.0,
                        step: 0.05
                    )
                }

                Section("Debug Toggles") {
                    Toggle(
                        "Show Raw Anchor Gizmo",
                        isOn: Binding(
                            get: { appModel.debugOptions.showRawAnchorGizmo },
                            set: { appModel.debugOptions.showRawAnchorGizmo = $0 }
                        )
                    )
                    Toggle(
                        "Show Stabilized Gizmo",
                        isOn: Binding(
                            get: { appModel.debugOptions.showDisplayAnchorGizmo },
                            set: { appModel.debugOptions.showDisplayAnchorGizmo = $0 }
                        )
                    )
                    Toggle(
                        "Show Bounding Box",
                        isOn: Binding(
                            get: { appModel.debugOptions.showBoundingBox },
                            set: { appModel.debugOptions.showBoundingBox = $0 }
                        )
                    )
                    Toggle(
                        "Show Raw Pose Ghost",
                        isOn: Binding(
                            get: { appModel.debugOptions.showRawPoseGhost },
                            set: { appModel.debugOptions.showRawPoseGhost = $0 }
                        )
                    )
                    Toggle(
                        "Show Stabilized Pose Ghost",
                        isOn: Binding(
                            get: { appModel.debugOptions.showDisplayPoseGhost },
                            set: { appModel.debugOptions.showDisplayPoseGhost = $0 }
                        )
                    )
                    Toggle(
                        "Show Attachment Offset Marker",
                        isOn: Binding(
                            get: { appModel.debugOptions.showAttachmentOffsetMarker },
                            set: { appModel.debugOptions.showAttachmentOffsetMarker = $0 }
                        )
                    )
                    Toggle(
                        "Show Field Mount Marker",
                        isOn: Binding(
                            get: { appModel.debugOptions.showFieldMountMarker },
                            set: { appModel.debugOptions.showFieldMountMarker = $0 }
                        )
                    )
                    Toggle(
                        "Show Raw Trail",
                        isOn: Binding(
                            get: { appModel.debugOptions.showRawTrail },
                            set: { appModel.debugOptions.showRawTrail = $0 }
                        )
                    )
                    Toggle(
                        "Show Display Trail",
                        isOn: Binding(
                            get: { appModel.debugOptions.showDisplayTrail },
                            set: { appModel.debugOptions.showDisplayTrail = $0 }
                        )
                    )
                }

                Section("Debug Snapshot") {
                    LabeledContent("Raw Position", value: appModel.debugSnapshot.formattedRawPosition)
                    LabeledContent("Display Position", value: appModel.debugSnapshot.formattedDisplayPosition)
                    LabeledContent("Raw Yaw", value: appModel.debugSnapshot.formattedRawYaw)
                    LabeledContent("Display Yaw", value: appModel.debugSnapshot.formattedDisplayYaw)
                    LabeledContent("Position Delta", value: appModel.debugSnapshot.formattedPositionDelta)
                    LabeledContent("Yaw Delta", value: appModel.debugSnapshot.formattedYawDelta)
                    LabeledContent("Last Seen Age", value: appModel.debugSnapshot.formattedLastSeenAge)
                    LabeledContent("Field Opacity", value: appModel.debugSnapshot.formattedFieldOpacity)
                }

                Section("Event Timeline") {
                    if appModel.trackingTimeline.isEmpty {
                        Text("No events yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.trackingTimeline) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(event.formattedTimestamp)  \(event.detail)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Notes") {
                    Text("Use Manual Scripted or Replay Scenario in the simulator. Replay Scenario is the preferred no-hardware validation path for the stabilizer and lifecycle logic.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Box Field Lab")
        }
        .task {
            await appModel.activate(openImmersiveSpace: openImmersiveSpace)
        }
    }

    private func parameterRow(
        title: String,
        value: Binding<Double>,
        formattedValue: String,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
        }
    }

    private var positionLerpBinding: Binding<Double> {
        Binding(
            get: { Double(appModel.stabilizerParameters.positionLerpFactor) },
            set: { newValue in
                appModel.updateStabilizerParameters { $0.positionLerpFactor = Float(newValue) }
            }
        )
    }

    private var positionDeadbandBinding: Binding<Double> {
        Binding(
            get: { Double(appModel.stabilizerParameters.positionDeadbandMeters) },
            set: { newValue in
                appModel.updateStabilizerParameters { $0.positionDeadbandMeters = Float(newValue) }
            }
        )
    }

    private var yawLerpBinding: Binding<Double> {
        Binding(
            get: { Double(appModel.stabilizerParameters.yawLerpFactor) },
            set: { newValue in
                appModel.updateStabilizerParameters { $0.yawLerpFactor = Float(newValue) }
            }
        )
    }

    private var yawFlipThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(radiansToDegrees(appModel.stabilizerParameters.yawFlipThresholdRadians)) },
            set: { newValue in
                appModel.updateStabilizerParameters { $0.yawFlipThresholdRadians = Float(newValue) * .pi / 180 }
            }
        )
    }

    private var temporaryLossBinding: Binding<Double> {
        Binding(
            get: { appModel.stabilizerParameters.temporaryLossDuration },
            set: { newValue in
                appModel.updateStabilizerParameters { $0.temporaryLossDuration = newValue }
            }
        )
    }
}
