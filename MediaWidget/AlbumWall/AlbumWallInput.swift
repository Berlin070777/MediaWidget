import AppKit

final class MediaMainWindow: NSWindow {
    let albumInput = AlbumWallInput()

    override func sendEvent(_ event: NSEvent) {
        let sliderHasKeyboardFocus = event.type == .keyDown && firstResponder is NSSlider
        if isKeyWindow, attachedSheet == nil, !sliderHasKeyboardFocus,
           albumInput.handle(event, in: contentView) {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class AlbumWallInput {
    private var owner: UUID?
    private var wheelArea = CGRect.zero
    private var trackingWheel = false
    private var onKey: ((UInt16) -> Bool)?
    private var onScroll: ((NSEvent) -> Bool)?

    func register(_ owner: UUID, area: CGRect,
                  onKey: @escaping (UInt16) -> Bool, onScroll: @escaping (NSEvent) -> Bool) {
        if self.owner != owner { trackingWheel = false }
        self.owner = owner
        wheelArea = area
        self.onKey = onKey
        self.onScroll = onScroll
    }

    func unregister(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        onKey = nil
        onScroll = nil
        trackingWheel = false
    }

    func handle(_ event: NSEvent, in view: NSView?) -> Bool {
        switch event.type {
        case .keyDown:
            guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
            return onKey?(event.keyCode) == true
        case .scrollWheel:
            guard let view, let onScroll else { return false }
            let location = view.convert(event.locationInWindow, from: nil)
            let y = view.isFlipped ? location.y - view.bounds.minY : view.bounds.maxY - location.y
            let point = CGPoint(x: location.x - view.bounds.minX, y: y)
            let phase = event.phase
            let momentum = event.momentumPhase
            if phase.contains(.mayBegin) || phase.contains(.began) { trackingWheel = false }
            let isGesture = !phase.isEmpty || !momentum.isEmpty
            guard wheelArea.contains(point) || (trackingWheel && isGesture) else { return false }
            let handled = onScroll(event)
            // Keep routing a precise gesture after finger lift so its momentum
            // reaches the same shelf even if the pointer has moved.
            if phase.contains(.cancelled) || momentum.contains(.ended) || momentum.contains(.cancelled)
                || (phase.contains(.ended) && !event.hasPreciseScrollingDeltas) {
                trackingWheel = false
            } else if handled && isGesture {
                trackingWheel = true
            }
            return handled
        default:
            return false
        }
    }
}
