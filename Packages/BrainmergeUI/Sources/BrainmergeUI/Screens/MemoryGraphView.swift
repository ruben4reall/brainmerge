import AppKit
import SwiftUI
import BrainmergeCore

/// The memory as a living graph, like Obsidian's graph view: every note is a bubble in the color of the account that
/// saved it, links are threads, each project is a hub. Notes pulse when they are written and again when an account
/// saves them. Hover lights a note and its neighbors; click shows it; double-click opens it in your notes app.
/// Drag the background to move around, drag a bubble to pull it, pinch or use the mouse wheel to zoom.
/// With keyboard navigation on, the arrow keys go from note to note, Return opens one, Escape closes it.
///
/// An Obsidian vault is drawn the way Obsidian draws it: its colors, sizes, forces and zoom, labels that fade in as you
/// zoom, one click to open a note in Obsidian, a secondary click (or Option-click) for the inspector.
struct MemoryGraphView: View {
    @Bindable var graph: MemoryGraphModel
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTarget: String?
    @State private var panOrigin: CGPoint?
    @State private var magnifyBase: GraphCamera?
    @State private var monitor: Any?
    @State private var clickMonitor: Any?
    @State private var host = WindowBox()
    /// An account clicked in the legend: its notes stay lit until it is clicked again.
    @State private var pinnedAccount: String?
    @State private var preview = ""
    /// Set by the capture script: the pointer may rest over the window by chance, and a screenshot should show the graph unlit.
    static let capturing = ProcessInfo.processInfo.environment["BRAINMERGE_CAPTURE"] != nil

    var tints: [String: Color] {
        Dictionary(app.accounts.map { ($0.id, Theme.color(for: $0.identity.tint)) }, uniquingKeysWith: { a, _ in a })
    }

    var noteCount: Int { graph.graph.nodes.reduce(0) { $0 + ($1.kind == .note ? 1 : 0) } }
    var isVault: Bool { graph.style == .vault }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                canvas
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size: geo.size))
                    .simultaneousGesture(magnifyGesture(size: geo.size))
                    .onTapGesture(coordinateSpace: .local) { point in tap(at: point, size: geo.size) }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point):
                            graph.pointer = point
                            if !Self.capturing { graph.hovered = note(at: point, size: geo.size) }
                        case .ended: graph.pointerLeft()
                        }
                    }
                    .focusable(interactions: .activate)
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .escape]) { press in key(press.key) }
                    .accessibilityLabel("Memory graph")
                    .accessibilityValue(summary)
                    .accessibilityChildren { accessibleNotes }
                if noteCount == 0 { emptyState }
                VStack {
                    HStack(alignment: .top) {
                        // A vault has no accounts: Obsidian's graph has no legend either.
                        if !isVault { legend }
                        Spacer()
                        if let id = graph.selected { inspector(id).transition(.opacity) }
                    }
                    Spacer()
                    HStack(alignment: .bottom) { status; Spacer(); controls(size: geo.size) }
                }
                .padding(12)
            }
            .background(isVault ? Theme.Colors.vaultBackground : Color.clear)
            .background(WindowReader(box: host))
            .onAppear {
                graph.viewSize = geo.size; graph.reduceMotion = reduceMotion
                graph.backingScale = host.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
                installScrollMonitor()
            }
            .onChange(of: geo.size) { _, size in graph.viewSize = size }
            .onChange(of: reduceMotion) { _, value in graph.reduceMotion = value }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)) { note in
                if let window = note.object as? NSWindow, window === host.window { graph.backingScale = window.backingScaleFactor }
            }
            .onDisappear {
                removeScrollMonitor()
                graph.pointerLeft()
                if dragTarget != nil { graph.endDrag() }
                dragTarget = nil; panOrigin = nil; magnifyBase = nil
                graph.stop()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous).strokeBorder(Theme.Colors.surfaceLine, lineWidth: 1))
        .task(id: app.graphTarget.key) {
            pinnedAccount = nil
            let target = app.graphTarget
            if let window = host.window { graph.backingScale = window.backingScaleFactor }
            await graph.refresh(root: target.root, style: target.style)
            while !Task.isCancelled {
                // Two seconds between reads; longer for a folder so large that one read takes a while.
                try? await Task.sleep(for: .seconds(max(2, graph.lastRefreshDuration * 4)))
                if Task.isCancelled { break }
                // A minimized or hidden window does not read the folder; it catches up as soon as it shows again.
                if let window = host.window, !window.occlusionState.contains(.visible) { continue }
                await graph.refresh(root: target.root, style: target.style)
            }
        }
        // The inspector's text, read off the main thread, and read again when the note changes while it is open.
        .task(id: previewKey) {
            var text = ""
            if let id = graph.selected { text = await graph.loadPreview(id) }
            if !Task.isCancelled { preview = text }
        }
    }

    var previewKey: String {
        guard let id = graph.selected else { return "" }
        return "\(id)|\(graph.graph.node(id)?.modified?.timeIntervalSinceReferenceDate ?? 0)"
    }

    @ViewBuilder var canvas: some View {
        if isVault {
            VaultCanvas(graph: graph)
        } else {
            GraphCanvas(graph: graph, tints: tints, focus: graph.focus, reduceMotion: reduceMotion)
        }
    }

    // MARK: Pointer and keyboard

    func note(at point: CGPoint, size: CGSize) -> String? { graph.node(at: point, in: size) }

    /// One click selects, a double click opens: one gesture, so a single click is not held back by the double-click delay.
    /// In a vault, as in Obsidian, one click opens the note; Option- or Control-click shows the inspector.
    func tap(at point: CGPoint, size: CGSize) {
        let id = note(at: point, size: size)
        if isVault {
            let event = NSApp.currentEvent
            if let flags = event?.modifierFlags, flags.contains(.option) || flags.contains(.control) { select(id); return }
            guard (event?.clickCount ?? 1) == 1 else { return }
            if let id { open(id) } else { select(nil) }
            return
        }
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            if let id { open(id) }
            return
        }
        select(id)
    }

    func select(_ id: String?) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { graph.selected = id }
    }

    /// Every bubble in a stable order for the keyboard and VoiceOver: projects first, then notes, by name.
    var orderedNodes: [MemoryGraph.Node] { Self.ordered(graph.graph.nodes) }

    static func ordered(_ nodes: [MemoryGraph.Node]) -> [MemoryGraph.Node] {
        nodes.sorted {
            // Hubs first; every other kind shares one order by name, so the order stays total with a vault's kinds.
            let hub0 = $0.kind == .project, hub1 = $1.kind == .project
            if hub0 != hub1 { return hub0 }
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func key(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .escape:
            guard graph.selected != nil else { return .ignored }
            select(nil); return .handled
        case .return:
            guard let id = graph.selected else { return .ignored }
            open(id); return .handled
        default:
            let order = orderedNodes.map(\.id)
            guard !order.isEmpty else { return .ignored }
            let step = key == .leftArrow || key == .upArrow ? -1 : 1
            let index = graph.selected.flatMap { order.firstIndex(of: $0) }.map { ($0 + step + order.count) % order.count }
                ?? (step > 0 ? 0 : order.count - 1)
            select(order[index])
            graph.reveal(order[index])
            return .handled
        }
    }

    func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                graph.fitted = true
                if dragTarget == nil, panOrigin == nil {
                    if let id = note(at: value.startLocation, size: size) { dragTarget = id } else { panOrigin = graph.camera.center }
                }
                if let id = dragTarget {
                    graph.drag(id, to: graph.camera.toWorld(value.location, in: size))
                } else if let origin = panOrigin {
                    graph.camera.center = graph.camera.dragged(from: origin, by: value.translation)
                }
            }
            .onEnded { _ in
                if dragTarget != nil { graph.endDrag() }
                dragTarget = nil; panOrigin = nil
            }
    }

    func magnifyGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                graph.fitted = true
                if magnifyBase == nil { magnifyBase = graph.camera }
                var camera = magnifyBase!
                camera.zoom(by: value.magnification, around: value.startLocation, in: size)
                graph.camera = camera
            }
            .onEnded { _ in magnifyBase = nil }
    }

    /// Trackpad scrolling moves around (the graph follows the fingers, like a map), a mouse wheel zooms around the
    /// pointer. Only while the pointer is over this graph, in this window: every other scroll goes where it belongs.
    func installScrollMonitor() {
        installClickMonitor()
        guard monitor == nil else { return }
        let graph = self.graph, host = self.host
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let precise = event.hasPreciseScrollingDeltas, dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let pointer = graph.pointer, let window = host.window, window.windowNumber == windowNumber else { return false }
                graph.fitted = true
                if precise {
                    graph.camera.pan(by: CGSize(width: dx, height: dy))
                } else {
                    graph.camera.zoom(by: exp(dy * 0.08), around: pointer, in: graph.viewSize)
                }
                return true
            }
            return handled ? nil : event
        }
    }

    func removeScrollMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        monitor = nil; clickMonitor = nil
    }

    /// In a vault, a secondary click on a note shows the inspector, since a plain click opens the note in Obsidian.
    func installClickMonitor() {
        guard clickMonitor == nil else { return }
        let graph = self.graph, host = self.host
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard graph.style == .vault, let pointer = graph.pointer, let window = host.window, window.windowNumber == windowNumber else { return false }
                graph.selected = graph.node(at: pointer, in: graph.viewSize)
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: Opening

    var target: NotesTarget { NotesApps.target(for: app.notesApp, installed: NotesApps.installed()) }

    func open(_ id: String) {
        guard let url = graph.fileURL(id) else { return }
        if isVault {
            // A vault's note opens where it lives: in Obsidian, whatever app opens the memory.
            if let link = NotesApps.obsidianURL(for: url) { NSWorkspace.shared.open(link) }
            return
        }
        NotesApps.open(url, with: target)
    }

    func openLabel(for id: String) -> String {
        if isVault { return "Open in Obsidian" }
        if case .folder = target { return graph.graph.node(id)?.file == nil ? "Open folder" : "Open note" }
        return target.label
    }

    // MARK: Accessibility

    var summary: String {
        let links = graph.graph.edges.count
        if isVault { return "\(noteCount) note\(noteCount == 1 ? "" : "s"), \(links) link\(links == 1 ? "" : "s")" }
        let projects = graph.graph.nodes.count - noteCount
        return "\(noteCount) note\(noteCount == 1 ? "" : "s"), \(projects) project\(projects == 1 ? "" : "s"), \(links) link\(links == 1 ? "" : "s")"
    }

    /// One element per bubble for VoiceOver (the first 500 in name order): select it, or open it.
    @ViewBuilder var accessibleNotes: some View {
        let nodes = Array(orderedNodes.prefix(500))
        ForEach(nodes) { (node: MemoryGraph.Node) in
            let selected: AccessibilityTraits = graph.selected == node.id ? .isSelected : []
            Rectangle().fill(Color.clear)
                .accessibilityLabel(Text(spoken(node)))
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(selected)
                .accessibilityAction { select(node.id); graph.reveal(node.id) }
                .accessibilityAction(named: Text("Open")) { open(node.id) }
        }
    }

    func spoken(_ node: MemoryGraph.Node) -> String {
        if node.kind == .project {
            let notes = graph.neighbors(of: node.id).filter { !$0.hasPrefix("project:") }.count
            return "\(node.title), project, \(notes) note\(notes == 1 ? "" : "s")"
        }
        return [node.title, node.project, savedLine(node)].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Overlays

    /// What an empty graph says: why nothing shows, and what to do when macOS refused to let Brainmerge read the folder.
    static func emptyText(vault: Bool, refused: Bool) -> String {
        if refused {
            return "Brainmerge may not read this \(vault ? "vault" : "memory folder"). Allow it in System Settings, Privacy & Security, Files & Folders."
        }
        return vault ? "Nothing to show. This vault has no notes yet, or its graph filters in Obsidian hide them all."
                     : "No notes yet. Open an account and work on a project: what Claude Code remembers appears here as it happens."
    }

    var emptyState: some View {
        Text(Self.emptyText(vault: isVault, refused: graph.refused))
            .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            .frame(maxWidth: 380)
    }

    /// The accounts whose notes are in view, in their colors, with how many notes each saved last.
    /// Hovering one lights its notes; clicking one keeps them lit.
    var legend: some View {
        let present = Set(graph.graph.nodes.filter { $0.kind == .note }.map(\.id))
        let slugs = Dictionary(grouping: graph.authors.filter { present.contains($0.key) }.values.compactMap(\.slug), by: { $0 }).mapValues(\.count)
        let ordered = app.accounts.filter { slugs[$0.id] != nil }.sorted { (slugs[$0.id] ?? 0) > (slugs[$1.id] ?? 0) }
        return HStack(spacing: 6) {
            ForEach(ordered) { account in
                let pinned = pinnedAccount == account.id
                let count = slugs[account.id] ?? 0
                Button {
                    pinnedAccount = pinned ? nil : account.id
                    graph.highlightedAccount = pinnedAccount
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.color(for: account.identity.tint)).frame(width: 8, height: 8)
                        Text("\(account.identity.name) · \(count)").font(Theme.Fonts.caption)
                            .foregroundStyle(pinned ? Theme.Colors.text : Theme.Colors.textMuted)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(pinned ? .regular.tint(Theme.Colors.accentSoft) : .regular, in: Capsule())
                .onHover { inside in graph.highlightedAccount = inside ? account.id : pinnedAccount }
                .help(pinned ? "Show every note again" : "Light the notes \(account.identity.name) saved")
                .accessibilityLabel("\(account.identity.name): \(count) note\(count == 1 ? "" : "s")")
                .accessibilityAddTraits(pinned ? .isSelected : [])
            }
        }
    }

    /// "Live", or "Changed just now" for four seconds after a change: redrawn once more when those seconds are over.
    var status: some View {
        TimelineView(.explicit(graph.lastChange.map { [$0.addingTimeInterval(4.05)] } ?? [])) { context in
            let recent = graph.lastChange.map { context.date.timeIntervalSince($0) < 4 } ?? false
            let projects = graph.graph.nodes.count - noteCount, links = graph.graph.edges.count
            let projectCount = isVault ? "" : " · \(projects) project\(projects == 1 ? "" : "s")"
            let counts = "\(noteCount) note\(noteCount == 1 ? "" : "s")\(projectCount) · \(links) link\(links == 1 ? "" : "s")\(graph.truncated ? " · the most recent 2,000" : "")"
            HStack(spacing: 6) {
                Circle().fill(recent ? Theme.Colors.accentLight : Theme.Colors.sage).frame(width: 6, height: 6)
                Text("\(Text(recent ? "Changed just now" : "Live").foregroundStyle(Theme.Colors.textMuted)) · \(counts)")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular, in: Capsule())
        }
    }

    func controls(size: CGSize) -> some View {
        HStack(spacing: 6) {
            control("minus", "Zoom out") { graph.fitted = true; graph.camera.zoom(by: 0.8, around: CGPoint(x: size.width / 2, y: size.height / 2), in: size) }
            control("plus", "Zoom in") { graph.fitted = true; graph.camera.zoom(by: 1.25, around: CGPoint(x: size.width / 2, y: size.height / 2), in: size) }
            control("arrow.up.left.and.arrow.down.right", "Fit the whole graph") { graph.fitNow() }
        }
    }

    func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Colors.textMuted)
                .frame(width: 28, height: 28).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .help(label).accessibilityLabel(label)
    }

    /// Who saved the note last and when, from the memory's history; the file's own date when no account saved it.
    func savedLine(_ node: MemoryGraph.Node?) -> String? {
        guard let node else { return nil }
        if let author = graph.authors[node.id] {
            let name = author.slug.flatMap { slug in app.accounts.first { $0.id == slug }?.identity.name } ?? author.name
            return "Saved by \(name) · \(MemoryView.relative(author.date))"
        }
        return node.modified.map { "Changed \(MemoryView.relative($0))" }
    }

    func inspector(_ id: String) -> some View {
        let node = graph.graph.node(id)
        let account = graph.authors[id]?.slug.flatMap { slug in app.accounts.first { $0.id == slug } }
        let notes = node?.kind == .project ? graph.neighbors(of: id).filter { !$0.hasPrefix("project:") }.count : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(node?.title ?? id).font(Theme.Fonts.cardName).lineLimit(2).padding(.top, 5)
                Spacer(minLength: 8)
                Button { select(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Colors.textMuted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close").accessibilityLabel("Close")
            }
            if node?.kind == .project {
                Text("Project · \(notes) note\(notes == 1 ? "" : "s")").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
            } else if node?.kind == .unresolved {
                Text("Linked, but no file has this name yet.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
            } else {
                Text(id).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint).lineLimit(1).truncationMode(.middle)
            }
            if node?.file != nil, let line = savedLine(node) {
                HStack(spacing: 6) {
                    Circle().fill(account.map { Theme.color(for: $0.identity.tint) } ?? Theme.color(for: .gray)).frame(width: 7, height: 7)
                    Text(line).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            if !preview.isEmpty {
                Text(preview).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if graph.fileURL(id) != nil {
                HStack(spacing: 8) {
                    Button(openLabel(for: id)) { open(id) }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.small)
                    Button("Show in Finder") { if let url = graph.fileURL(id) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                        .buttonStyle(.glass).controlSize(.small)
                }
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
        .frame(width: 300, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The drawing itself: the only part of the screen that redraws on every animation frame.
private struct GraphCanvas: View {
    let graph: MemoryGraphModel
    let tints: [String: Color]
    let focus: Set<String>?
    let reduceMotion: Bool

    struct Label { let priority: Int; let text: Text; let at: CGPoint; let owner: Int; let forced: Bool }

    static func radius(_ node: MemoryGraph.Node, degree: Int) -> CGFloat {
        let d = CGFloat(degree).squareRoot()
        return node.kind == .project ? min(7 + d * 1.5, 17) : min(3.5 + d * 1.3, 12)
    }

    var body: some View {
        let _ = graph.frame   // redraw on every animation frame
        let camera = graph.camera, layout = graph.layout, nodes = graph.graph.nodes, lines = graph.lineIndices
        let pulses = graph.pulses, authors = graph.authors, selected = graph.selected, hovered = graph.hovered
        let tints = self.tints, focus = self.focus, reduceMotion = self.reduceMotion
        let now = Date()
        let showAllLabels = camera.scale >= 1.25 || nodes.count <= 40
        Canvas { context, size in
            guard layout.count == nodes.count, !nodes.isEmpty else { return }
            let degree = layout.degree
            func screen(_ i: Int) -> CGPoint { camera.toScreen(layout.position(at: i), in: size) }
            // Threads first, under the bubbles.
            var faint = Path(), lit = Path()
            for (a, b) in lines {
                let isLit = focus.map { $0.contains(nodes[a].id) && $0.contains(nodes[b].id) } ?? false
                if isLit { lit.move(to: screen(a)); lit.addLine(to: screen(b)) } else { faint.move(to: screen(a)); faint.addLine(to: screen(b)) }
            }
            context.stroke(faint, with: .color(Theme.Colors.graphLink.opacity(focus == nil ? 1 : 0.5)), lineWidth: 1)
            context.stroke(lit, with: .color(Theme.Colors.graphLinkLit), lineWidth: 1.3)
            // Bubbles and pulses; labels are gathered and placed afterwards, above every bubble.
            var labels: [Label] = []
            var bubbles = RectIndex()
            for (i, node) in nodes.enumerated() {
                let p = screen(i)
                let r = max(Self.radius(node, degree: degree[i]) * min(max(camera.scale, 0.6), 1.6), 2)
                if p.x < -40 || p.y < -40 || p.x > size.width + 40 || p.y > size.height + 40 { continue }
                let dimmed = focus.map { !$0.contains(node.id) } ?? false
                let fill: Color = node.kind == .project ? Theme.Colors.text
                    : authors[node.id]?.slug.flatMap { tints[$0] } ?? Theme.color(for: .gray)
                if let pulse = pulses[node.id] {
                    let t = min(max(now.timeIntervalSince(pulse.start) / MemoryGraphModel.pulseDuration, 0), 1)
                    let tint = pulse.slug.flatMap { tints[$0] } ?? Theme.Colors.accentLight
                    if !reduceMotion {
                        let ring = r + 4 + CGFloat(t) * 22
                        context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                                       with: .color(tint.opacity(0.9 * (1 - t))), lineWidth: 2)
                    }
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2)),
                                 with: .color(tint.opacity(0.35 * (1 - t))))
                }
                let bubble = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: bubble), with: .color(fill.opacity(dimmed ? 0.28 : (node.kind == .project ? 0.92 : 1))))
                if selected == node.id {
                    context.stroke(Path(ellipseIn: bubble.insetBy(dx: -3.5, dy: -3.5)), with: .color(Theme.Colors.accentLight), lineWidth: 2)
                }
                bubbles.insert(bubble, owner: i)
                let labelled = node.kind == .project || showAllLabels || (focus?.contains(node.id) ?? false)
                if labelled, !dimmed || node.kind == .project {
                    let pointed = hovered == node.id || selected == node.id
                    let emphasis = pointed || node.kind == .project
                    let text = Text(node.title)
                        .font(.system(size: node.kind == .project ? 12 : 11, weight: emphasis ? .semibold : .regular))
                        .foregroundStyle(emphasis ? Theme.Colors.text : Theme.Colors.textMuted)
                    // The pointed note first, then hubs, then the most linked notes.
                    let priority = pointed ? Int.max : (node.kind == .project ? 1_000_000 : 0) + degree[i]
                    labels.append(Label(priority: priority, text: text, at: CGPoint(x: p.x, y: p.y + r + 9), owner: i, forced: emphasis))
                }
            }
            // A label never covers another label, and a note's label never covers another bubble. A soft halo in the
            // background color keeps the forced ones (hubs, the pointed note) readable over a thread or a bubble.
            var placed = RectIndex()
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Theme.Colors.background.opacity(0.95), radius: 2.5))
                for label in labels.sorted(by: { $0.priority > $1.priority }) {
                    let resolved = layer.resolve(label.text)
                    let measured = resolved.measure(in: CGSize(width: 240, height: 40))
                    let box = CGRect(x: label.at.x - measured.width / 2, y: label.at.y - measured.height / 2,
                                     width: measured.width, height: measured.height).insetBy(dx: -3, dy: -1)
                    if placed.intersects(box) { continue }
                    if !label.forced, bubbles.intersects(box, except: label.owner) { continue }
                    placed.insert(box)
                    layer.draw(resolved, at: label.at, anchor: .center)
                }
            }
        }
    }
}

/// A vault drawn the way Obsidian 1.13.7 draws it: node sizes from their links, lines one screen pixel wide from edge to
/// edge, a label under every node that fades in with the zoom, the hovered node in the accent with its lines, the rest
/// faded to a fifth. Everything is measured in Obsidian's units, the screen's pixels: `camera.unit` turns them into points.
private struct VaultCanvas: View {
    let graph: MemoryGraphModel

    var body: some View {
        let _ = graph.frame   // redraw on every animation frame
        let camera = graph.camera, layout = graph.layout, nodes = graph.graph.nodes
        let lines = graph.lineIndices, arrows = graph.arrowIndices
        let settings = graph.settings, colors = graph.groupColors, weights = graph.weights
        let hovered = graph.hovered, selected = graph.selected, center = graph.focusCenter
        let fades = nodes.map { graph.fade($0.id) }, lineFade = graph.lineFade
        // A node is drawn at its size times the square root of the zoom, as in Obsidian.
        let root = camera.scale.squareRoot(), unit = camera.unit
        let labelAlpha = ObsidianGraphSettings.labelAlpha(scale: Double(camera.scale), fade: settings.textFadeMultiplier)
        Canvas { context, size in
            guard layout.count == nodes.count, !nodes.isEmpty else { return }
            let sizes = nodes.map { CGFloat(ObsidianGraphSettings.nodeSize(weight: weights[$0.id] ?? 0, multiplier: settings.nodeSizeMultiplier)) }
            let points = (0..<nodes.count).map { camera.toScreen(layout.position(at: $0), in: size) }
            let radius = sizes.map { $0 * root * unit }
            // Lines first, from one node's edge to the other's.
            var faint = Path(), lit = Path()
            for (a, b) in lines {
                let p = points[a], q = points[b]
                let dx = q.x - p.x, dy = q.y - p.y, d = hypot(dx, dy)
                guard d > radius[a] + radius[b] else { continue }
                let from = CGPoint(x: p.x + dx / d * radius[a], y: p.y + dy / d * radius[a])
                let to = CGPoint(x: q.x - dx / d * radius[b], y: q.y - dy / d * radius[b])
                if let center, nodes[a].id == center || nodes[b].id == center { lit.move(to: from); lit.addLine(to: to) }
                else { faint.move(to: from); faint.addLine(to: to) }
            }
            let width = CGFloat(settings.lineSizeMultiplier) * unit
            context.stroke(faint, with: .color(Theme.Colors.vaultLine.opacity(lineFade)), lineWidth: width)
            context.stroke(lit, with: .color(Theme.Colors.vaultHighlight), lineWidth: width)
            if settings.showArrow {
                // Arrows fade in between zoom 0.3 and 0.8, at half the labels' color, as in Obsidian.
                let alpha = min(max(2 * (camera.scale - 0.3), 0), 1) * 0.5
                let length = 8 * CGFloat(settings.lineSizeMultiplier).squareRoot() * unit, half = length / 2
                var heads = Path()
                for (a, b) in arrows where alpha > 0 {
                    let p = points[a], q = points[b]
                    let dx = q.x - p.x, dy = q.y - p.y, d = hypot(dx, dy)
                    guard d > radius[a] + radius[b] + length else { continue }
                    let ux = dx / d, uy = dy / d
                    let tip = CGPoint(x: q.x - ux * radius[b], y: q.y - uy * radius[b])
                    let base = CGPoint(x: tip.x - ux * length, y: tip.y - uy * length)
                    heads.move(to: tip)
                    heads.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
                    heads.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
                    heads.closeSubpath()
                }
                context.fill(heads, with: .color(Theme.Colors.vaultText.opacity(alpha * lineFade)))
            }
            for (i, node) in nodes.enumerated() {
                let p = points[i], r = radius[i]
                if p.x < -r || p.y < -r || p.x > size.width + r || p.y > size.height + r { continue }
                let bubble = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                let fill = node.id == hovered ? Theme.Colors.vaultHighlight : Self.color(of: node, colors: colors)
                context.fill(Path(ellipseIn: bubble), with: .color(fill.opacity(fades[i])))
                if node.id == hovered || node.id == selected {
                    context.stroke(Path(ellipseIn: bubble.insetBy(dx: -2 * unit, dy: -2 * unit)), with: .color(Theme.Colors.vaultFocused), lineWidth: 2 * unit)
                }
            }
            // Labels above every node: no culling, as in Obsidian, where zooming out is what makes them go.
            for (i, node) in nodes.enumerated() {
                let pointed = node.id == hovered
                let alpha = pointed ? 1 : labelAlpha * fades[i]
                guard alpha > 0.01 else { continue }
                let p = points[i]
                if p.x < -300 || p.y < -80 || p.x > size.width + 300 || p.y > size.height + 20 { continue }
                // The hovered label is whole, a little lower, and never shrunk by a zoom out.
                let font = (14 + sizes[i] / 4) * (pointed ? max(root, 1) : root) * unit
                let y = p.y + (sizes[i] + 5) * root * unit + (pointed ? 15 * unit : 0)
                context.draw(Text(node.title).font(.system(size: font)).foregroundStyle(Theme.Colors.vaultText.opacity(alpha)),
                             at: CGPoint(x: p.x, y: y), anchor: .top)
            }
        }
    }

    /// A node's own color: its group's, else by kind, as Obsidian falls back.
    static func color(of node: MemoryGraph.Node, colors: [String: ObsidianGraphSettings.GroupColor]) -> Color {
        if let group = colors[node.id] { return Theme.color(group: group) }
        switch node.kind {
        case .attachment: return Theme.Colors.vaultAttachment
        case .unresolved: return Theme.Colors.vaultUnresolved
        case .note, .project: return Theme.Colors.vaultNode
        }
    }
}

/// Rectangles bucketed on a coarse grid, to test overlaps without comparing every pair on every frame.
struct RectIndex {
    private var cells: [Int64: [(rect: CGRect, owner: Int)]] = [:]
    private let cell: CGFloat = 64

    private func keys(_ rect: CGRect) -> [Int64] {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return [] }
        let x0 = Int((rect.minX / cell).rounded(.down)), x1 = Int((rect.maxX / cell).rounded(.down))
        let y0 = Int((rect.minY / cell).rounded(.down)), y1 = Int((rect.maxY / cell).rounded(.down))
        guard x1 - x0 < 64, y1 - y0 < 64 else { return [] }
        var keys: [Int64] = []
        for x in x0...x1 { for y in y0...y1 { keys.append(Int64(x) << 32 | Int64(UInt32(truncatingIfNeeded: y))) } }
        return keys
    }

    mutating func insert(_ rect: CGRect, owner: Int = -1) {
        for key in keys(rect) { cells[key, default: []].append((rect, owner)) }
    }

    /// Whether the rectangle overlaps one already inserted, ignoring the ones inserted for `owner`.
    func intersects(_ rect: CGRect, except owner: Int = Int.min) -> Bool {
        keys(rect).contains { key in cells[key]?.contains { $0.owner != owner && $0.rect.intersects(rect) } ?? false }
    }
}

/// The window a view lives in, kept weakly, for the scroll monitor (it must only act on its own window).
@MainActor final class WindowBox { weak var window: NSWindow? }

private struct WindowReader: NSViewRepresentable {
    let box: WindowBox
    func makeNSView(context: Context) -> ReaderView { let view = ReaderView(); view.box = box; return view }
    func updateNSView(_ view: ReaderView, context: Context) { view.box = box; box.window = view.window }
    final class ReaderView: NSView {
        var box: WindowBox?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); box?.window = window }
    }
}
