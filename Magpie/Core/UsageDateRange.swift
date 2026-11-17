import Foundation

struct UsageDateRange: Equatable {
    var startDate: Date
    var endDate: Date

    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }

    static func presetLastDays(_ days: Int, endingAt now: Date = Date(), timeZone: TimeZone = .current) -> UsageDateRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let end = cal.startOfDay(for: now)
        let offset = max(0, days - 1)
        let start = cal.date(byAdding: .day, value: -offset, to: end) ?? end
        return UsageDateRange(startDate: start, endDate: end)
    }

    static func currentMonth(endingAt now: Date = Date(), timeZone: TimeZone = .current) -> UsageDateRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
        let end = cal.startOfDay(for: now)
        return UsageDateRange(startDate: start, endDate: end)
    }

    func normalized(timeZone: TimeZone = .current) -> (start: Date, end: Date, wasSwapped: Bool) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let a = cal.startOfDay(for: startDate)
        let b = cal.startOfDay(for: endDate)
        if b < a {
            return (b, a, true)
        }
        return (a, b, false)
    }

    func apiPeriodString(timeZone: TimeZone = .current) -> String {
        let pair = normalized(timeZone: timeZone)
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(fmt.string(from: pair.start))..\(fmt.string(from: pair.end))"
    }

    func displayLabel(timeZone: TimeZone = .current) -> String {
        let pair = normalized(timeZone: timeZone)
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let s = fmt.string(from: pair.start)
        let e = fmt.string(from: pair.end)
        return s == e ? "\(s) 当天" : "\(s) 至 \(e)"
    }
}
