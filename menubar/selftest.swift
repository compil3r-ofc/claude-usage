// Compiled against UsageCore.swift — exercises the exact logic the menu renders.
import Foundation

var failures = 0
func check(_ label: String, _ got: String, _ want: String) {
    if got == want { print("  ok    \(label)  ->  \(got)") }
    else { print("  FAIL  \(label)  got [\(got)]  want [\(want)]"); failures += 1 }
}

print("bars (width 16):")
check("0%",   Fmt.bar(0),   String(repeating: "\u{2591}", count: 16))
check("4%",   Fmt.bar(4),   "\u{2593}" + String(repeating: "\u{2591}", count: 15))   // never empty
check("33%",  Fmt.bar(33),  String(repeating: "\u{2593}", count: 5)  + String(repeating: "\u{2591}", count: 11))
check("71%",  Fmt.bar(71),  String(repeating: "\u{2593}", count: 11) + String(repeating: "\u{2591}", count: 5))
check("100%", Fmt.bar(100), String(repeating: "\u{2593}", count: 16))
check("over", Fmt.bar(140), String(repeating: "\u{2593}", count: 16))               // clamped

print("durations:")
check("30s",  Fmt.duration(30),     "now")
check("12m",  Fmt.duration(12*60),  "12m")
check("4h30", Fmt.duration(16200),  "4h 30m")
check("2d4h", Fmt.duration(187200), "2d 4h")

print("loader:")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cu-test.json")
setenv("CLAUDE_USAGE_CACHE", tmp.path, 1)
let now = Date().timeIntervalSince1970

func write(_ s: String) { try! s.write(to: tmp, atomically: true, encoding: .utf8) }

write("""
{"updated_at":\(now),"plan":"Max",
 "five_hour":{"used_percentage":33,"resets_at":\(now+16200)},
 "seven_day":{"used_percentage":71,"resets_at":\(now+187200)},
 "fable":{"used_percentage":100,"resets_at":\(now+187200),"captured_at":\(now)}}
""")
var s = CacheLoader.load()
check("count",     "\(s.quotas.count)", "3")
check("order",     s.quotas.map(\.short).joined(separator: ","), "5h,wk,fable")
check("plan",      s.plan ?? "nil", "Max")
check("tightest",  s.tightest?.short ?? "nil", "fable")
check("red at 100","\(s.quotas[2].color == .systemRed)", "true")
check("green 33",  "\(s.quotas[0].color == .systemGreen)", "true")
check("captured",  "\(s.quotas[2].capturedAt != nil)", "true")

print("menu bar tracking:")
check("auto -> tightest", s.tracked(Tracked.auto)?.short ?? "nil", "fable")
check("pin 5h",           s.tracked("five_hour")?.short ?? "nil", "5h")
check("pin wk",           s.tracked("seven_day")?.short ?? "nil", "wk")
check("pin fable",        s.tracked("fable")?.short ?? "nil", "fable")
check("pin available",    "\(s.isPinnedUnavailable("fable"))", "false")
check("auto never flags", "\(s.isPinnedUnavailable(Tracked.auto))", "false")
check("selectable keys",  Tracked.keys.joined(separator: ","), "five_hour,seven_day,fable")

// A window with no reset time is KEPT, with no countdown. statusline.sh's fresh()
// must agree: it used to drop these, so the collector deleted entries the readers
// were still showing. If this check and that jq function ever diverge again, a
// synced Fable value silently disappears on the next render.
write("""
{"updated_at":\(now),"five_hour":{"used_percentage":33,"resets_at":\(now+16200)},
 "fable":{"used_percentage":100,"resets_at":0,"captured_at":\(now)}}
""")
let noReset = CacheLoader.load()
check("no reset time kept",  "\(noReset.quotas.count)", "2")
check("kept without countdown",
      "\(noReset.quotas.first(where: { $0.key == "fable" })?.resetsAt == nil)", "true")

print("staleness:")
// A number nobody is refreshing must not look like a live one.
write("""
{"updated_at":\(now),"five_hour":{"used_percentage":33,"resets_at":\(now+16200)}}
""")
check("fresh cache not stale", "\(CacheLoader.load().isStale)", "false")
write("""
{"updated_at":\(now - 400),"five_hour":{"used_percentage":33,"resets_at":\(now+16200)}}
""")
let old = CacheLoader.load()
check("old cache is stale",   "\(old.isStale)", "true")
check("stale warned in menu",
      "\(buildMenuRows(old, choice: Tracked.auto).contains { $0.text.contains("nothing is updating") })", "true")
write("""
{"updated_at":\(now),"five_hour":{"used_percentage":33,"resets_at":\(now+16200)}}
""")
check("no warning when fresh",
      "\(buildMenuRows(CacheLoader.load(), choice: Tracked.auto).contains { $0.text.contains("nothing is updating") })", "false")

// Pinning Fable when it was never synced must fall back, not blank the menu bar.
write("""
{"updated_at":\(now),
 "five_hour":{"used_percentage":33,"resets_at":\(now+16200)},
 "seven_day":{"used_percentage":71,"resets_at":\(now+187200)}}
""")
let noFable = CacheLoader.load()
check("fable gone",        "\(noFable.quotas.count)", "2")
check("pin missing falls back", noFable.tracked("fable")?.short ?? "nil", "wk")
check("flags unavailable", "\(noFable.isPinnedUnavailable("fable"))", "true")
check("pin 5h still works", noFable.tracked("five_hour")?.short ?? "nil", "5h")

// An expired window must be dropped, not shown as stale.
write("""
{"updated_at":\(now),"five_hour":{"used_percentage":50,"resets_at":\(now-10)}}
""")
s = CacheLoader.load()
check("expired dropped", "\(s.quotas.count)", "0")
check("expired msg",     s.error ?? "nil", "No rate-limit data recorded yet")

write("{ not json")
s = CacheLoader.load()
check("corrupt", s.error ?? "nil", "Cache is unreadable")

try? FileManager.default.removeItem(at: tmp)
s = CacheLoader.load()
check("missing", s.error ?? "nil", "No usage data yet")

// The dropdown as the user reads it. buildMenuRows is the single source of
// truth for the real menu, so this is not a mock.
write("""
{"updated_at":\(now),"plan":"Max",
 "five_hour":{"used_percentage":33,"resets_at":\(now+16200)},
 "seven_day":{"used_percentage":71,"resets_at":\(now+187200)},
 "fable":{"used_percentage":100,"resets_at":\(now+187200),"captured_at":\(now-480)}}
""")
let menuSnap = CacheLoader.load()

func render(_ choice: String) {
    for r in buildMenuRows(menuSnap, choice: choice) {
        if r.separator { print("   " + String(repeating: "\u{2500}", count: 48)); continue }
        var selectable = false
        if case .select = r.act { selectable = true }
        let mark = r.checked ? " \u{2713} " : (selectable ? "   " : "   ")
        print("  \(mark)\(r.text)")
    }
}

print("\n--- dropdown, default (auto) ---")
render(Tracked.auto)
print("\n--- dropdown, Weekly all models pinned ---")
render("seven_day")
print("")

print("menu structure:")
let rows = buildMenuRows(menuSnap, choice: Tracked.auto)
let picks = rows.filter { if case .select = $0.act { return true }; return false }
check("four choices offered", "\(picks.count)", "4")
check("choice order", picks.compactMap { r -> String? in
    if case .select(let k) = r.act { return k }; return nil
}.joined(separator: ","), "five_hour,seven_day,fable,auto")
check("heading precedes choices",
      "\(rows.firstIndex(where: { $0.text.hasPrefix("Show in menu bar") })! < rows.firstIndex(where: { if case .select = $0.act { return true }; return false })!)",
      "true")
check("exactly one checked", "\(picks.filter(\.checked).count)", "1")
check("auto checked by default",
      "\(picks.first(where: { $0.checked }).map { r -> Bool in if case .select(let k) = r.act { return k == Tracked.auto }; return false } ?? false)",
      "true")
let pinned = buildMenuRows(menuSnap, choice: "seven_day")
    .filter { if case .select = $0.act { return true }; return false }
check("pinning moves the check", "\(pinned.filter(\.checked).count)", "1")
check("pinned row is the right one",
      "\(pinned.first(where: { $0.checked }).map { r -> Bool in if case .select(let k) = r.act { return k == "seven_day" }; return false } ?? false)",
      "true")

try? FileManager.default.removeItem(at: tmp)

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
