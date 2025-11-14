//
//  LobbyView.swift
//  EotL
//
//  Created by Michael Hammer on 07/11/2025.
//

import SwiftUI
import SpriteKit

struct LobbyView: View {
    @State private var inGame = false
    @State private var showSettings = false
    @State private var animateStart = false
    @State private var revealProgress: CGFloat = 0.0
    @State private var transitioning = false

    private let buttonSize: CGFloat = 42

    var body: some View {
        ZStack {
            if !inGame {
                lobbyContent
                    .transition(.identity)
            } else {
                GameView()
                    .ignoresSafeArea()
                    .transition(.identity)
            }

            // Circular Reveal Overlay
            if transitioning {
                Color.black
                    .mask(
                        Circle()
                            .scale(revealProgress)
                            .frame(width: UIScreen.main.bounds.height * 2)
                    )
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
    }

    private var lobbyContent: some View {
        ZStack {
            // Hintergrund
            SpriteView(scene: LobbyBackgroundScene(size: UIScreen.main.bounds.size))
                .ignoresSafeArea()

            // Logo
            VStack {
                Text("MAZE")
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.4), radius: 24)
                    .scaleEffect(animateStart ? 1.03 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: animateStart)

                Spacer().frame(height: 140)
            }

            // Start Button
            Button(action: startGameTransition) {
                Text("Start")
                    .font(.system(size: buttonSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 58)
                    .background(
                        Capsule()
                            .fill(Color.pink.opacity(0.9))
                            .shadow(color: .white.opacity(0.4), radius: 14)
                    )
                    .scaleEffect(animateStart ? 1.10 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateStart)
            }

            // Settings Button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding(22)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            SoundManager.shared.setupAudioSession(usePlaybackCategory: true)
            animateStart = true
            SoundManager.shared.playLoop("lobby-music", ext: "mp3", volume: 0.6)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func startGameTransition() {
        SoundManager.shared.stop() // Lobby-Musik aus
        SoundManager.shared.play("level-selected")
        
        transitioning = true

        withAnimation(.easeInOut(duration: 0.70)) {
            revealProgress = 3.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            inGame = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.30)) {
                    transitioning = false
                    revealProgress = 0.0
                }
            }
            SoundManager.shared.playLoop("game-music", ext: "mp3", volume: 0.3)
        }
    }
}
