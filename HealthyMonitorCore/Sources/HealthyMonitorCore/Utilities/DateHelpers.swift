import Foundation

public extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    func hour(in calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: self)
    }

    func isInQuietHours(startHour: Int, endHour: Int) -> Bool {
        let h = hour()
        if startHour <= endHour {
            return h >= startHour && h < endHour
        } else {
            // Overnight quiet hours, e.g. 22:00–07:00
            return h >= startHour || h < endHour
        }
    }

    static func today(at hour: Int, minute: Int = 0) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }
}

public extension Calendar {
    func datesInRange(from start: Date, to end: Date) -> [Date] {
        var dates: [Date] = []
        var current = startOfDay(for: start)
        let endDay = startOfDay(for: end)
        while current <= endDay {
            dates.append(current)
            guard let next = date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}
