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

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
