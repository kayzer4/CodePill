import SwiftUI

@main
struct CodePillApp: App {
    @StateObject private var client = CodePillClient()

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .preferredColorScheme(.dark)
                .onAppear {
                    client.connect()
                    let autoStart = UserDefaults.standard.object(forKey: "autoStartLiveActivity") as? Bool ?? true
                    if autoStart {
                        client.startDynamicIsland(prompt: "CodePill Ready", projectName: "CodePill", isBusy: false)
                    }
                }
        }
    }
}
