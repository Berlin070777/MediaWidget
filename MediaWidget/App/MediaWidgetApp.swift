// MediaWidgetApp.swift
// MediaWidget
//
// Main app entry point. Menu bar app with optional floating panel.

import SwiftUI

@main
struct MediaWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var mediaMonitor = MediaMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: mediaMonitor, showPanel: { appDelegate.presentFloatingPanel() },
                        showSettings: { appDelegate.presentSettings() })
        } label: {
            Image(systemName: mediaMonitor.currentMedia.isPlaying ? "play.fill" : "play")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: mediaMonitor)
        }
    }
}
