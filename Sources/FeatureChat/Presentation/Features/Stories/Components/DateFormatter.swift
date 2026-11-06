import Foundation

func formatDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    let secondsAgo = now.timeIntervalSince(date)

    // If viewed within the last 60 seconds → "Just now"
    if secondsAgo < 60 {
        return "Just now"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.timeStyle = .short
    formatter.dateStyle = .none

    if calendar.isDateInToday(date) {
        return "Today, \(formatter.string(from: date))"
    } else if calendar.isDateInYesterday(date) {
        return "Yesterday, \(formatter.string(from: date))"
    } else {
        formatter.dateStyle = .medium
        return "\(formatter.string(from: date))"
    }
}
