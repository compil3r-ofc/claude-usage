// Menu bar UI + bootstrap. Model and formatting live in UsageCore.swift.
import AppKit

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    /// Which window the title tracks. Persisted, so it survives a relaunch.
    private var choice: String {
        get { UserDefaults.standard.string(forKey: Tracked.defaultsKey) ?? Tracked.auto }
        set { UserDefaults.standard.set(newValue, forKey: Tracked.defaultsKey); refresh() }
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        choice = key
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
        // The cache only changes when Claude Code renders its status line, and the
        // menu repaints on open anyway, so a slow poll is plenty and costs nothing.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // Repaint just before the menu opens so it is never stale on screen.
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let snap = CacheLoader.load()
        renderTitle(snap)
        renderMenu(snap)
    }

    private func renderTitle(_ snap: Snapshot) {
        guard let button = statusItem.button else { return }
        guard let t = snap.tracked(choice) else {
            button.attributedTitle = NSAttributedString(
                string: "Claude —",
                attributes: [.font: NSFont.menuBarFont(ofSize: 0),
                             .foregroundColor: NSColor.secondaryLabelColor])
            return
        }
        // Colored dot + the percentage of the tracked window. When the cache has
        // gone stale the dot is hollow and the number dimmed, so an out-of-date
        // reading never passes for a live one.
        let stale = snap.isStale
        let s = NSMutableAttributedString(
            string: stale ? "\u{25CB} " : "\u{25CF} ",
            attributes: [.font: NSFont.systemFont(ofSize: 9),
                         .foregroundColor: stale ? NSColor.secondaryLabelColor : t.color])
        s.append(NSAttributedString(
            string: "\(Int(t.pct.rounded()))%",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                         .foregroundColor: stale ? NSColor.secondaryLabelColor : NSColor.labelColor]))
        button.attributedTitle = s
        var lines = snap.quotas.map { q -> String in
            let mark = (q.key == t.key) ? "\u{25B8} " : "   "
            return "\(mark)\(q.label): \(Int(q.pct.rounded()))%"
        }
        if choice == Tracked.auto { lines.append("\nTracking: tightest window") }
        if snap.isStale, let u = snap.updatedAt {
            lines.append("\nStale: last updated \(Fmt.age(u))")
        }
        if snap.isPinnedUnavailable(choice) { lines.append("\nPinned window unavailable; showing tightest") }
        button.toolTip = lines.joined(separator: "\n")
    }

    /// Turns one MenuRow into an NSMenuItem. All layout decisions live in
    /// buildMenuRows; this only maps them onto AppKit.
    private func item(_ r: MenuRow) -> NSMenuItem {
        if r.separator { return .separator() }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        switch r.act {
        case .none: break
        case .select(let key):
            item.action = #selector(selectWindow(_:))
            item.target = self
            item.representedObject = key
            item.state = r.checked ? .on : .off
        case .refresh:
            item.action = #selector(manualRefresh)
            item.target = self
            item.keyEquivalent = "r"
        case .quit:
            item.action = #selector(NSApplication.terminate(_:))
            item.keyEquivalent = "q"
        }

        let color: NSColor
        switch r.tint {
        case .normal:      color = .labelColor
        case .secondary:   color = .secondaryLabelColor
        case .tertiary:    color = .tertiaryLabelColor
        case .warning:     color = .systemOrange
        case .quota(let p): color = p >= 90 ? .systemRed : (p >= 70 ? .systemOrange : .systemGreen)
        }
        let font = r.mono ? NSFont.monospacedSystemFont(ofSize: r.size, weight: .regular)
                          : NSFont.systemFont(ofSize: r.size)
        item.attributedTitle = NSAttributedString(
            string: r.text, attributes: [.font: font, .foregroundColor: color])
        return item
    }

    private func renderMenu(_ snap: Snapshot) {
        let menu = statusItem.menu!
        menu.removeAllItems()
        for r in buildMenuRows(snap, choice: choice) { menu.addItem(item(r)) }
    }

    @objc private func manualRefresh() { refresh() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
