import Foundation
import Combine
import ClaudeUsageCore

class UsageStore: ObservableObject {
    @Published var data = UsageData()
    @Published var isLoading = false
}
