import Foundation

enum SidebarSelection: String, CaseIterable, Identifiable {
    case dashboard
    case sources
    case competitors
    case history
    case reports
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "仪表盘"
        case .competitors:
            return "竞品"
        case .sources:
            return "数据源"
        case .history:
            return "情报历史"
        case .reports:
            return "Word 报告"
        case .logs:
            return "运行记录"
        case .settings:
            return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "gauge.with.dots.needle.bottom.50percent"
        case .competitors:
            return "building.2"
        case .sources:
            return "antenna.radiowaves.left.and.right"
        case .history:
            return "tray.full"
        case .reports:
            return "doc.richtext"
        case .logs:
            return "list.bullet.rectangle"
        case .settings:
            return "gearshape"
        }
    }
}
