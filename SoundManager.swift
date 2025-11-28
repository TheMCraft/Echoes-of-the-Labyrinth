//
//  SoundManager.swift
//  EotL
//
//  Created by Michael Hammer on 07/11/2025.
//

import Foundation
import AVFoundation
import UIKit
import Combine

final class SoundManager {
    @MainActor static let shared = SoundManager()

    // Dedizierte Player für Hintergrundloop und SFX
    private var loopPlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?

    private var audioSessionConfigured = false
    private var cancellables: Set<AnyCancellable> = []
    private var settingsObserved = false

    // Merke aktuellen Loop inkl. Ziel-Lautstärke
    private var currentLoopInfo: (name: String, ext: String, targetVolume: Float)?

    private init() { }

    // Einmal aufrufen (z. B. in LobbyView.onAppear oder App init)
    @MainActor
    func setupAudioSession(usePlaybackCategory: Bool = false) {
        observeSettingsIfNeeded()
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true
        do {
            let category: AVAudioSession.Category = usePlaybackCategory ? .playback : .ambient
            try AVAudioSession.sharedInstance().setCategory(category, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("AudioSession Fehler:", error) }
    }

    @MainActor
    private func observeSettingsIfNeeded() {
        guard !settingsObserved else { return }
        settingsObserved = true
        GameSettings.shared.$isSoundEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    // Sofortiger Start: Loop entweder vorhanden -> Lautstärke anheben, sonst starten
                    if let loop = self.currentLoopInfo {
                        if let lp = self.loopPlayer {
                            lp.volume = loop.targetVolume
                            if !lp.isPlaying { lp.play() }
                        } else {
                            self.startLoop(name: loop.name, ext: loop.ext, volume: loop.targetVolume)
                        }
                    } else {
                        // Kein Loop gesetzt -> Kontext-Loop direkt hörbar starten
                        if GameSettings.shared.isInGame {
                            self.startLoop(name: "game-music", ext: "mp3", volume: 0.3)
                        } else {
                            self.startLoop(name: "lobby-music", ext: "mp3", volume: 0.6)
                        }
                    }
                } else {
                    // Deaktiviert: SFX stoppen, Loop stumm weiterlaufen lassen (für sofortigen Start später)
                    self.sfxPlayer?.stop(); self.sfxPlayer = nil
                    if let lp = self.loopPlayer {
                        lp.volume = 0
                        if !lp.isPlaying { lp.play() }
                    } else if let loop = self.currentLoopInfo {
                        // Falls noch kein Player existiert, stummen Loop starten
                        self.startLoop(name: loop.name, ext: loop.ext, volume: 0)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Loader
    private func makePlayer(name: String, ext: String) -> AVAudioPlayer? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            do { return try AVAudioPlayer(contentsOf: url) } catch { print("AVAudioPlayer Fehler (URL):", error) }
        }
        for candidate in [name, "\(name).\(ext)"] {
            if let dataAsset = NSDataAsset(name: candidate) {
                do { return try AVAudioPlayer(data: dataAsset.data) } catch { print("AVAudio Fehler (Asset \(candidate)):", error) }
            }
        }
        print("Sound nicht gefunden:", name, ext)
        return nil
    }

    // MARK: - Öffentliche API
    // One-shot SFX
    @MainActor func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        guard GameSettings.shared.isSoundEnabled else { return }
        guard let p = makePlayer(name: name, ext: ext) else { return }
        sfxPlayer?.stop(); sfxPlayer = nil
        sfxPlayer = p
        sfxPlayer?.volume = volume
        sfxPlayer?.prepareToPlay()
        _ = sfxPlayer?.play()
    }

    // Hintergrund-Loop (merkt Ziel-Lautstärke und startet ggf. stumm)
    @MainActor func playLoop(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        currentLoopInfo = (name, ext, volume)
        let vol = GameSettings.shared.isSoundEnabled ? volume : 0
        startLoop(name: name, ext: ext, volume: vol)
    }

    // Sofortiges Stoppen aller Sounds
    @MainActor func stop() {
        loopPlayer?.stop(); loopPlayer = nil
        sfxPlayer?.stop(); sfxPlayer = nil
    }

    // MARK: - Intern
    @MainActor
    private func startLoop(name: String, ext: String, volume: Float) {
        // Phase zurück auf jetzt, indem wir neu starten
        loopPlayer?.stop(); loopPlayer = nil
        guard let p = makePlayer(name: name, ext: ext) else { return }
        loopPlayer = p
        loopPlayer?.numberOfLoops = -1
        loopPlayer?.volume = volume
        loopPlayer?.prepareToPlay()
        _ = loopPlayer?.play()
    }
}
