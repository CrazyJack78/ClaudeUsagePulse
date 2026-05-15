import Foundation
import Combine

class UsageStore: ObservableObject {
    @Published var data = UsageData()
    @Published var isLoading = false
}
