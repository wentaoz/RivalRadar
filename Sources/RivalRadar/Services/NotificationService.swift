import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyNewItems(_ items: [IntelligenceItem], competitors: [Competitor]) {
        guard !items.isEmpty else { return }
        let top = items.max { $0.importance < $1.importance }
        let competitorName = top.flatMap { item in competitors.first(where: { $0.id == item.competitorID })?.name } ?? "竞品"

        let content = UNMutableNotificationContent()
        content.title = "竞品雷达发现 \(items.count) 条新情报"
        content.body = top.map { "\(competitorName)：\($0.title)" } ?? "打开竞品雷达查看详情"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "rivalradar-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
