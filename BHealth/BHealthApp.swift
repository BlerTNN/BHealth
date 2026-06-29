//
//  BHealthApp.swift
//  BHealth
//
//  Created by Bill on 2026-06-26.
//

import SwiftUI
import SwiftData

@main
struct BHealthApp: App {
    @StateObject private var healthDashboardStore = HealthDashboardStore()
    @StateObject private var appSettings = AppSettings()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthDashboardStore)
                .environmentObject(appSettings)
                .environment(\.locale, appSettings.locale)
        }
        .modelContainer(sharedModelContainer)
    }
}
