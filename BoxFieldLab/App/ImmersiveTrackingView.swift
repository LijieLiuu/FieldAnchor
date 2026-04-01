import RealityKit
import SwiftUI

struct ImmersiveTrackingView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        RealityView { content in
            content.add(appModel.sceneRootEntity)
            appModel.sceneInstalled()
        } placeholder: {
            ProgressView("Preparing immersive scene")
        }
        .task {
            await appModel.startRuntimeLoopIfNeeded()
        }
    }
}
