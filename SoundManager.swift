//
//  SoundManager.swift
//  EotL
//
//  Created by Michael Hammer on 07/11/2025.
//

import Foundation
import AVFoundation
import UIKit // Für NSDataAsset

final class SoundManager {
    @MainActor static let shared = SoundManager()

    private var player: AVAudioPlayer?
    private var audioSessionConfigured = false

    private init() { }

    // Einmal aufrufen (z. B. in LobbyView.onAppear oder App init)
    func setupAudioSession(usePlaybackCategory: Bool = false) {
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true

        do {
            // .ambient = Spiel-SFX mischen sich mit System / Musik; .playback ignoriert Stumm-Schalter
            let category: AVAudioSession.Category = usePlaybackCategory ? .playback : .ambient
            try AVAudioSession.sharedInstance().setCategory(category,
                                                            mode: .default,
                                                            options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession Fehler:", error)
        }
    }

    // MARK: - Interner Loader
    private func makePlayer(name: String, ext: String) -> AVAudioPlayer? {
        // 1. Direkt als Datei im Bundle (falls später ausgelagerte Ressourcen)
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                return p
            } catch {
                print("AVAudioPlayer Fehler (URL):", error)
            }
        }
        // 2. Fallback: Data Asset (wie bei level-selected.mp3.dataset)
        //    Probiere sowohl den Basisnamen als auch den Namen inkl. Extension,
        //    da der Asset-Name je nach Erstellung "level-selected" oder "level-selected.mp3" sein kann.
        let dataAssetCandidates = [name, "\(name).\(ext)"]
        for candidate in dataAssetCandidates {
            if let dataAsset = NSDataAsset(name: candidate) {
                do {
                    let p = try AVAudioPlayer(data: dataAsset.data)
                    return p
                } catch {
                    print("AVAudioPlayer Fehler (DataAsset \(candidate)):", error)
                }
            }
        }
        print("Sound nicht gefunden (weder Datei noch DataAsset):", name, ext)
        return nil
    }

    // Normaler Playback
    @MainActor func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        // Wenn Sound deaktiviert → Abbruch
        guard GameSettings.shared.isSoundEnabled else { return }
        guard let p = makePlayer(name: name, ext: ext) else { return }
        player = p
        player?.volume = volume
        player?.prepareToPlay()
        let played = player?.play() ?? false
        if played {
            print("[SoundManager] Spiele Sound: \(name).\(ext) (duration=\(player?.duration ?? 0))")
        } else {
            print("[SoundManager] Start fehlgeschlagen für: \(name).\(ext)")
        }
    }

    // Sofortiges Stoppen (falls benötigt)
    func stop() {
        player?.stop()
    }

    // Beispiel für Loop-Sound (Hintergrund, etc.)
    @MainActor func playLoop(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        guard GameSettings.shared.isSoundEnabled else { return }
        guard let p = makePlayer(name: name, ext: ext) else { return }
        player = p
        player?.numberOfLoops = -1
        player?.volume = volume
        player?.prepareToPlay()
        player?.play()
    }
}
