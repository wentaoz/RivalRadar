import Foundation

enum TimeFilterPreset: String, CaseIterable, Identifiable {
    case all
    case today
    case last7Days
    case last30Days
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .today:
            return "今天"
        case .last7Days:
            return "最近 7 天"
        case .last30Days:
            return "最近 30 天"
        case .custom:
            return "自定义"
        }
    }

    func contains(
        _ date: Date,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return date >= start && date < end
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return date >= start && date <= now
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return date >= start && date <= now
        case .custom:
            let lower = min(startDate, endDate)
            let upper = max(startDate, endDate)
            let start = calendar.startOfDay(for: lower)
            let endStart = calendar.startOfDay(for: upper)
            let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? upper
            return date >= start && date < end
        }
    }
}
