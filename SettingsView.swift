//
//  SettingsView.swift
//  EotL
//
//  Created by Michael Hammer on 07/11/2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var debugMode = GameSettings.shared.isDebugMode
    @State private var soundEnabled = GameSettings.shared.isSoundEnabled

    // Optionaler Callback; wenn gesetzt, zeigen wir einen "Give up" Button
    var onGiveUp: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Gameplay") {
                    Toggle("Debug Mode (zeigt Wände immer)", isOn: $debugMode)
                }
                Section("Audio") {
                    Toggle("Sound aktiv", isOn: $soundEnabled)
                        .onChange(of: soundEnabled) { newVal in
                            GameSettings.shared.isSoundEnabled = newVal
                        }
                }
                if onGiveUp != nil {
                    Section("Spiel") {
                        Button(role: .destructive) {
                            // sofort schließen und Lobby zurückgeben
                            SoundManager.shared.stop()
                            dismiss()
                            onGiveUp?()
                        } label: {
                            Text("Give up")
                        }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        GameSettings.shared.isDebugMode = debugMode
                        GameSettings.shared.isSoundEnabled = soundEnabled
                        dismiss()
                    }
                }
            }
        }
    }
}
