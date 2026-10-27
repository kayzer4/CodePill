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
                }
        }
    }
}
