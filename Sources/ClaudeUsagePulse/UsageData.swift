import Foundation

struct MetricData {
    var percentage: Double = 0
    var resetStr:   String = ""
    var resetAt:    Date?  = nil
    var creditInfo: (used: Double, limit: Double)? = nil
}

struct UsageData {
    var metrics:   [String: MetricData] = [:]
    var fetchedAt: Date    = Date()
    var error:     String? = nil

    subscript(key: String) -> MetricData {
        metrics[key] ?? MetricData()
    }
}
