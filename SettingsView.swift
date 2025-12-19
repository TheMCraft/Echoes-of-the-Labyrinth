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

    // Difficulty control
    enum Difficulty: Int, CaseIterable, Identifiable {
        case easy = 0, normal = 1, hard = 2
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .easy: return "Easy"
            case .normal: return "Normal"
            case .hard: return "Hard"
            }
        }
        var cols: Int { [10, 14, 18][rawValue] }
        var rows: Int { [8, 10, 12][rawValue] }
    }

    @State private var selectedDifficulty: Difficulty = {
        let cols = GameSettings.shared.mazeCols
        let rows = GameSettings.shared.mazeRows
        if cols <= 11 && rows <= 8 { return .easy }
        if cols >= 18 && rows >= 12 { return .hard }
        return .normal
    }()

    // Optionaler Callback; wenn gesetzt, zeigen wir einen "Give up" Button
    var onGiveUp: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Gameplay") {
                    Toggle("Debug Mode (zeigt Wände immer)", isOn: $debugMode)
                    Picker("Schwierigkeit", selection: $selectedDifficulty) {
                        ForEach(Difficulty.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
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
                        // Commit difficulty to settings
                        GameSettings.shared.mazeCols = selectedDifficulty.cols
                        GameSettings.shared.mazeRows = selectedDifficulty.rows
                        dismiss()
                    }
                }
            }
        }
    }
}
