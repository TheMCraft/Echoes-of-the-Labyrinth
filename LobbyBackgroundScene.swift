//
//  LobbyBackgroundScene.swift
//  EotL
//
//  Created by Michael Hammer on 07/11/2025.
//

import SpriteKit

final class LobbyBackgroundScene: SKScene {
    private var bg: SKSpriteNode!
    private let starsFar = SKNode()
    private let starsNear = SKNode()
    private var startTime: CFTimeInterval = 0

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = .black

        // Shader Placeholder - Original Code später einfügen
        let shader = SKShader(source: "")
        bg = SKSpriteNode(color: .black, size: size)
        bg.shader = shader
        bg.position = .zero
        bg.zPosition = -1000
        addChild(bg)

        addChild(starsFar)
        addChild(starsNear)

        spawnStars(into: starsFar, count: 240, maxRadius: 1.3, alpha: 0.7, drift: 6)
        spawnStars(into: starsNear, count: 120, maxRadius: 2.1, alpha: 1.0, drift: 10)
    }

    override func update(_ currentTime: TimeInterval) {
        if startTime == 0 { startTime = currentTime }
        let t = Float(currentTime - startTime)

        bg.shader?.uniformNamed("u_time")?.floatValue = t

        starsFar.position.x = sin(CGFloat(t) * 0.12) * 10
        starsNear.position.x = sin(CGFloat(t) * 0.20) * 16
    }

    private func spawnStars(into node: SKNode, count: Int, maxRadius: CGFloat, alpha: CGFloat, drift: CGFloat) {
        for _ in 0..<count {
            let r = CGFloat.random(in: 0.6...maxRadius)
            let s = SKShapeNode(circleOfRadius: r)
            s.fillColor = .white
            s.strokeColor = .clear
            s.alpha = alpha * .random(in: 0.5...1.0)
            s.position = CGPoint(x: .random(in: -size.width...size.width),
                                 y: .random(in: -size.height...size.height))
            node.addChild(s)

            let move = SKAction.moveBy(x: .random(in: -drift...drift),
                                       y: .random(in: -drift...drift),
                                       duration: .random(in: 3...6))
            move.timingMode = .easeInEaseOut

            s.run(.repeatForever(.sequence([move, move.reversed()])))
        }
    }
}
