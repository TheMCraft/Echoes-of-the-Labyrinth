import SwiftUI
import SpriteKit
import CoreHaptics

// MARK: - SpriteKit Scene
final class SwipeScene: SKScene, @MainActor SKPhysicsContactDelegate {

    // MARK: Nodes & World
    private let worldNode = SKNode()
    private let arrow = SKShapeNode()
    private var cam: SKCameraNode!

    // Welt: Quadrat, Mittelpunkt = (0,0)
    private var worldSide: CGFloat = 0
    private var worldRect: CGRect {
        CGRect(x: -worldSide/2, y: -worldSide/2, width: worldSide, height: worldSide)
    }

    // MARK: Walls (immer bis zum Rand)
    private var walls: [CGRect] {
        let thickness: CGFloat = 40
        return [
            // vertikal, von oben bis unten
            CGRect(x: -150, y: -worldSide/2, width: thickness, height: worldSide),
            CGRect(x: 200,  y: -worldSide/2, width: thickness, height: worldSide),

            // horizontal, von links bis rechts
            CGRect(x: -worldSide/2, y: -100, width: worldSide, height: thickness),
            CGRect(x: -worldSide/2, y: 300,  width: worldSide, height: thickness)
        ]
    }

    // MARK: Haptics & Input
    private var haptics: CHHapticEngine?
    private var touchStart: CGPoint?

    // MARK: Tuning
    private let swipeMinDistance: CGFloat = 20
    private let moveSpeed: CGFloat = 10
    private let edgeInset: CGFloat = 24
    private let cameraZoom: CGFloat = 1 // kleiner als 1 => Kamera zoomt rein

    private enum Dir {
        case up, down, left, right
    }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        addChild(worldNode)

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupWorld()
        setupWalls()
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

        // physik für welt-rand
        border.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(
            x: -worldSide/2, y: -worldSide/2,
            width: worldSide, height: worldSide
        ))
        border.physicsBody?.categoryBitMask = 0x1 << 1
        border.physicsBody?.isDynamic = false

        worldNode.addChild(border)
    }

    private func setupWalls() {
        // --- Parameter ---
        let thickness: CGFloat = 24            // Wandstärke (muss > 0)
        let cols = 14                          // Spalten (Zellen)
        let rows = 10                          // Zeilen (Zellen)
        let inset = worldSide * 0.15           // Abstand vom Weltrand

        // --- Maze-Rect innerhalb der Welt ---
        let mazeRect = worldRect.insetBy(dx: inset, dy: inset)
        let cell = min( (mazeRect.width / CGFloat(cols)).rounded(.down),
                        (mazeRect.height / CGFloat(rows)).rounded(.down) )
        let mazeW = cell * CGFloat(cols)
        let mazeH = cell * CGFloat(rows)
        let origin = CGPoint(x: mazeRect.midX - mazeW/2, y: mazeRect.midY - mazeH/2)

        // Helfer zum Hinzufügen einer Wand
        func addWall(center: CGPoint, size: CGSize) {
            let wall = SKShapeNode(rectOf: size, cornerRadius: 2)
            wall.position = center
            wall.fillColor = .gray
            wall.strokeColor = .white
            wall.lineWidth = 1.5
            wall.zPosition = -5
            wall.physicsBody = SKPhysicsBody(rectangleOf: size)
            wall.physicsBody?.isDynamic = false
            wall.physicsBody?.categoryBitMask = 0x1 << 2
            wall.physicsBody?.collisionBitMask = 0x1 << 0
            worldNode.addChild(wall)
        }

        // Zellstruktur mit vier möglichen Wänden
        struct Cell {
            var top = true, right = true, bottom = true, left = true
            var visited = false
        }

        // Grid initialisieren
        var grid = Array(repeating: Array(repeating: Cell(), count: cols), count: rows)

        // DFS-Backtracker zum "Schnitzen"
        func carveMaze(from start: (r: Int, c: Int)) {
            var stack: [(r: Int, c: Int)] = [start]
            grid[start.r][start.c].visited = true

            while let current = stack.last {
                var neighbors: [(r: Int, c: Int, dir: String)] = []
                let r = current.r, c = current.c

                // Nachbarn sammeln
                if r+1 < rows && !grid[r+1][c].visited { neighbors.append((r+1, c, "up")) }
                if c+1 < cols && !grid[r][c+1].visited { neighbors.append((r, c+1, "right")) }
                if r-1 >= 0   && !grid[r-1][c].visited { neighbors.append((r-1, c, "down")) }
                if c-1 >= 0   && !grid[r][c-1].visited { neighbors.append((r, c-1, "left")) }

                if neighbors.isEmpty {
                    _ = stack.popLast()
                    continue
                }

                let next = neighbors.randomElement()!

                // Wände zwischen current und next entfernen
                switch next.dir {
                case "up":
                    grid[r][c].top = false
                    grid[next.r][next.c].bottom = false
                case "right":
                    grid[r][c].right = false
                    grid[next.r][next.c].left = false
                case "down":
                    grid[r][c].bottom = false
                    grid[next.r][next.c].top = false
                case "left":
                    grid[r][c].left = false
                    grid[next.r][next.c].right = false
                default: break
                }

                grid[next.r][next.c].visited = true
                stack.append((next.r, next.c))
            }
        }

        // Maze schnitzen; Start unten links
        carveMaze(from: (r: 0, c: 0))

        // Eintritt/Austritt öffnen
        let entranceCol = 0             // unten (row 0)
        grid[0][entranceCol].bottom = false
        let exitCol = cols - 1          // oben (row rows-1)
        grid[rows-1][exitCol].top = false

        // --- Wände zeichnen ---
        // Konvention: Wir zeichnen pro Zelle die "bottom" und "right" Wand.
        // Zusätzlich zeichnen wir für die oberste Reihe die "top"-Wände
        // und für die linkeste Spalte die "left"-Wände. So gibt es keine Duplikate.

        for r in 0..<rows {
            for c in 0..<cols {
                let cellMinX = origin.x + CGFloat(c) * cell
                let cellMinY = origin.y + CGFloat(r) * cell
                let centerX  = cellMinX + cell/2
                let centerY  = cellMinY + cell/2

                // bottom
                if grid[r][c].bottom {
                    let y = cellMinY
                    addWall(center: CGPoint(x: centerX, y: y),
                            size: CGSize(width: cell, height: thickness))
                }
                // right
                if grid[r][c].right {
                    let x = cellMinX + cell
                    addWall(center: CGPoint(x: x, y: centerY),
                            size: CGSize(width: thickness, height: cell))
                }
                // top nur in oberster Reihe
                if r == rows - 1 && grid[r][c].top {
                    let y = cellMinY + cell
                    addWall(center: CGPoint(x: centerX, y: y),
                            size: CGSize(width: cell, height: thickness))
                }
                // left nur in linker Spalte
                if c == 0 && grid[r][c].left {
                    let x = cellMinX
                    addWall(center: CGPoint(x: x, y: centerY),
                            size: CGSize(width: thickness, height: cell))
                }
            }
        }
    }



    // MARK: - Arrow
    private func setupArrow() {
        arrow.path = arrowPath(size: 60)
        arrow.fillColor = .systemPink
        arrow.strokeColor = .clear
        arrow.position = .zero
        arrow.zPosition = 10

        arrow.physicsBody = SKPhysicsBody(polygonFrom: arrow.path!)
        arrow.physicsBody?.isDynamic = true
        arrow.physicsBody?.affectedByGravity = false
        arrow.physicsBody?.allowsRotation = false
        arrow.physicsBody?.categoryBitMask = 0x1 << 0
        arrow.physicsBody?.collisionBitMask = 0xFFFFFFFF
        arrow.physicsBody?.contactTestBitMask = 0xFFFFFFFF

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

    private func moveArrow(direction: Dir) {
        arrow.removeAllActions()

        let impulse: CGVector
        let force: CGFloat = 150

        // Rotation in Radiant
        let angle: CGFloat
        switch direction {
        case .up:
            impulse = CGVector(dx: 0, dy: force)
            angle = .pi/2
        case .down:
            impulse = CGVector(dx: 0, dy: -force)
            angle = -.pi/2
        case .right:
            impulse = CGVector(dx: force, dy: 0)
            angle = 0
        case .left:
            impulse = CGVector(dx: -force, dy: 0)
            angle = .pi
        }

        arrow.physicsBody?.velocity = .zero
        arrow.physicsBody?.applyImpulse(impulse)

        // Drehung animiert
        let rotate = SKAction.rotate(toAngle: angle, duration: 0.1, shortestUnitArc: true)

        let pulse = SKAction.sequence([
            SKAction.group([
                rotate,
                SKAction.scale(to: 1.15, duration: 0.08)
            ]),
            SKAction.scale(to: 1.0,  duration: 0.10)
        ])
        arrow.run(pulse)
    }

    // MARK: - Physics Contact
    func didBegin(_ contact: SKPhysicsContact) {
        if contact.bodyA.node == arrow || contact.bodyB.node == arrow {
            arrow.physicsBody?.velocity = .zero
            hapticImpact()
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
