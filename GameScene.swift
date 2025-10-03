import SpriteKit
import CoreHaptics

final class GameScene: SKScene {

    private let arrow = SKShapeNode()
    private var haptics: CHHapticEngine?
    private let swipeThreshold: CGFloat = 12
    private let moveSpeed: CGFloat = 500 // Punkte pro Sekunde
    private let edgeInset: CGFloat = 24  // Abstand vom Rand

    override func didMove(to view: SKView) {
        backgroundColor = .black
        setupHaptics()
        setupArrow()
    }

    private func setupArrow() {
        arrow.path = arrowPath(size: 60)
        arrow.fillColor = .systemPink
        arrow.strokeColor = .clear
        arrow.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(arrow)
    }

    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            haptics = try CHHapticEngine()
            try haptics?.start()
        } catch {
            haptics = nil
        }
    }

    private func hapticImpact() {
        guard let engine = haptics else { return }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 10)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 10)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch { }
    }

    // Input
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let end = t.location(in: self)
        let start = t.previousLocation(in: self)
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) < swipeThreshold && abs(dy) < swipeThreshold { return }

        let horizontal = abs(dx) > abs(dy)
        if horizontal {
            moveArrow(direction: dx > 0 ? .right : .left)
        } else {
            moveArrow(direction: dy > 0 ? .up : .down)
        }
    }

    private enum Dir { case up, right, down, left }

    private func moveArrow(direction: Dir) {
        arrow.removeAllActions()

        let current = arrow.position
        var target = current

        switch direction {
        case .up:
            target.y = size.height - edgeInset
        case .down:
            target.y = edgeInset
        case .right:
            target.x = size.width - edgeInset
        case .left:
            target.x = edgeInset
        }

        let distance = hypot(target.x - current.x, target.y - current.y)
        let duration = distance / moveSpeed

        let move = SKAction.move(to: target, duration: duration)
        move.timingMode = .easeOut

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.08),
            SKAction.scale(to: 1.0, duration: 0.10)
        ])

        arrow.run(move) { [weak self] in
            self?.hapticImpact()
            self?.arrow.run(pulse)
        }
    }

    private func arrowPath(size: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let w = size
        let h = size * 0.55
        p.move(to: CGPoint(x: -w * 0.45, y: -h * 0.5))
        p.addLine(to: CGPoint(x: -w * 0.45, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.35, y: 0))
        p.closeSubpath()
        return p
    }
}
