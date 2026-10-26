import Foundation

/// An editable copy of the LaunchAgent schedule, limited to the shapes the Settings window
/// offers: daily, weekly on chosen days, or monthly on one day, always at one time.
struct ScheduleDraft: Sendable, Equatable {
    enum Frequency: String, CaseIterable, Identifiable, Sendable {
        case daily
        case weekly
        case monthly

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var frequency: Frequency = .daily
    var hour = 3
    var minute = 0
    /// launchd weekdays: 0 = Sunday ... 6 = Saturday
    var weekdays: Set<Int> = [0]
    var dayOfMonth = 1

    // Flags for the scheduled run. `--yes` is always passed because nobody is there to answer.
    var verbose = false
    var skipCasks = false
    var skipCleanup = false
    var skipSecurityScan = false
    /// Flags the editor doesn't know about, kept as they are
    var otherArguments: [String] = []

    /// False when the plist's schedule has a shape the editor can't show (e.g. several
    /// times a day). Saving replaces it with what the editor shows.
    private(set) var isRepresentable = true

    init() {}

    init(schedule: Schedule) {
        readIntervals(schedule.intervals)
        readArguments(schedule.scriptArguments)
    }

    // MARK: Reading the current schedule

    private mutating func readIntervals(_ intervals: [CalendarInterval]) {
        guard let first = intervals.first, let hour = first.hour else {
            isRepresentable = intervals.isEmpty
            return
        }
        self.hour = hour
        minute = first.minute ?? 0

        let sameTime = intervals.allSatisfy { $0.hour == hour && ($0.minute ?? 0) == minute && $0.month == nil }
        let weekdays = intervals.compactMap(\.weekday)
        if sameTime, intervals.count == 1, first.weekday == nil, first.day == nil {
            frequency = .daily
        } else if sameTime, weekdays.count == intervals.count, intervals.allSatisfy({ $0.day == nil }) {
            frequency = .weekly
            // launchd accepts 7 for Sunday as well as 0
            self.weekdays = Set(weekdays.map { $0 % 7 })
        } else if sameTime, intervals.count == 1, let day = first.day, first.weekday == nil {
            frequency = .monthly
            dayOfMonth = day
        } else {
            isRepresentable = false
        }
    }

    private mutating func readArguments(_ arguments: [String]) {
        for argument in arguments {
            switch argument {
            case "-y", "--yes": break
            case "-v", "--verbose": verbose = true
            case "-s", "--skip-casks": skipCasks = true
            case "-c", "--skip-cleanup": skipCleanup = true
            case "--skip-security-scan": skipSecurityScan = true
            default: otherArguments.append(argument)
            }
        }
    }

    // MARK: Writing

    var intervals: [CalendarInterval] {
        switch frequency {
        case .daily:
            [CalendarInterval(minute: minute, hour: hour)]
        case .weekly:
            weekdays.sorted().map { CalendarInterval(minute: minute, hour: hour, weekday: $0) }
        case .monthly:
            [CalendarInterval(minute: minute, hour: hour, day: dayOfMonth)]
        }
    }

    var scriptArguments: [String] {
        var arguments = ["--yes"]
        if verbose { arguments.append("--verbose") }
        if skipCasks { arguments.append("--skip-casks") }
        if skipCleanup { arguments.append("--skip-cleanup") }
        if skipSecurityScan { arguments.append("--skip-security-scan") }
        return arguments + otherArguments
    }

    var validationError: String? {
        switch frequency {
        case .weekly where weekdays.isEmpty: "Choose at least one day."
        // launchd skips months without the day, so 29-31 would silently miss some months
        case .monthly where !(1...28).contains(dayOfMonth): "Choose a day between 1 and 28."
        default: nil
        }
    }

    var schedule: Schedule { Schedule(intervals: intervals, scriptArguments: scriptArguments) }

    /// The plist with this schedule and these flags, every other key unchanged.
    /// `ProgramArguments` keeps everything before the first flag (`/bin/bash`, script path).
    func updatedPlist(_ data: Data) throws -> Data {
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let dictionaries = intervals.map(\.plistDictionary)
        plist["StartCalendarInterval"] = dictionaries.count == 1 ? dictionaries[0] : dictionaries

        let existing = plist["ProgramArguments"] as? [String] ?? []
        let program = existing.prefix { !$0.hasPrefix("-") }
        guard !program.isEmpty else { throw CocoaError(.propertyListReadCorrupt) }
        plist["ProgramArguments"] = Array(program) + scriptArguments

        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

extension CalendarInterval {
    var plistDictionary: [String: Int] {
        var dict: [String: Int] = [:]
        dict["Minute"] = minute
        dict["Hour"] = hour
        dict["Day"] = day
        dict["Weekday"] = weekday
        dict["Month"] = month
        return dict
    }
}
