import Foundation

/// Compares release versions such as "v1.10" and "1.2.1".
enum AppVersion {
    static func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: .whitespaces)
            .drop { $0 == "v" || $0 == "V" }
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// True when `candidate` is a later version than `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
