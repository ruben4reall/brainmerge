import AppKit
import SwiftUI
import BrainmergeCore

/// The memory as a living graph, like Obsidian's graph view: every note is a bubble in the color of the account that
/// saved it, links are threads, each project is a hub. Notes pulse when they are written and again when an account
/// saves them. Hover lights a note and its neighbors; click shows it; double-click opens it in your notes app.
/// Drag the background to move around, drag a bubble to pull it, pinch or use the mouse wheel to zoom.
struct MemoryGraphView: View {
    @Bindable var graph: MemoryGraphModel
    let app: AppModel
    @State private var dragTarget: String?
    @State private var panOrigin: CGPoint?
    @State private var magnifyBase: GraphCamera?
    @State private var monitor: Any?
    /// Set by the capture script: the pointer may rest over the window by chance, and a screenshot should show the graph unlit.
    static let capturing = ProcessInfo.processInfo.environment["BRAINMERGE_CAPTURE"] != nil

    var tints: [String: Color] {
        Dictionary(app.accounts.map { ($0.id, Theme.color(for: $0.identity.tint)) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let _ = graph.frame   // redraw on every animation frame
        GeometryReader { geo in
            ZStack {
                canvas(size: geo.size)
                if graph.graph.nodes.filter({ $0.kind == .note }).isEmpty { emptyState }
                VStack {
                    HStack(alignment: .top) { legend; Spacer(); if let id = graph.selected { inspector(id).transition(.opacity) } }
                    Spacer()
                    HStack(alignment: .bottom) { status; Spacer(); controls(size: geo.size) }
                }
                .padding(12)
            }
            .onAppear { graph.viewSize = geo.size; installScrollMonitor() }
            .onChange(of: geo.size) { _, size in graph.viewSize = size }
            .onDisappear { removeScrollMonitor() }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous).strokeBorder(Theme.Colors.surfaceLine, lineWidth: 1))
        .task(id: app.selectedBrain?.root.path) {
            await graph.refresh(root: app.selectedBrain?.root)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                await graph.refresh(root: app.selectedBrain?.root)
            }
        }
    }

    // MARK: Drawing

    func radius(_ node: MemoryGraph.Node, degree: Int) -> CGFloat {
        let d = CGFloat(degree).squareRoot()
        return node.kind == .project ? min(7 + d * 1.5, 17) : min(3.5 + d * 1.3, 12)
    }

    func color(_ node: MemoryGraph.Node, tints: [String: Color]) -> Color {
        if node.kind == .project { return Theme.Colors.text }
        if let slug = graph.authors[node.id]?.slug, let tint = tints[slug] { return tint }
        return Theme.color(for: .gray)
    }

    /// The notes that stay lit: the hovered or selected note and its neighbors, or one account's notes.
    var focus: Set<String>? {
        if let id = graph.hovered ?? graph.selected { return graph.neighbors(of: id).union([id]) }
        if let slug = graph.highlightedAccount {
            let ids = graph.graph.nodes.filter { graph.authors[$0.id]?.slug == slug }.map(\.id)
            return Set(ids).union(ids.flatMap { graph.neighbors(of: $0).filter { $0.hasPrefix("project:") } })
        }
        return nil
    }

    func canvas(size: CGSize) -> some View {
        let tints = self.tints
        let focus = self.focus
        let camera = graph.camera
        let layout = graph.layout
        let nodes = graph.graph.nodes
        let now = Date()
        let showAllLabels = camera.scale >= 1.25 || nodes.count <= 40
        return Canvas { context, size in
            guard layout.count == nodes.count, !nodes.isEmpty else { return }
            let degree = layout.degree
            func screen(_ i: Int) -> CGPoint { camera.toScreen(layout.position(at: i), in: size) }
            // Threads first, under the bubbles.
            var faint = Path(), lit = Path()
            for (a, b) in layout.linkIndices {
                let lit_ = focus.map { $0.contains(nodes[a].id) && $0.contains(nodes[b].id) } ?? false
                if lit_ { lit.move(to: screen(a)); lit.addLine(to: screen(b)) } else { faint.move(to: screen(a)); faint.addLine(to: screen(b)) }
            }
            context.stroke(faint, with: .color(Theme.Colors.graphLink.opacity(focus == nil ? 1 : 0.35)), lineWidth: 1)
            context.stroke(lit, with: .color(Theme.Colors.graphLinkLit), lineWidth: 1.3)
            // Bubbles and pulses; labels are gathered and placed afterwards, above every bubble.
            var labels: [(priority: Int, text: Text, at: CGPoint)] = []
            for (i, node) in nodes.enumerated() {
                let p = screen(i)
                let r = max(radius(node, degree: degree[i]) * min(max(camera.scale, 0.6), 1.6), 2)
                if p.x < -40 || p.y < -40 || p.x > size.width + 40 || p.y > size.height + 40 { continue }
                let dimmed = focus.map { !$0.contains(node.id) } ?? false
                let fill = color(node, tints: tints)
                if let pulse = graph.pulses[node.id] {
                    let t = min(max(now.timeIntervalSince(pulse.start) / MemoryGraphModel.pulseDuration, 0), 1)
                    let ring = r + 4 + CGFloat(t) * 22
                    let tint = pulse.slug.flatMap { tints[$0] } ?? Theme.Colors.accentLight
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                                   with: .color(tint.opacity(0.9 * (1 - t))), lineWidth: 2)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2)),
                                 with: .color(tint.opacity(0.35 * (1 - t))))
                }
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                context.fill(circle, with: .color(fill.opacity(dimmed ? 0.18 : (node.kind == .project ? 0.92 : 1))))
                if graph.selected == node.id {
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - r - 3.5, y: p.y - r - 3.5, width: (r + 3.5) * 2, height: (r + 3.5) * 2)),
                                   with: .color(Theme.Colors.accentLight), lineWidth: 2)
                }
                let labelled = node.kind == .project || showAllLabels || (focus?.contains(node.id) ?? false)
                if labelled, !dimmed || node.kind == .project {
                    let pointed = graph.hovered == node.id || graph.selected == node.id
                    let emphasis = pointed || node.kind == .project
                    let text = Text(node.title)
                        .font(.system(size: node.kind == .project ? 12 : 11, weight: emphasis ? .semibold : .regular))
                        .foregroundStyle(emphasis ? Theme.Colors.text : Theme.Colors.textMuted)
                    // The pointed note first, then hubs, then the most linked notes: a label that would cover another is left out.
                    let priority = pointed ? Int.max : (node.kind == .project ? 1_000_000 : 0) + degree[i]
                    labels.append((priority, text, CGPoint(x: p.x, y: p.y + r + 9)))
                }
            }
            var placed: [CGRect] = []
            for label in labels.sorted(by: { $0.priority > $1.priority }) {
                let resolved = context.resolve(label.text)
                let size = resolved.measure(in: CGSize(width: 240, height: 40))
                let box = CGRect(x: label.at.x - size.width / 2, y: label.at.y - size.height / 2, width: size.width, height: size.height).insetBy(dx: -3, dy: -1)
                if placed.contains(where: { $0.intersects(box) }) { continue }
                placed.append(box)
                context.draw(resolved, at: label.at, anchor: .center)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(size: size))
        .simultaneousGesture(magnifyGesture(size: size))
        .onTapGesture(count: 2, coordinateSpace: .local) { point in if let id = note(at: point, size: size) { open(id) } }
        .onTapGesture(count: 1, coordinateSpace: .local) { point in withAnimation(.easeOut(duration: 0.15)) { graph.selected = note(at: point, size: size) } }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                graph.pointer = point
                if !Self.capturing { graph.hovered = note(at: point, size: size) }
            case .ended: graph.pointer = nil; graph.hovered = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Memory graph: \(nodes.filter { $0.kind == .note }.count) notes and \(graph.graph.edges.count) links. The timeline lists the same notes.")
    }

    func note(at point: CGPoint, size: CGSize) -> String? {
        graph.layout.nearest(to: graph.camera.toWorld(point, in: size), within: max(14 / graph.camera.scale, 8))
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
                    graph.camera.center = CGPoint(x: origin.x - value.translation.width / graph.camera.scale,
                                                  y: origin.y - value.translation.height / graph.camera.scale)
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

    /// Trackpad scrolling moves around, a mouse wheel zooms around the pointer, like most maps.
    func installScrollMonitor() {
        guard monitor == nil else { return }
        let graph = self.graph
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let precise = event.hasPreciseScrollingDeltas, dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let pointer = graph.pointer else { return false }
                graph.fitted = true
                if precise {
                    graph.camera.pan(by: CGSize(width: -dx, height: -dy))
                } else {
                    graph.camera.zoom(by: exp(dy * 0.08), around: pointer, in: graph.viewSize)
                }
                return true
            }
            return handled ? nil : event
        }
    }

    func removeScrollMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }

    // MARK: Opening

    var target: NotesTarget { NotesApps.target(for: app.notesApp, installed: NotesApps.installed()) }

    func open(_ id: String) {
        guard let url = graph.fileURL(id) else { return }
        NotesApps.open(url, with: target)
    }

    func openLabel(for id: String) -> String {
        if id.hasPrefix("project:") { return target == .folder ? "Open folder" : target.label }
        switch target {
        case .folder: return "Open note"
        default: return target.label
        }
    }

    // MARK: Overlays

    var emptyState: some View {
        Text("No notes yet. Open an account and work on a project: what Claude Code remembers appears here as it happens.")
            .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            .frame(maxWidth: 380)
    }

    /// The accounts whose notes are in view, in their colors, with how many notes each saved last. Hovering one lights its notes.
    var legend: some View {
        let present = Set(graph.graph.nodes.filter { $0.kind == .note }.map(\.id))
        let slugs = Dictionary(grouping: graph.authors.filter { present.contains($0.key) }.values.compactMap(\.slug), by: { $0 }).mapValues(\.count)
        let ordered = app.accounts.filter { slugs[$0.id] != nil }.sorted { (slugs[$0.id] ?? 0) > (slugs[$1.id] ?? 0) }
        return HStack(spacing: 6) {
            ForEach(ordered) { account in
                HStack(spacing: 6) {
                    Circle().fill(Theme.color(for: account.identity.tint)).frame(width: 8, height: 8)
                    Text("\(account.identity.name) · \(slugs[account.id] ?? 0)").font(Theme.Fonts.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .glassEffect(.regular, in: Capsule())
                .onHover { inside in graph.highlightedAccount = inside ? account.id : nil }
                .accessibilityLabel("\(account.identity.name): \(slugs[account.id] ?? 0) notes")
            }
        }
    }

    var status: some View {
        let notes = graph.graph.nodes.filter { $0.kind == .note }.count
        let recent = graph.lastChange.map { Date().timeIntervalSince($0) < 4 } ?? false
        return HStack(spacing: 6) {
            Circle().fill(recent ? Theme.Colors.accentLight : Theme.Colors.sage).frame(width: 6, height: 6)
            Text(recent ? "Changed just now" : "Live").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
            let projects = graph.graph.nodes.filter { $0.kind == .project }.count
            Text("· \(notes) note\(notes == 1 ? "" : "s") · \(projects) project\(projects == 1 ? "" : "s") · \(graph.graph.edges.count) link\(graph.graph.edges.count == 1 ? "" : "s")\(graph.truncated ? " · the most recent 2,000" : "")")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassEffect(.regular, in: Capsule())
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

    func inspector(_ id: String) -> some View {
        let node = graph.graph.node(id)
        let author = graph.authors[id]
        let account = author?.slug.flatMap { slug in app.accounts.first { $0.id == slug } }
        let notes = node?.kind == .project ? graph.neighbors(of: id).filter { !$0.hasPrefix("project:") }.count : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(node?.title ?? id).font(Theme.Fonts.cardName).lineLimit(2)
                Spacer(minLength: 8)
                Button { graph.selected = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Colors.textFaint) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            if node?.kind == .project {
                Text("Project · \(notes) note\(notes == 1 ? "" : "s")").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
            } else {
                Text(id).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Circle().fill(account.map { Theme.color(for: $0.identity.tint) } ?? Theme.color(for: .gray)).frame(width: 7, height: 7)
                    Text(author.map { "Saved by \(account?.identity.name ?? $0.name) · \(MemoryView.relative($0.date))" } ?? "Not saved yet")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
                let preview = graph.preview(id)
                if !preview.isEmpty {
                    Text(preview).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                Button(openLabel(for: id)) { open(id) }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.small)
                Button("Show in Finder") { if let url = graph.fileURL(id) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    .buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
