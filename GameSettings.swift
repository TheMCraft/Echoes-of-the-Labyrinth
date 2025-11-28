import Foundation
import Combine

@MainActor
final class GameSettings: ObservableObject {
    // Shared singleton used across the app
    static let shared = GameSettings()

    @Published var isSoundEnabled: Bool
    @Published var isHapticsEnabled: Bool
    @Published var isDebugMode: Bool
    @Published var isInGame: Bool // neu: Track current app mode for music resume

    // Designated initializer kept internal; prefer using `shared`
    init(isSoundEnabled: Bool = true, isHapticsEnabled: Bool = true, isDebugMode: Bool? = false, isInGame: Bool = false) {
        self.isSoundEnabled = isSoundEnabled
        self.isHapticsEnabled = isHapticsEnabled
        #if DEBUG
        self.isDebugMode = isDebugMode ?? true
        #else
        self.isDebugMode = isDebugMode ?? false
        #endif
        self.isInGame = isInGame
    }
}
