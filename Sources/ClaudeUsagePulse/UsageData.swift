import Foundation

struct UsageData {
    var sessionPercentage: Double = 0
    var weeklyPercentage:  Double = 0
    var sonnetPercentage:  Double = 0
    var designPercentage:  Double = 0
    var creditsPercentage: Double = 0
    var creditsUsedEUR:    Double = 0
    var creditsLimitEUR:   Double = 0
    var sessionResetStr:   String = ""
    var weeklyResetStr:    String = ""
    var sonnetResetStr:    String = ""
    var designResetStr:    String = ""
    var sessionResetAt:    Date?  = nil
    var weeklyResetAt:     Date?  = nil
    var sonnetResetAt:     Date?  = nil
    var designResetAt:     Date?  = nil
    var fetchedAt:         Date   = Date()
    var error:             String? = nil
}
