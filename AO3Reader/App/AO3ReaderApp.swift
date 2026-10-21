// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@main
struct AO3ReaderApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.auth.refresh(client: app.client) }
        }
    }
}
