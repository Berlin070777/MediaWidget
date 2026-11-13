import AppKit
import Carbon
import SwiftUI

/// Application delegate that owns the global hot key and the floating control panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// The floating panel, created lazily on first use.
    private var floatingPanel: NSPanel?

    /// Carbon hot key registration handle.
    private var hotKeyRef: EventHotKeyRef?

    /// Carbon event handler reference, kept so it can be removed on termination.
    private var hotKeyHandlerRef: EventHandlerRef?

    /// The hot key: ⌘⇧M (virtual key code 0x2E = "M").
    private let hotKeyCode: UInt32 = 0x2E
    private let hotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only – no Dock icon unless the user asks for one.
        NSApp.setActivationPolicy(
            UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory
        )

        registerGlobalHotKey()

        // Start listening immediately instead of waiting for the menu bar popover
        // to appear, so the widget and the floating panel always have fresh data.
        MediaMonitor.shared.startMonitoring()

        // Development convenience:
        //   defaults write com.mediawidget.app showPanelOnLaunch -bool YES
        if UserDefaults.standard.bool(forKey: "showPanelOnLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.presentFloatingPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaMonitor.shared.stopMonitoring()

        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = hotKeyHandlerRef {
            RemoveEventHandler(handler)
            hotKeyHandlerRef = nil
        }
    }

    // MARK: - Global Hotkey (⌘⇧M)

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D575F48), // "MW_H"
                                     id: 1)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // Install Carbon event handler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }

                var hotkeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                if result == noErr && hotkeyID.id == 1 {
                    // The handler is installed on the application event target, so this
                    // always runs on the main thread. Resolve the delegate inside the
                    // isolated closure; `UnsafeMutableRawPointer` is not `Sendable`, so
                    // it is funnelled through `Int`.
                    let opaque = Int(bitPattern: userData)
                    MainActor.assumeIsolated {
                        guard let pointer = UnsafeMutableRawPointer(bitPattern: opaque) else { return }
                        Unmanaged<AppDelegate>
                            .fromOpaque(pointer)
                            .takeUnretainedValue()
                            .toggleFloatingPanel()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )

        guard status == noErr else {
            NSLog("[AppDelegate] Failed to install event handler: \(status)")
            return
        }

        let regStatus = RegisterEventHotKey(
            hotKeyCode,
            hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            NSLog("[AppDelegate] Failed to register hotkey: \(regStatus)")
        }
    }

    // MARK: - Floating Panel

    /// Shows or hides the floating panel.
    func toggleFloatingPanel() {
        if let panel = floatingPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            presentFloatingPanel()
        }
    }

    /// Brings the floating panel on screen, creating it on first use.
    func presentFloatingPanel() {
        let panel = floatingPanel ?? makeFloatingPanel()
        floatingPanel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideFloatingPanel() {
        floatingPanel?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// The red traffic light hides the panel instead of tearing it down, so the
    /// next ⌘⇧M brings back the very same window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func makeFloatingPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 370),
            // Native macOS traffic lights (close / miniaturize / zoom).
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        panel.standardWindowButton(.zoomButton)?.isHidden = false
        panel.minSize = NSSize(width: 320, height: 300)
        panel.delegate = self
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: FloatingPanelView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Wrap in a container so the rounded corners are clipped reliably.
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        panel.contentView = container
        return panel
    }
}
