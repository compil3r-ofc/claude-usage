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
        // Colored dot + the percentage of the tracked window.
        let s = NSMutableAttributedString(
            string: "\u{25CF} ",
            attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: t.color])
        s.append(NSAttributedString(
            string: "\(Int(t.pct.rounded()))%",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                         .foregroundColor: NSColor.labelColor]))
        button.attributedTitle = s
        var lines = snap.quotas.map { q -> String in
            let mark = (q.key == t.key) ? "\u{25B8} " : "   "
            return "\(mark)\(q.label): \(Int(q.pct.rounded()))%"
        }
        if choice == Tracked.auto { lines.append("\nTracking: tightest window") }
        if snap.isPinnedUnavailable(choice) { lines.append("\nPinned window unavailable; showing tightest") }
        button.toolTip = lines.joined(separator: "\n")
    }

    private func row(_ text: String, color: NSColor? = nil, size: CGFloat = 12,
                     mono: Bool = false, selects: String? = nil, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let key = selects {
            item.action = #selector(selectWindow(_:))
            item.target = self
            item.representedObject = key
            item.state = checked ? .on : .off
        }
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                        : NSFont.systemFont(ofSize: size)
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color ?? NSColor.labelColor])
        return item
    }

    private func renderMenu(_ snap: Snapshot) {
        let menu = statusItem.menu!
        menu.removeAllItems()

        let header = snap.plan.map { "Claude usage · \($0) plan" } ?? "Claude usage"
        menu.addItem(row(header, color: .secondaryLabelColor, size: 11))
        menu.addItem(.separator())

        if let err = snap.error {
            menu.addItem(row(err, color: .secondaryLabelColor))
            menu.addItem(row("Send a message in Claude Code to fill it.",
                             color: .tertiaryLabelColor, size: 11))
        } else {
            for q in snap.quotas {
                let pct = String(format: "%3d%%", Int(q.pct.rounded()))
                let name = q.label.padding(toLength: 19, withPad: " ", startingAt: 0)
                menu.addItem(row("\(name)\(Fmt.bar(q.pct))  \(pct)",
                                 color: q.color, mono: true,
                                 selects: q.key, checked: choice == q.key))

                var notes: [String] = []
                if let r = q.resetsAt { notes.append("resets in \(Fmt.duration(r.timeIntervalSinceNow))") }
                if let c = q.capturedAt { notes.append("read \(Fmt.age(c))") }
                if !notes.isEmpty {
                    menu.addItem(row("   " + notes.joined(separator: " · "),
                                     color: .tertiaryLabelColor, size: 10, mono: true))
                }
            }
            menu.addItem(.separator())
            menu.addItem(row("Show in menu bar", color: .secondaryLabelColor, size: 11))
            menu.addItem(row("Tightest window (auto)",
                             selects: Tracked.auto, checked: choice == Tracked.auto))
            menu.addItem(row("   click a row above to pin one instead",
                             color: .tertiaryLabelColor, size: 10))
            if snap.isPinnedUnavailable(choice) {
                menu.addItem(row("   pinned window unavailable — showing tightest",
                                 color: .systemOrange, size: 10))
            }

            if !snap.quotas.contains(where: { $0.key == "fable" }) {
                menu.addItem(.separator())
                menu.addItem(row("Fable not recorded — run /usage-sync in Claude Code",
                                 color: .tertiaryLabelColor, size: 10))
            }
        }

        menu.addItem(.separator())
        if let u = snap.updatedAt {
            menu.addItem(row("updated \(Fmt.age(u))", color: .tertiaryLabelColor, size: 10))
        }
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func manualRefresh() { refresh() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
