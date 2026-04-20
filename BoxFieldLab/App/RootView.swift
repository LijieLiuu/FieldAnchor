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

                    Picker(
                        "Validation Mode",
                        selection: Binding(
                            get: { appModel.validationMode },
                            set: { appModel.setValidationMode($0) }
                        )
                    ) {
                        ForEach(ValidationMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Text(appModel.validationMode.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

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

                        HStack {
                            Button(appModel.replayPlaybackState.isPlaying ? "Pause" : "Play") {
                                appModel.toggleReplayPlayback()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Restart") {
                                appModel.restartReplay()
                            }
                            .buttonStyle(.bordered)
                        }

                        Picker("Playback Speed", selection: replaySpeedBinding) {
                            Text("0.5x").tag(0.5)
                            Text("1.0x").tag(1.0)
                            Text("2.0x").tag(2.0)
                        }

                        LabeledContent("Replay Status", value: appModel.replayPlaybackState.statusLabel)
                        LabeledContent("Replay Elapsed", value: appModel.replayPlaybackState.formattedElapsed)
                    }

                    if appModel.inputMode == .manualScripted {
                        Toggle(
                            "Show Manual Box",
                            isOn: Binding(
                                get: { appModel.manualObjectVisible },
                                set: { appModel.manualObjectVisible = $0 }
                            )
                        )

                        Text("Manual Scripted is only a smoke test path. Replay Scenario is the preferred simulator workflow.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if appModel.inputMode == .objectTracking {
                        Text("Object Tracking requires Vision Pro hardware and automatically switches the immersive scene to Full Space so ARKit tracking can run correctly.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Lifecycle", value: appModel.stabilizedState.trackingState.label)
                    LabeledContent("Synthetic Input", value: appModel.runtimeSummary.isSyntheticInput ? "Yes" : "No")
                    LabeledContent("Active Scenario", value: appModel.runtimeSummary.activeScenarioName)
                    LabeledContent("Reference Asset", value: appModel.runtimeSummary.referenceAssetName)
                    LabeledContent("Field Visual", value: appModel.fieldVisualSourceName)
                    LabeledContent("Provider State", value: appModel.runtimeSummary.providerState)
                    LabeledContent("Authorization", value: appModel.runtimeSummary.authorizationState)

                    if let latestError = appModel.runtimeSummary.latestError, latestError.isEmpty == false {
                        Text(latestError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Auto Validation") {
                    HStack {
                        Button("Run Validation Suite") {
                            appModel.startValidationSuite()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Stop") {
                            appModel.stopValidationSuite()
                        }
                        .buttonStyle(.bordered)
                    }

                    LabeledContent("Suite Status", value: appModel.validationSuiteStatus.phase.label)
                    LabeledContent("Current Run", value: "\(appModel.validationSuiteStatus.currentRunIndex)/\(appModel.validationSuiteStatus.totalRuns)")
                    LabeledContent("Scenario", value: appModel.validationSuiteStatus.currentScenarioName)
                    LabeledContent("Preset", value: appModel.validationSuiteStatus.currentPresetName)
                    LabeledContent("Run Elapsed", value: appModel.validationSuiteStatus.formattedCurrentElapsed)
                    LabeledContent("Suite Elapsed", value: appModel.validationSuiteStatus.formattedTotalElapsed)

                    Text(appModel.validationSuiteStatus.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(appModel.validationRecommendation)
                        .font(.footnote)
                }

                Section("Validation Summary") {
                    LabeledContent("Overall", value: appModel.validationOverview.overallAssessment)
                    LabeledContent("Best Preset", value: appModel.validationOverview.bestPresetName)
                    LabeledContent("Pass Runs", value: "\(appModel.validationOverview.passCount)")
                    LabeledContent("Attention Runs", value: "\(appModel.validationOverview.attentionCount)")
                    LabeledContent("Total Runs", value: "\(appModel.validationOverview.totalRuns)")

                    Text(appModel.validationOverview.primaryConcern)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Preset Comparison") {
                    if appModel.validationPresetSummaries.isEmpty {
                        Text("No preset comparison yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.validationPresetSummaries) { summary in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.preset.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(summary.scoreSummary)
                                    .font(.footnote)
                                Text("Avg Pos \(summary.formattedAveragePositionDelta), Avg Max Yaw \(summary.formattedAverageMaxYawDelta)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Stabilizer Parameters") {
                    LabeledContent("Current Preset", value: appModel.appliedPreset?.label ?? "Custom")

                    Menu("Apply Preset") {
                        ForEach(StabilizerPreset.allCases) { preset in
                            Button(preset.label) {
                                appModel.applyPreset(preset)
                            }
                        }
                    }

                    Button("Reset to Defaults") {
                        appModel.resetParametersToDefaults()
                    }

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

                Section("Stability Summary") {
                    LabeledContent("Lifecycle", value: appModel.debugSnapshot.lifecycleState.label)
                    LabeledContent("Position Delta", value: appModel.debugSnapshot.formattedPositionDelta)
                    LabeledContent("Yaw Delta", value: appModel.debugSnapshot.formattedYawDelta)
                    LabeledContent("Last Seen Age", value: appModel.debugSnapshot.formattedLastSeenAge)
                    LabeledContent("Recent Transitions", value: "\(appModel.metricsSnapshot.recentTransitionCount)")
                    LabeledContent("Yaw Rejects", value: "\(appModel.metricsSnapshot.yawRejectCount)")
                }

                Section("Rolling Metrics") {
                    LabeledContent("Window", value: appModel.metricsSnapshot.formattedWindow)
                    LabeledContent("Samples", value: "\(appModel.metricsSnapshot.sampleCount)")
                    LabeledContent("Max Position Delta", value: appModel.metricsSnapshot.formattedMaxPositionDelta)
                    LabeledContent("Avg Position Delta", value: appModel.metricsSnapshot.formattedAveragePositionDelta)
                    LabeledContent("Max Yaw Delta", value: appModel.metricsSnapshot.formattedMaxYawDelta)
                    LabeledContent("Temporary-Loss Entries", value: "\(appModel.metricsSnapshot.temporaryLossCount)")
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

                Section("Marker Guide") {
                    Text("Red visuals represent raw tracking input.")
                    Text("Green visuals represent the stabilized display pose.")
                    Text("Yellow visuals represent the attachment offset and field mount point.")
                }

                Section("Debug Snapshot") {
                    LabeledContent("Raw Position", value: appModel.debugSnapshot.formattedRawPosition)
                    LabeledContent("Display Position", value: appModel.debugSnapshot.formattedDisplayPosition)
                    LabeledContent("Raw Yaw", value: appModel.debugSnapshot.formattedRawYaw)
                    LabeledContent("Display Yaw", value: appModel.debugSnapshot.formattedDisplayYaw)
                    LabeledContent("Position Delta", value: appModel.debugSnapshot.formattedPositionDelta)
                    LabeledContent("Yaw Delta", value: appModel.debugSnapshot.formattedYawDelta)
                    LabeledContent("Last Seen Age", value: appModel.debugSnapshot.formattedLastSeenAge)
                    LabeledContent("Replay Elapsed", value: appModel.debugSnapshot.formattedReplayElapsed)
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

                Section("Attention Items") {
                    if appModel.validationAttentionResults.isEmpty {
                        Text("No attention items. The current suite looks qualified for simulator-only work.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.validationAttentionResults) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(result.scenario.label) • \(result.preset.label)")
                                    .font(.subheadline.weight(.semibold))
                                Text(result.summary)
                                    .font(.footnote)
                                Text("Avg Pos \(result.formattedAveragePositionDelta), Max Pos \(result.formattedMaxPositionDelta), Max Yaw \(result.formattedMaxYawDelta)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Validation Report") {
                    Text("This block is meant to be copied into notes, a weekly report, or a handoff document.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("Show Full Report") {
                        Text(appModel.validationReportText)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("Notes") {
                    Text("Use Replay Scenario as the default no-hardware workflow. Compare presets, replay speed, raw/display deltas, and lifecycle behavior before moving to Vision Pro hardware.")
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

    private var replaySpeedBinding: Binding<Double> {
        Binding(
            get: { appModel.replayPlaybackState.speedMultiplier },
            set: { newValue in
                appModel.setReplaySpeed(newValue)
            }
        )
    }
}
