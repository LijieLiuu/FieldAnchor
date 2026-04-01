import SwiftUI

@main
struct BoxFieldLabApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveTrackingView()
                .environmentObject(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
