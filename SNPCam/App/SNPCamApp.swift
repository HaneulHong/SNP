import SwiftUI

@main
struct SNPCamApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
