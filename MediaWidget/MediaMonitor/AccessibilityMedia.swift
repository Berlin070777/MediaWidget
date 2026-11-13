import AppKit
import ApplicationServices

enum AccessibilityMedia {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return app
    }

    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, "AXChildren") ?? [] }
    static func title(_ element: AXUIElement) -> String { value(element, "AXTitle") ?? "" }
    static func classes(_ element: AXUIElement) -> [String] { value(element, "AXDOMClassList") ?? [] }
    static func enabled(_ element: AXUIElement) -> Bool { value(element, "AXEnabled") ?? false }

    static func press(_ element: AXUIElement) -> Bool {
        enabled(element) && AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func find(in root: AXUIElement, limit: Int, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        var pending = [root]
        for _ in 0..<limit {
            guard let element = pending.popLast() else { return nil }
            if matches(element) { return element }
            pending.append(contentsOf: children(element).reversed())
        }
        return nil
    }

    static func seconds(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        let values = parts.compactMap { Int($0) }
        guard (2...3).contains(parts.count), values.count == parts.count,
              values.allSatisfy({ (0...9999).contains($0) }),
              values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return Double(values.reduce(0) { $0 * 60 + $1 })
    }
}
