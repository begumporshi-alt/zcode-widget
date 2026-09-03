import Foundation
import UserNotifications

/// Owns task reminder delivery through local notifications.
///
/// Two complementary paths:
/// 1. **Exact-time scheduling** — when a task is saved with a future due date
///    and reminders on, a UNCalendarNotificationTrigger is registered. The
///    system delivers it even if the widget is quit.
/// 2. **Scanner fallback** — a timer re-checks due tasks every 15 s. It covers
///    tasks that were saved already-overdue and tasks whose scheduled banner
///    could not be registered. Tasks whose delivery was already scheduled are
///    skipped (via `lastRemindedAt`) so no double banner appears.
final class TaskReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskReminderManager()

    static let reminderCategoryID = "TASK_REMINDER"
    static let markDoneActionID = "MARK_DONE"

    private static let scanInterval: TimeInterval = 15
    /// Overdue longer than this is not re-notified by the scanner — the
    /// scheduled notification already fired at the true due time, and stale
    /// overdue tasks must not banner on every app relaunch.
    private static let catchupWindow: TimeInterval = 3600
    /// A task saved (or edited) within this window whose due date is already
    /// in the past is treated as intentional and reminded immediately.
    private static let freshnessWindow: TimeInterval = 120

    /// Invoked when the user clicks a reminder banner (not the Mark Done
    /// action) — the app should show the panel on the Tasks tab.
    var onOpenTasks: (() -> Void)?

    private var scanTimer: Timer?
    private var started = false
    private var isAuthorized = false

    /// Registers the notification category/delegate and re-arms delivery for
    /// every stored future reminder. Call once after TaskStore.shared.load().
    func start() {
        guard !started else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let markDone = UNNotificationAction(identifier: Self.markDoneActionID,
                                            title: "Mark Done",
                                            options: [])
        let category = UNNotificationCategory(identifier: Self.reminderCategoryID,
                                              actions: [markDone],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])

        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
        }

        let store = TaskStore.shared
        for task in store.tasks where !task.completed && task.reminderEnabled {
            taskDidChange(task)
        }

        let timer = Timer(timeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        scanTimer = timer
        scanNow()
    }

    // MARK: Public API (called from the Tasks UI)

    /// Asks for notification permission the first time the user enables a
    /// reminder; reports the outcome so the UI can revert the toggle.
    func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        self.isAuthorized = granted
                        completion(granted)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    self.isAuthorized = true
                    completion(true)
                }
            default:
                DispatchQueue.main.async {
                    self.isAuthorized = false
                    completion(false)
                }
            }
        }
    }

    /// Call after a task is saved, completed, or edited. Cancels any pending
    /// delivery and re-schedules when the task still wants a future reminder.
    func taskDidChange(_ task: TaskItem) {
        let center = UNUserNotificationCenter.current()
        let identifier = Self.notificationID(for: task.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard !task.completed, task.reminderEnabled, let due = task.dueDate, due > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = "Due now"
        content.sound = .default
        content.categoryIdentifier = Self.reminderCategoryID
        content.userInfo = ["taskID": task.id]

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
        components.timeZone = TimeZone.current
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))

        // Delivery is arranged: tell the scanner to treat this due date as
        // handled, so it does not post a duplicate banner when the time comes.
        TaskStore.shared.markReminded(task.id, through: due)
    }

    /// Call after a task is deleted.
    func taskDeleted(_ id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID(for: id)])
    }

    /// One scanner pass over due tasks (also invoked by the UI right after a
    /// save so a just-saved overdue task reminds immediately).
    func scanNow() {
        let store = TaskStore.shared
        let now = Date()
        var handled: [(id: String, through: Date)] = []

        for task in store.openTasks where task.reminderEnabled {
            guard let due = task.dueDate, due <= now else { continue }
            // Already delivered or already scheduled for this due date?
            guard (task.lastRemindedAt ?? .distantPast) < due else { continue }

            let overdue = now.timeIntervalSince(due)
            let freshSave = now.timeIntervalSince(task.updatedAt) < Self.freshnessWindow
            guard overdue <= Self.catchupWindow || freshSave else { continue }

            if isAuthorized {
                postImmediate(task)
            }
            // Mark handled either way so a denied/unavailable center is not
            // polled every scan cycle.
            handled.append((task.id, now))
        }

        for entry in handled {
            store.markReminded(entry.id, through: entry.through)
        }
    }

    // MARK: Notification center delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the banner even while the widget panel is open.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let taskID = response.notification.request.content.userInfo["taskID"] as? String
        if response.actionIdentifier == Self.markDoneActionID, let id = taskID {
            DispatchQueue.main.async {
                if let task = TaskStore.shared.setCompleted(id, true) {
                    self.taskDidChange(task)
                }
            }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                self.onOpenTasks?()
            }
        }
        completionHandler()
    }

    // MARK: Helpers

    private func postImmediate(_ task: TaskItem) {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = "Overdue"
        content.sound = .default
        content.categoryIdentifier = Self.reminderCategoryID
        content.userInfo = ["taskID": task.id]

        let request = UNNotificationRequest(identifier: Self.notificationID(for: task.id),
                                            content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    static func notificationID(for taskID: String) -> String {
        "task-reminder-\(taskID)"
    }
}
