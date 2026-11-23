import SwiftUI

struct AlbumWallCarousel<Tile: View>: View {
    let albums: [WallAlbum]
    let size: CGSize
    let input: AlbumWallInput
    var focus: AlbumWallFocus? = nil
    let showDetails: (WallAlbum) -> Void
    @ViewBuilder let tile: (WallAlbum, CGFloat, Double, CGFloat, Bool, @escaping () -> Void) -> Tile

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputOwner = UUID()
    @State private var wheelArea = CGRect.zero
    @State private var centeredID: String?
    @State private var centerSlot = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var trackpadAxis: Axis?
    @State private var startingDelta = CGSize.zero
    @State private var wheelSettling: Task<Void, Never>?
    @State private var turnedCover: (slot: Int, albumID: String)?
    @State private var turn = AlbumSleeveGesture()

    private var currentIndex: Int { albums.firstIndex { $0.id == centeredID } ?? 0 }
    private var loops: Bool { albums.count > 1 }
    private var coverSize: CGFloat { max(1, min(570, size.width * 0.64, size.height * 0.70)) }
    private var step: CGFloat { max(86, coverSize * 0.52) }
    private var reflectionHeight: CGFloat { min(72, coverSize * 0.16) }

    var body: some View {
        if albums.indices.contains(currentIndex) {
            shelf
                .onChange(of: albums.map(\.id), initial: true) { previous, updated in
                    if centeredID.map({ updated.contains($0) }) != true {
                        let oldIndex = centeredID.flatMap { previous.firstIndex(of: $0) } ?? 0
                        centeredID = updated.isEmpty ? nil : updated[min(oldIndex, updated.count - 1)]
                        resetTurn()
                    }
                    if updated.count < 2 {
                        wheelSettling?.cancel()
                        scrollOffset = 0
                    }
                }
                .onChange(of: focus, initial: true) { _, request in
                    if let request { reveal(request.albumID) }
                }
                .onAppear { registerInput() }
                .onChange(of: albums) { registerInput() }
                .onChange(of: size) { registerInput() }
                .onChange(of: reduceMotion) { registerInput() }
                .onDisappear {
                    input.unregister(inputOwner)
                    wheelSettling?.cancel()
                }
        }
    }

    private var shelf: some View {
        let sideCount = min(4, Int(ceil((size.width + coverSize) / (2 * step))))
        let visibleCount = loops ? sideCount : 0
        let slots = (centerSlot - visibleCount)...(centerSlot + visibleCount)

        return GeometryReader { proxy in
            ZStack {
                ForEach(slots, id: \.self) { slot in
                    cover(albums[albumIndex(at: slot)], at: slot, in: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { rect in
            wheelArea = rect
            registerInput()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("立体唱片墙")
        .accessibilityHint("双指左右翻阅，上滑或下滑切换正反面")
        .accessibilityActions {
            Button("翻到唱片背面") { showBack(true) }
            Button("翻回唱片正面") { showBack(false) }
        }
    }

    private func reveal(_ id: String) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        let forward = (index - currentIndex + albums.count) % albums.count
        let distance = forward <= albums.count - forward ? forward : forward - albums.count
        select(centerSlot + distance)
    }

    private func registerInput() {
        input.register(inputOwner, area: wheelArea, onKey: handleKey, onScroll: scroll)
    }

    private func albumIndex(at slot: Int) -> Int {
        let index = (currentIndex + slot - centerSlot) % albums.count
        return index < 0 ? index + albums.count : index
    }

    private func cover(_ album: WallAlbum, at slot: Int, in viewport: CGSize) -> some View {
        let offset = slot - centerSlot
        let centered = offset == 0
        let distance = CGFloat(offset) + scrollOffset / step
        let depth = min(1, abs(distance))
        let angle = min(1, max(-1, distance)) * -41
        let scale = 1 - (reduceMotion ? 0.12 : 0.21) * depth
        let baseline = (viewport.height + coverSize - reflectionHeight) / 2
        let fraction = turnedCover?.slot == slot && turnedCover?.albumID == album.id ? turn.progress : 0
        let accessibleOffsets = -((albums.count - 1) / 2)...(albums.count / 2)

        return tile(album, coverSize, fraction, reflectionHeight, centered) {
            if centered {
                showDetails(album)
            } else {
                select(slot)
            }
        }
        .id(album.id)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.42)
        .scaleEffect(scale)
        .opacity(1 - 0.54 * depth)
        .position(x: viewport.width / 2 + distance * step, y: baseline - coverSize * scale / 2)
        .zIndex(10 - Double(abs(distance)))
        .accessibilityAddTraits(centered ? .isSelected : [])
        .accessibilityHint(centered ? "查看专辑详情" : "移到中央")
        .accessibilityHidden(!accessibleOffsets.contains(offset))
    }

    private func handleKey(_ key: UInt16) -> Bool {
        guard !albums.isEmpty else { return false }
        switch key {
        case 123: select(centerSlot - 1)  // Left Arrow
        case 124: select(centerSlot + 1)  // Right Arrow
        case 126: showBack(!turn.isBack)  // Up Arrow
        case 125: showBack(false)  // Down Arrow
        case 36, 76: showDetails(albums[currentIndex])  // Return, Keypad Enter
        case 53 where turn.isTurned: showBack(false)  // Escape
        default: return false
        }
        return true
    }

    private func scroll(_ event: NSEvent) -> Bool {
        guard !albums.isEmpty else { return false }
        if event.hasPreciseScrollingDeltas || !event.momentumPhase.isEmpty
            || (!event.phase.isEmpty && trackpadAxis != nil) {
            return scrollTrackpad(event)
        }
        if event.phase.contains(.began) {
            wheelSettling?.cancel()
            scrollOffset = 0
        }
        if event.phase.contains(.cancelled) {
            guard scrollOffset != 0 else { return false }
            select(centerSlot)
            return true
        }
        if event.phase.contains(.ended) {
            guard scrollOffset != 0 else { return false }
            settle()
            return true
        }

        let horizontal = event.scrollingDeltaX
        guard abs(horizontal) > abs(event.scrollingDeltaY) else { return false }
        advanceScroll(by: horizontal * 16, edgeLimit: 0.20)
        if event.phase.isEmpty { scheduleSettlement(after: .milliseconds(120)) }
        return true
    }

    private func scrollTrackpad(_ event: NSEvent) -> Bool {
        let phase = event.phase
        let momentum = event.momentumPhase
        if phase.contains(.mayBegin) { return false }
        if phase.contains(.began) {
            wheelSettling?.cancel()
            trackpadAxis = nil
            startingDelta = .zero
        }
        if trackpadAxis == .vertical, !momentum.isEmpty {
            if momentum.contains(.ended) || momentum.contains(.cancelled) { trackpadAxis = nil }
            return true
        }
        if phase.contains(.cancelled) || momentum.contains(.cancelled) {
            guard let axis = trackpadAxis else { return false }
            if axis == .vertical {
                settleTurn(at: turn.gestureOrigin)
                trackpadAxis = nil
                return true
            }
            select(centerSlot, animation: .easeOut(duration: 0.18))
            return true
        }
        if phase.contains(.ended) {
            guard let axis = trackpadAxis else { return false }
            if axis == .vertical {
                settleTurn(at: turn.destination(at: event.timestamp))
            } else {
                scheduleSettlement(after: .milliseconds(60), precise: true)
            }
            return true
        }
        if momentum.contains(.ended) {
            guard trackpadAxis == .horizontal else { return false }
            settle(precise: true)
            return true
        }

        var horizontal = event.scrollingDeltaX
        var vertical = event.scrollingDeltaY
        if trackpadAxis == nil {
            guard momentum.isEmpty, max(abs(horizontal), abs(vertical)) > 0 else { return false }
            startingDelta.width += horizontal
            startingDelta.height += vertical
            guard max(abs(startingDelta.width), abs(startingDelta.height)) >= 2 else { return true }
            horizontal = startingDelta.width
            vertical = startingDelta.height
            startingDelta = .zero
            trackpadAxis = abs(horizontal) > abs(vertical) ? .horizontal : .vertical
            if trackpadAxis == .vertical {
                associateTurnWithCurrentAlbum()
                turn.begin()
            } else if turn.isTurned {
                showBack(false)
            }
        }
        wheelSettling?.cancel()
        if trackpadAxis == .vertical {
            let upward = event.isDirectionInvertedFromDevice ? -vertical : vertical
            turn.advance(by: upward, at: event.timestamp, travel: min(300, max(150, coverSize * 0.53)))
            if phase.isEmpty {
                let timestamp = event.timestamp
                wheelSettling = Task {
                    try? await Task.sleep(for: .milliseconds(110))
                    guard !Task.isCancelled else { return }
                    settleTurn(at: turn.destination(at: timestamp + 0.11))
                    trackpadAxis = nil
                }
            }
            return true
        }
        advanceScroll(by: horizontal * 1.24, edgeLimit: 0.29)
        if phase.isEmpty { scheduleSettlement(after: .milliseconds(110), precise: true) }
        return true
    }

    private func advanceScroll(by delta: CGFloat, edgeLimit: CGFloat) {
        let offset = scrollOffset + delta
        guard loops else {
            let limit = step * edgeLimit
            scrollOffset = max(-limit, min(limit, offset))
            return
        }

        // Keep slot identities and on-screen positions continuous past the seam.
        let steps = Int((-offset / step).rounded(.towardZero))
        scrollOffset = offset + CGFloat(steps) * step
        moveCenter(to: centerSlot + steps)
    }

    private func moveCenter(to slot: Int) {
        guard loops, slot != centerSlot else { return }
        centeredID = albums[albumIndex(at: slot)].id
        centerSlot = slot
    }

    private func scheduleSettlement(after delay: Duration, precise: Bool = false) {
        wheelSettling?.cancel()
        wheelSettling = Task {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { settle(precise: precise) }
        }
    }

    private func settle(precise: Bool = false) {
        let threshold = precise ? 0.13 : 0.22
        let shift = abs(scrollOffset) < step * threshold ? 0 : (scrollOffset < 0 ? 1 : -1)
        if precise {
            select(centerSlot + shift, animation: .easeOut(duration: 0.18))
        } else {
            select(centerSlot + shift)
        }
    }

    private func select(_ slot: Int, animation: Animation = .spring(duration: 0.29, bounce: 0.13)) {
        wheelSettling?.cancel()
        trackpadAxis = nil
        withAnimation(reduceMotion ? nil : animation) {
            moveCenter(to: slot)
            scrollOffset = 0
            turn.settle(at: turn.frontDestination)
        }
    }

    private func associateTurnWithCurrentAlbum() {
        let id = albums[currentIndex].id
        if turnedCover?.slot != centerSlot || turnedCover?.albumID != id {
            turn = AlbumSleeveGesture()
            turnedCover = (centerSlot, id)
        }
    }

    private func showBack(_ show: Bool) {
        wheelSettling?.cancel()
        associateTurnWithCurrentAlbum()
        settleTurn(at: show ? turn.backDestination : turn.frontDestination)
    }

    private func settleTurn(at face: Double) {
        wheelSettling?.cancel()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.06)) {
            turn.settle(at: face)
        }
    }

    private func resetTurn() {
        turn = AlbumSleeveGesture()
        turnedCover = nil
    }
}

struct AlbumSleeveGesture {
    private(set) var progress: Double = 0
    private(set) var isBack = false
    private var timestamp: TimeInterval?
    private var speed: Double = 0

    var isTurned: Bool { progress != 0 && progress != 2 }
    var gestureOrigin: Double { isBack ? 1 : 0 }
    var frontDestination: Double { progress > 1 ? 2 : 0 }
    var backDestination: Double { progress < 0 ? -1 : 1 }

    mutating func begin() {
        // A full turn and the initial orientation show the same face.
        progress = gestureOrigin
        timestamp = nil
        speed = 0
    }

    mutating func advance(by points: CGFloat, at time: TimeInterval, travel: CGFloat) {
        let increment = Double(points / travel)
        if let timestamp, time > timestamp {
            let instantaneous = increment / max(0.008, time - timestamp)
            if instantaneous != 0, speed.sign != instantaneous.sign {
                speed = 0
            }
            speed = speed * 0.35 + instantaneous * 0.65
        }
        timestamp = time
        progress = limited(progress + increment)
    }

    func destination(at time: TimeInterval) -> Double {
        let moving = timestamp.map { time - $0 < 0.095 } == true
        let projection = moving ? min(0.27, max(-0.27, speed * 0.10)) : 0
        return limited((progress + projection).rounded())
    }

    private func limited(_ value: Double) -> Double {
        min(gestureOrigin + 1, max(gestureOrigin - 1, value))
    }

    mutating func settle(at face: Double) {
        isBack = abs(face) == 1
        progress = face
        timestamp = nil
        speed = 0
    }
}
