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

    /// Parses the "yyyy-MM-dd" prefix of `s` as a UTC day. Reads the digits directly: a
    /// DateFormatter call costs about half a millisecond, and launch parses tens of thousands.
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let fast: Date?? = s.utf8.withContiguousStorageIfAvailable { b -> Date? in
            guard b.count >= 10 else { return nil }
            func digits(_ r: Range<Int>) -> Int? {
                var v = 0
                for i in r {
                    guard b[i] >= 48, b[i] <= 57 else { return nil }
                    v = v * 10 + Int(b[i] - 48)
                }
                return v
            }
            guard b[4] == 45, b[7] == 45, let y = digits(0..<4), let m = digits(5..<7), let d = digits(8..<10) else {
                return Date.distantFuture   // not ISO-shaped: let the formatter decide below
            }
            guard (1...12).contains(m), d >= 1, d <= daysIn(month: m, year: y) else { return nil }
            return Date(timeIntervalSince1970: Double(daysFromCivil(y, m, d)) * 86_400)
        }
        if let fast, fast != .distantFuture { return fast }
        guard s.count >= 10 else { return nil }
        return day.date(from: String(s.prefix(10)))
    }

    private static func daysIn(month m: Int, year y: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func years(_ d: Date) -> Double {
        d.timeIntervalSinceReferenceDate / (365.25 * 86_400)
    }

    static func months(from a: Date, to b: Date) -> Double {
        b.timeIntervalSince(a) / (30.44 * 86_400)
    }
}
