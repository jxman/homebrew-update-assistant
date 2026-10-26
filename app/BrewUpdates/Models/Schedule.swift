import Foundation

/// One `StartCalendarInterval` entry from the LaunchAgent plist. Missing keys mean "every".
struct CalendarInterval: Sendable, Equatable {
    var minute: Int?
    var hour: Int?
    var day: Int?
    /// launchd weekday: 0 or 7 = Sunday, 1 = Monday ... 6 = Saturday
    var weekday: Int?
    var month: Int?

    init(minute: Int? = nil, hour: Int? = nil, day: Int? = nil, weekday: Int? = nil, month: Int? = nil) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
    }

    init(plistDictionary dict: [String: Any]) {
        self.init(
            minute: dict["Minute"] as? Int,
            hour: dict["Hour"] as? Int,
            day: dict["Day"] as? Int,
            weekday: dict["Weekday"] as? Int,
            month: dict["Month"] as? Int
        )
    }

    /// Components for `Calendar.nextDate`. Foundation weekdays are 1 = Sunday ... 7 = Saturday.
    var dateComponents: DateComponents {
        DateComponents(
            month: month,
            day: day,
            hour: hour,
            minute: minute ?? 0,
            second: 0,
            weekday: weekday.map { $0 % 7 + 1 }
        )
    }

    var description: String { description(locale: .current) }

    /// Human-readable schedule, e.g. "Daily at 03:00" or "Sundays at 09:30"
    func description(locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale

        let time: String
        switch (hour, minute) {
        case let (hour?, minute):
            time = String(format: "%02d:%02d", hour, minute ?? 0)
        case let (nil, minute?):
            time = String(format: "every hour at :%02d", minute)
        case (nil, nil):
            time = "every minute"
        }

        var parts: [String] = []
        if let weekday {
            parts.append("\(calendar.weekdaySymbols[weekday % 7])s")
        }
        if let day {
            parts.append("day \(day)")
        }
        if let month {
            parts.append(calendar.monthSymbols[(month - 1) % 12])
        }
        if parts.isEmpty, hour != nil {
            parts.append("Daily")
        }
        return parts.isEmpty ? time.prefix(1).uppercased() + time.dropFirst() : "\(parts.joined(separator: ", ")) at \(time)"
    }
}

/// The LaunchAgent's schedule and the arguments it runs the script with.
struct Schedule: Sendable, Equatable {
    let intervals: [CalendarInterval]
    /// Script flags from ProgramArguments, e.g. `--yes --verbose`
    let scriptArguments: [String]

    var description: String { description(locale: .current) }

    func description(locale: Locale) -> String {
        intervals.isEmpty ? "Not scheduled" : intervals.map { $0.description(locale: locale) }.joined(separator: "; ")
    }

    func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        intervals
            .compactMap { calendar.nextDate(after: date, matching: $0.dateComponents, matchingPolicy: .nextTime) }
            .min()
    }

    /// Parses a LaunchAgent plist. `StartCalendarInterval` may be one dictionary or an array of them.
    static func parse(plistData: Data) throws -> Schedule {
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        let intervals: [CalendarInterval]
        switch plist["StartCalendarInterval"] {
        case let dict as [String: Any]:
            intervals = [CalendarInterval(plistDictionary: dict)]
        case let array as [[String: Any]]:
            intervals = array.map(CalendarInterval.init(plistDictionary:))
        default:
            intervals = []
        }

        // ProgramArguments is ["/bin/bash", "<script path>", flags...]; keep only the flags
        let arguments = plist["ProgramArguments"] as? [String] ?? []
        let flags = arguments.drop { !$0.hasPrefix("-") }
        return Schedule(intervals: intervals, scriptArguments: Array(flags))
    }
}
