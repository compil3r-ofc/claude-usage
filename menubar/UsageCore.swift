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
