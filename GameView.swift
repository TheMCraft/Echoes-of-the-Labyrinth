import SwiftUI
import SpriteKit
import CoreHaptics

// MARK: - SpriteKit Scene
final class SwipeScene: SKScene {

    // MARK: Nodes & World
    private let worldNode = SKNode()
    private let arrow = SKShapeNode()
    private var cam: SKCameraNode!

    // Welt: Quadrat, Mittelpunkt = (0,0)
    private var worldSide: CGFloat = 0
    private var worldRect: CGRect {
        CGRect(x: -worldSide/2, y: -worldSide/2, width: worldSide, height: worldSide)
    }

    // MARK: Haptics & Input
    private var haptics: CHHapticEngine?
    private var touchStart: CGPoint?

    // MARK: Tuning
    private let swipeMinDistance: CGFloat = 20
    private let moveSpeed: CGFloat = 5000
    private let edgeInset: CGFloat = 24
    private let cameraZoom: CGFloat = 0.75 // kleiner als 1 => Kamera zoomt rein

    private enum Dir {
        case up, down, left, right
    }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        addChild(worldNode)

        setupWorld()
        setupArrow()
        setupCamera()
        setupHaptics()
        updateCameraConstraints()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        updateCameraConstraints()
    }

    // MARK: - World
    private func setupWorld() {
        worldSide = max(size.width, size.height) * 4.0

        let border = SKShapeNode(rectOf: CGSize(width: worldSide, height: worldSide))
        border.lineWidth = 6
        border.strokeColor = .darkGray
        border.fillColor = .clear
        border.zPosition = -10
        worldNode.addChild(border)
    }

    // MARK: - Arrow
    private func setupArrow() {
        arrow.path = arrowPath(size: 60)
        arrow.fillColor = .systemPink
        arrow.strokeColor = .clear
        arrow.position = .zero
        arrow.zPosition = 10
        worldNode.addChild(arrow)
    }

    private func arrowPath(size: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let w = size
        let h = size * 0.55
        p.move(to: CGPoint(x: -w * 0.45, y: -h * 0.5))
        p.addLine(to: CGPoint(x: -w * 0.45, y:  h * 0.5))
        p.addLine(to: CGPoint(x:  w * 0.35, y:  0))
        p.closeSubpath()
        return p
    }

    // MARK: - Camera
    private func setupCamera() {
        cam = SKCameraNode()
        camera = cam
        addChild(cam)

        cam.setScale(cameraZoom)
        cam.position = arrow.position
    }

    private func updateCameraConstraints() {
        guard let view = self.view else { return }

        let visibleW = view.bounds.width * cam.xScale
        let visibleH = view.bounds.height * cam.yScale

        let xInset = visibleW/2
        let yInset = visibleH/2
        let limitRect = worldRect.insetBy(dx: xInset, dy: yInset)

        let follow = SKConstraint.distance(SKRange(constantValue: 0), to: arrow)
        let xRange = SKRange(lowerLimit: limitRect.minX, upperLimit: limitRect.maxX)
        let yRange = SKRange(lowerLimit: limitRect.minY, upperLimit: limitRect.maxY)
        let xLock = SKConstraint.positionX(xRange)
        let yLock = SKConstraint.positionY(yRange)

        cam.constraints = [follow, xLock, yLock]
    }

    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = touches.first?.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let start = touchStart,
              let end = touches.first?.location(in: self) else {
            touchStart = nil
            return
        }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)

        guard distance >= swipeMinDistance else {
            touchStart = nil
            return
        }

        let direction = classifySwipe(dx: dx, dy: dy)
        moveArrow(direction: direction)
        touchStart = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }

    // MARK: - Direction Classification (nur 4 Richtungen)
    private func classifySwipe(dx: CGFloat, dy: CGFloat) -> Dir {
        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .up : .down
        }
    }

    // MARK: - Movement
    private func moveArrow(direction: Dir) {
        arrow.removeAllActions()
        let current = arrow.position
        var target = current

        let minX = worldRect.minX + edgeInset
        let maxX = worldRect.maxX - edgeInset
        let minY = worldRect.minY + edgeInset
        let maxY = worldRect.maxY - edgeInset

        switch direction {
        case .up:    target = CGPoint(x: current.x, y: maxY)
        case .down:  target = CGPoint(x: current.x, y: minY)
        case .right: target = CGPoint(x: maxX, y: current.y)
        case .left:  target = CGPoint(x: minX, y: current.y)
        }

        let distance = hypot(target.x - current.x, target.y - current.y)
        let duration = distance / moveSpeed

        let move = SKAction.move(to: target, duration: max(0.0001, duration))
        move.timingMode = .easeOut

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.08),
            SKAction.scale(to: 1.0,  duration: 0.10)
        ])

        arrow.run(move) { [weak self] in
            self?.hapticImpact()
            self?.arrow.run(pulse)
        }
    }

    // MARK: - Haptics
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
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch { }
    }
}

// MARK: - SwiftUI wrapper
struct GameView: View {
    @State private var scene: SwipeScene = {
        let size = UIScreen.main.bounds.size
        let scene = SwipeScene(size: size)
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
