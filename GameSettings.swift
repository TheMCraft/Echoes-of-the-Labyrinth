import Foundation
import Combine

final class GameSettings: ObservableObject {
    @Published var isSoundEnabled: Bool
    @Published var isHapticsEnabled: Bool

    init(isSoundEnabled: Bool = true, isHapticsEnabled: Bool = true) {
        self.isSoundEnabled = isSoundEnabled
        self.isHapticsEnabled = isHapticsEnabled
    }
}
