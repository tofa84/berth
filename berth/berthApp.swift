//
//  berthApp.swift
//  berth
//
//  Created by Falco Tomasetti on 28.06.26.
//

import SwiftUI

@main
struct berthApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    #if DEBUG
                    if SelfTest.isEnabled { await SelfTest.run(model); exit(0) }
                    #endif
                    model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 822)
    }
}
