// ClaudeUsage — a macOS menu bar readout of remaining Claude plan quota.
//
// Reads the same ~/.claude/usage-cache.json that the `claude-usage` CLI reads.
// The cache is kept current by the Claude Code status line collector, so this
// app makes no network calls and holds no credentials.

import AppKit  // NSColor only

// MARK: - Model

struct Quota {
    let key: String
    let label: String
    let short: String
    let pct: Double
    let resetsAt: Date?
    let capturedAt: Date?

    /// Short label shown beside the percentage in the menu bar. A bare number is
    /// ambiguous: with "tightest" tracking it silently switches between windows,
    /// so the same menu bar can read 44% (5-hour) and then 39% (weekly) and look
    /// like it is wrong rather than like it changed which window it is showing.
    var badge: String { short }

    var color: NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 70 { return .systemOrange }
        return .systemGreen
    }
}

struct Snapshot {
    var quotas: [Quota] = []
    var plan: String?
    var updatedAt: Date?
    var error: String?

    /// The window closest to its ceiling — the one that will bite first.
    var tightest: Quota? { quotas.max(by: { $0.pct < $1.pct }) }
}

// MARK: - Which window the menu bar title tracks

enum Tracked {
    static let defaultsKey = "trackedWindow"
    static let auto = "auto"
    /// Selectable keys, in the order the menu lists them.
    static let keys = ["five_hour", "seven_day", "fable"]
}

extension Snapshot {
    /// The window the menu bar title shows.
    ///
    /// `auto` follows whichever window is tightest. A specific key pins that one,
    /// but falls back to the tightest when that window is not in the cache — Fable
    /// is often unrecorded, and an empty menu bar would be worse than a real number.
    func tracked(_ choice: String) -> Quota? {
        if choice == Tracked.auto { return tightest }
        return quotas.first { $0.key == choice } ?? tightest
    }

    /// The collector writes on every status line render, and at least once a
    /// minute while any session is open. Older than this and nothing is feeding
    /// the cache, so the numbers on screen have drifted from reality. A stale
    /// number looks exactly like a fresh one, which is worse than showing none.
    static let staleAfter: TimeInterval = 300

    var isStale: Bool {
        guard let u = updatedAt else { return true }
        return Date().timeIntervalSince(u) > Snapshot.staleAfter
    }

    /// True when the pinned window is unavailable, so the title is showing a stand-in.
    func isPinnedUnavailable(_ choice: String) -> Bool {
        choice != Tracked.auto && !quotas.contains { $0.key == choice }
    }
}

// MARK: - Loading

enum CacheLoader {
    static var url: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_USAGE_CACHE"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/usage-cache.json")
    }

    // Order matters: it is the order shown in the menu.
    private static let spec: [(String, String, String)] = [
        ("five_hour", "5-hour", "5h"),
        ("seven_day", "Weekly, all models", "wk"),
        ("fable",     "Weekly, Fable", "fable"),
    ]

    static func load() -> Snapshot {
        var snap = Snapshot()
        guard let data = try? Data(contentsOf: url) else {
            snap.error = "No usage data yet"
            return snap
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            snap.error = "Cache is unreadable"
            return snap
        }

        snap.plan = root["plan"] as? String
        if let u = root["updated_at"] as? Double { snap.updatedAt = Date(timeIntervalSince1970: u) }

        let now = Date()
        for (key, label, short) in spec {
            guard let w = root[key] as? [String: Any],
                  let pct = (w["used_percentage"] as? NSNumber)?.doubleValue else { continue }
            var resets: Date?
            if let r = (w["resets_at"] as? NSNumber)?.doubleValue, r > 0 {
                let d = Date(timeIntervalSince1970: r)
                if d > now { resets = d } else { continue }   // window already rolled over
            }
            var captured: Date?
            if let c = (w["captured_at"] as? NSNumber)?.doubleValue { captured = Date(timeIntervalSince1970: c) }
            snap.quotas.append(Quota(key: key, label: label, short: short,
                                     pct: pct, resetsAt: resets, capturedAt: captured))
        }
        if snap.quotas.isEmpty && snap.error == nil { snap.error = "No rate-limit data recorded yet" }
        return snap
    }
}

// MARK: - Formatting

enum Fmt {
    static func bar(_ pct: Double, width: Int = 16) -> String {
        var filled = Int((pct / 100.0 * Double(width)).rounded(.down))
        filled = max(0, min(width, filled))
        if filled == 0 && pct > 0 { filled = 1 }
        return String(repeating: "\u{2593}", count: filled)
             + String(repeating: "\u{2591}", count: width - filled)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "now" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func age(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        return s < 60 ? "just now" : "\(duration(s)) ago"
    }
}


// MARK: - Menu contents

/// One line of the dropdown, described without AppKit so it can be tested and
/// printed. `main.swift` turns these into NSMenuItems and does nothing else,
/// so what the tests check is what the menu shows.
struct MenuRow {
    enum Tint { case normal, secondary, tertiary, warning, quota(Double) }
    enum Act { case none, select(String), refresh, quit }

    var text: String
    var tint: Tint = .normal
    var size: CGFloat = 12
    var mono: Bool = false
    var act: Act = .none
    var checked: Bool = false
    var separator: Bool = false

    static let sep = MenuRow(text: "", separator: true)
}

/// Builds the whole dropdown.
///
/// The three windows and "Tightest of the three" are deliberately laid out as
/// four peers under one heading. An earlier version put the heading below the
/// windows with only the auto option beneath it, which read as though auto were
/// the only choice and the windows above were a static readout.
func buildMenuRows(_ snap: Snapshot, choice: String) -> [MenuRow] {
    var rows: [MenuRow] = []

    rows.append(MenuRow(text: snap.plan.map { "Claude usage · \($0) plan" } ?? "Claude usage",
                        tint: .secondary, size: 11))
    rows.append(.sep)

    if let err = snap.error {
        rows.append(MenuRow(text: err, tint: .secondary))
        rows.append(MenuRow(text: "Send a message in Claude Code to fill it.",
                            tint: .tertiary, size: 11))
    } else {
        rows.append(MenuRow(text: "Show in menu bar  ·  pick one", tint: .secondary, size: 11))

        for q in snap.quotas {
            let pct = String(format: "%3d%%", Int(q.pct.rounded()))
            let name = q.label.padding(toLength: 19, withPad: " ", startingAt: 0)
            rows.append(MenuRow(text: "\(name)\(Fmt.bar(q.pct))  \(pct)",
                                tint: .quota(q.pct), mono: true,
                                act: .select(q.key), checked: choice == q.key))

            var notes: [String] = []
            if let r = q.resetsAt { notes.append("resets in \(Fmt.duration(r.timeIntervalSinceNow))") }
            if let c = q.capturedAt { notes.append("read \(Fmt.age(c))") }
            if !notes.isEmpty {
                rows.append(MenuRow(text: "   " + notes.joined(separator: " · "),
                                    tint: .tertiary, size: 10, mono: true))
            }
        }

        rows.append(MenuRow(text: "Tightest of the three  (auto)",
                            act: .select(Tracked.auto), checked: choice == Tracked.auto))
        rows.append(MenuRow(text: "   follows whichever is closest to its limit",
                            tint: .tertiary, size: 10, mono: true))

        if snap.isPinnedUnavailable(choice) {
            rows.append(MenuRow(text: "   pinned window unavailable — showing tightest",
                                tint: .warning, size: 10, mono: true))
        }
        if !snap.quotas.contains(where: { $0.key == "fable" }) {
            rows.append(.sep)
            rows.append(MenuRow(text: "Fable not recorded — run /usage-sync in Claude Code",
                                tint: .tertiary, size: 10))
        }
    }

    rows.append(.sep)
    if let u = snap.updatedAt {
        rows.append(MenuRow(text: "updated \(Fmt.age(u))",
                            tint: snap.isStale ? .warning : .tertiary, size: 10))
    }
    if snap.isStale && snap.error == nil {
        rows.append(MenuRow(text: "nothing is updating the cache \u{2014} open a Claude Code session",
                            tint: .warning, size: 10))
    }
    rows.append(MenuRow(text: "Refresh Now", act: .refresh))
    rows.append(MenuRow(text: "Quit", act: .quit))
    return rows
}
