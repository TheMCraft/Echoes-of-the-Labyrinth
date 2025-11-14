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

    var body: some View {
        NavigationView {
            Form {
                Section("Gameplay") {
                    Toggle("Debug Mode (zeigt Wände immer)", isOn: $debugMode)
                }
                Section("Audio") {
                    Toggle("Sound aktiv", isOn: $soundEnabled)
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
