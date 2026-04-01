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

                    LabeledContent("Lifecycle", value: appModel.stabilizedState.trackingState.label)
                    LabeledContent("Reference Asset", value: appModel.runtimeSummary.referenceAssetName)
                    LabeledContent("Provider State", value: appModel.runtimeSummary.providerState)
                    LabeledContent("Authorization", value: appModel.runtimeSummary.authorizationState)

                    if let latestError = appModel.runtimeSummary.latestError, latestError.isEmpty == false {
                        Text(latestError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if appModel.inputMode == .manualDemo {
                        Toggle(
                            "Show Manual Box",
                            isOn: Binding(
                                get: { appModel.manualObjectVisible },
                                set: { appModel.manualObjectVisible = $0 }
                            )
                        )
                    }
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
                        "Show Stabilized Attachment Gizmo",
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
                }

                Section("Diagnostics") {
                    LabeledContent("Position Delta", value: appModel.diagnostics.formattedPositionDelta)
                    LabeledContent("Yaw Delta", value: appModel.diagnostics.formattedYawDelta)
                    LabeledContent("Field Opacity", value: appModel.diagnostics.formattedOpacity)
                    LabeledContent("Current Mode", value: appModel.runtimeSummary.inputMode.label)
                }

                Section("Notes") {
                    Text("Use Manual Demo in the simulator. Switch to Object Tracking on Vision Pro after adding a Box.referenceObject file to the app bundle.")
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
}
