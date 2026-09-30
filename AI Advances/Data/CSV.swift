import Foundation

/// Minimal RFC 4180 CSV reader: handles quoted fields, escaped quotes and
/// newlines inside quotes (Epoch's notes columns contain all three).
enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }

        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\r": break
            case "\n":
                row.append(field); field = ""
                rows.append(row); row = []
            default: field.unicodeScalars.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Rows as dictionaries keyed by the header row.
    static func records(_ text: String) -> [[String: String]] {
        let all = rows(text)
        guard let header = all.first else { return [] }
        return all.dropFirst().compactMap { r in
            if r.count == 1 && r[0].isEmpty { return nil }
            var d: [String: String] = [:]
            for (i, key) in header.enumerated() where i < r.count { d[key] = r[i] }
            return d
        }
    }
}

enum Dates {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, s.count >= 10 else { return nil }
        return day.date(from: String(s.prefix(10)))
    }

    static func years(_ d: Date) -> Double {
        d.timeIntervalSinceReferenceDate / (365.25 * 86_400)
    }

    static func months(from a: Date, to b: Date) -> Double {
        b.timeIntervalSince(a) / (30.44 * 86_400)
    }
}
