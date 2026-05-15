import Foundation

struct UsageData {
    var sessionPercentage: Double = 0
    var weeklyPercentage: Double = 0
    var sessionResetAt: Date? = nil
    var weeklyResetAt: Date? = nil
    var fetchedAt: Date = Date()
    var error: String? = nil
}
