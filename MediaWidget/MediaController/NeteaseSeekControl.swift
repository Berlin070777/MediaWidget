import AppKit
import ApplicationServices
import CoreGraphics

enum NeteaseSeekControl {
    // The normal window in this client build has a full-width transport track
    // above its 82-point footer. The app doesn't expose an AX slider.
    private static let supportedBuild = "3444"
    private static let footerHeight: CGFloat = 81.5

    private struct PlayerWindow {
        let element: AXUIElement
        let bounds: CGRect
        let minimized: Bool
    }

    static func supports(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, let bundle = Bundle(url: url) else { return false }
        return bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == supportedBuild
    }

    static func canSeek(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), supports(app), CGPreflightPostEventAccess() else {
            return false
        }
        return normalWindow(for: pid) != nil
    }

    @MainActor
    static func seek(pid: pid_t, fraction: Double, stillCurrent: @Sendable () async -> Bool) async -> Bool {
        guard fraction.isFinite, let app = NSRunningApplication(processIdentifier: pid), supports(app),
              CGPreflightPostEventAccess(), let window = normalWindow(for: pid) else { return false }

        let previous = NSWorkspace.shared.frontmostApplication
        let wasHidden = app.isHidden
        if wasHidden { app.unhide() }
        defer {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                if window.minimized {
                    _ = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                }
                if wasHidden { app.hide() }
                if let previous, previous.processIdentifier != pid { previous.activate() }
            }
        }

        if window.minimized {
            guard AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
            else { return false }
        }
        app.activate()
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let ready = await waitForTarget(window.element, pid: pid, fraction: fraction)
        guard ready, await stillCurrent(), !Task.isCancelled,
              let point = targetPoint(in: window.element, pid: pid, fraction: fraction) else { return false }
        let cursor = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return false }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Let the client handle the click before returning focus to the panel.
        try? await Task.sleep(for: .milliseconds(120))
        if let cursor, let current = CGEvent(source: nil)?.location,
           abs(current.x - point.x) <= 2, abs(current.y - point.y) <= 2 {
            CGWarpMouseCursorPosition(cursor)
        }
        return true
    }

    @MainActor
    private static func waitForTarget(_ window: AXUIElement, pid: pid_t, fraction: Double) async -> Bool {
        for _ in 0..<16 {
            if Task.isCancelled { return false }
            if targetPoint(in: window, pid: pid, fraction: fraction) != nil { return true }
            try? await Task.sleep(for: .milliseconds(65))
        }
        return false
    }

    @MainActor
    private static func targetPoint(in window: AXUIElement, pid: pid_t, fraction: Double) -> CGPoint? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = normalWindow(for: pid), !current.minimized, CFEqual(window, current.element) else { return nil }
        let bounds = current.bounds
        let point = CGPoint(x: bounds.minX + min(max(bounds.width * fraction, 1), bounds.width - 1),
                            y: bounds.maxY - footerHeight)
        return windowOwns(point, expected: window, pid: pid) ? point : nil
    }

    private static func normalWindow(for pid: pid_t) -> PlayerWindow? {
        let ax = AccessibilityMedia.application(pid)
        guard let bar: AXUIElement = AccessibilityMedia.value(ax, kAXMenuBarAttribute),
              let windowMenu = AccessibilityMedia.children(bar).first(where: {
                  ["窗口", "Window"].contains(AccessibilityMedia.title($0))
              }),
              let menu = AccessibilityMedia.children(windowMenu).first,
              AccessibilityMedia.children(menu).contains(where: {
                  ["切换至迷你模式", "Switch to Mini Player", "Switch to Mini Mode"].contains(AccessibilityMedia.title($0))
              }) else { return nil }
        let windows: [AXUIElement] = AccessibilityMedia.value(ax, kAXWindowsAttribute) ?? []
        for window in windows.prefix(3) {
            let subrole: String? = AccessibilityMedia.value(window, kAXSubroleAttribute)
            let minimized: Bool = AccessibilityMedia.value(window, kAXMinimizedAttribute) ?? false
            let fullScreen: Bool = AccessibilityMedia.value(window, "AXFullScreen") ?? false
            let isPlayerWindow = subrole == kAXStandardWindowSubrole || (minimized && subrole == kAXDialogSubrole)
            guard isPlayerWindow, !fullScreen,
                  let position: AXValue = AccessibilityMedia.value(window, kAXPositionAttribute),
                  let size: AXValue = AccessibilityMedia.value(window, kAXSizeAttribute) else { continue }
            var origin = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions),
                  dimensions.width >= 700, dimensions.height >= 420 else { continue }
            return PlayerWindow(element: window, bounds: CGRect(origin: origin, size: dimensions), minimized: minimized)
        }
        return nil
    }

    private static func windowOwns(_ point: CGPoint, expected: AXUIElement, pid: pid_t) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }
        var owner: pid_t = 0
        guard AXUIElementGetPid(hit, &owner) == .success, owner == pid else { return false }
        let hitWindow: AXUIElement? = AccessibilityMedia.value(hit, kAXWindowAttribute)
        return CFEqual(hit, expected) || hitWindow.map { CFEqual($0, expected) } == true
    }
}
