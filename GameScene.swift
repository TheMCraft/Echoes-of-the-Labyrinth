import SpriteKit

final class GameScene: SKScene {
    private var label: SKLabelNode?

    override func didMove(to view: SKView) {
        backgroundColor = .black

        let label = SKLabelNode(text: "Hello, SpriteKit!")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 40
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        addChild(label)
        self.label = label

        // Simple action to show activity
        let fade = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.8),
            SKAction.fadeAlpha(to: 1.0, duration: 0.8)
        ])
        label.run(SKAction.repeatForever(fade))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        let node = SKShapeNode(circleOfRadius: 12)
        node.fillColor = .systemTeal
        node.strokeColor = .clear
        node.position = location
        addChild(node)

        let moveUp = SKAction.moveBy(x: 0, y: 120, duration: 0.8)
        moveUp.timingMode = .easeOut
        let fadeOut = SKAction.fadeOut(withDuration: 0.8)
        let group = SKAction.group([moveUp, fadeOut])
        node.run(SKAction.sequence([group, .removeFromParent()]))
    }
}
