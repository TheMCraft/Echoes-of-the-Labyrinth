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

    // MARK: Grid / Maze
    private struct Cell {
        var top = true, right = true, bottom = true, left = true
        var visited = false
    }
    private var cols = 14
    private var rows = 10
    private var grid: [[Cell]] = []
    private var cellSize: CGFloat = 0
    private var mazeOrigin: CGPoint = .zero  // linke-untere Ecke des Maze-Rechtecks (in Weltkoordinaten)

    // Aktuelle Spielerzelle (r: Zeile, c: Spalte) — r=0 ist unten, wächst nach oben
    private var playerRC: (r: Int, c: Int) = (0, 0)

    // MARK: Haptics & Input
    private var haptics: CHHapticEngine?
    private var touchStart: CGPoint?

    // MARK: Tuning
    private let swipeMinDistance: CGFloat = 20
    private let cameraZoom: CGFloat = 1       // <1 = reinzoomen
    private let moveDuration: TimeInterval = 0.12

    private enum Dir { case up, down, left, right }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        addChild(worldNode)

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupWorld()
        buildMazeAndWalls()
        setupArrowAtStart()
        setupCamera()
        setupHaptics()
        updateCameraConstraints()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        updateCameraConstraints()
    }

    // MARK: - World
    private func setupWorld() {
        worldSide = max(size.width, size.height) * 4.0  // Weltgröße hier skalieren

        let border = SKShapeNode(rectOf: CGSize(width: worldSide, height: worldSide))
        border.lineWidth = 6
        border.strokeColor = .darkGray
        border.fillColor = .clear
        border.zPosition = -10
        border.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(
            x: -worldSide/2, y: -worldSide/2, width: worldSide, height: worldSide
        ))
        border.physicsBody?.categoryBitMask = 0x1 << 1
        border.physicsBody?.isDynamic = false
        worldNode.addChild(border)
    }

    // MARK: - Maze (Grid + Wände)
    private func buildMazeAndWalls() {
        // --- Parameter ---
        let thickness: CGFloat = 24            // Wandstärke
        let inset = worldSide * 0.15           // Abstand Maze zu Weltrand

        // --- Maze-Rect innerhalb der Welt ---
        let mazeRect = worldRect.insetBy(dx: inset, dy: inset)
        cellSize = min(
            (mazeRect.width / CGFloat(cols)).rounded(.down),
            (mazeRect.height / CGFloat(rows)).rounded(.down)
        )
        let mazeW = cellSize * CGFloat(cols)
        let mazeH = cellSize * CGFloat(rows)
        mazeOrigin = CGPoint(x: mazeRect.midX - mazeW/2, y: mazeRect.midY - mazeH/2)

        // Grid initialisieren
        grid = Array(repeating: Array(repeating: Cell(), count: cols), count: rows)

        // Maze mit DFS-Backtracker schnitzen
        func carveMaze(from start: (r: Int, c: Int)) {
            var stack: [(r: Int, c: Int)] = [start]
            grid[start.r][start.c].visited = true

            while let current = stack.last {
                var neighbors: [(r: Int, c: Int, dir: Dir)] = []
                let r = current.r, c = current.c

                if r+1 < rows && !grid[r+1][c].visited { neighbors.append((r+1, c, .up)) }
                if c+1 < cols && !grid[r][c+1].visited { neighbors.append((r, c+1, .right)) }
                if r-1 >= 0   && !grid[r-1][c].visited { neighbors.append((r-1, c, .down)) }
                if c-1 >= 0   && !grid[r][c-1].visited { neighbors.append((r, c-1, .left)) }

                guard let next = neighbors.randomElement() else {
                    _ = stack.popLast()
                    continue
                }

                switch next.dir {
                case .up:
                    grid[r][c].top = false
                    grid[next.r][next.c].bottom = false
                case .right:
                    grid[r][c].right = false
                    grid[next.r][next.c].left = false
                case .down:
                    grid[r][c].bottom = false
                    grid[next.r][next.c].top = false
                case .left:
                    grid[r][c].left = false
                    grid[next.r][next.c].right = false
                }

                grid[next.r][next.c].visited = true
                stack.append((next.r, next.c))
            }
        }

        // Maze schnitzen; Start unten links
        carveMaze(from: (r: 0, c: 0))

        // Eintritt/Austritt öffnen
        grid[0][0].bottom = false                // Eingang unten links
        grid[rows-1][cols-1].top = false         // Ausgang oben rechts

        // Helper zum Wandzeichnen
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
            wall.physicsBody?.collisionBitMask = 0
            worldNode.addChild(wall)
        }

        // Wände zeichnen ohne Duplikate
        for r in 0..<rows {
            for c in 0..<cols {
                let cellMinX = mazeOrigin.x + CGFloat(c) * cellSize
                let cellMinY = mazeOrigin.y + CGFloat(r) * cellSize
                let centerX  = cellMinX + cellSize/2
                let centerY  = cellMinY + cellSize/2

                // bottom
                if grid[r][c].bottom {
                    let y = cellMinY
                    addWall(center: CGPoint(x: centerX, y: y),
                            size: CGSize(width: cellSize, height: thickness))
                }
                // right
                if grid[r][c].right {
                    let x = cellMinX + cellSize
                    addWall(center: CGPoint(x: x, y: centerY),
                            size: CGSize(width: thickness, height: cellSize))
                }
                // top nur in oberster Reihe
                if r == rows - 1 && grid[r][c].top {
                    let y = cellMinY + cellSize
                    addWall(center: CGPoint(x: centerX, y: y),
                            size: CGSize(width: cellSize, height: thickness))
                }
                // left nur in linker Spalte
                if c == 0 && grid[r][c].left {
                    let x = cellMinX
                    addWall(center: CGPoint(x: x, y: centerY),
                            size: CGSize(width: thickness, height: cellSize))
                }
            }
        }
    }

    // MARK: - Arrow (spieler zentriert im Zellzentrum)
    private func setupArrowAtStart() {
        // Startzelle (unten links)
        playerRC = (0, 0)

        arrow.path = arrowPath(size: 60)
        arrow.fillColor = .systemPink
        arrow.strokeColor = .clear
        arrow.zPosition = 10

        // Keine Physik am Player — wir bewegen diskret im Grid
        arrow.physicsBody = nil

        arrow.position = centerOfCell(playerRC.r, playerRC.c)
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

    private func centerOfCell(_ r: Int, _ c: Int) -> CGPoint {
        let x = mazeOrigin.x + (CGFloat(c) + 0.5) * cellSize
        let y = mazeOrigin.y + (CGFloat(r) + 0.5) * cellSize
        return CGPoint(x: x, y: y)
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
        tryMove(direction)
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

    // MARK: - Diskrete Grid-Bewegung
    private func canMove(from r: Int, _ c: Int, dir: Dir) -> Bool {
        switch dir {
        case .up:
            guard r+1 < rows else { return false }
            return !grid[r][c].top
        case .down:
            guard r-1 >= 0 else { return false }
            return !grid[r][c].bottom
        case .right:
            guard c+1 < cols else { return false }
            return !grid[r][c].right
        case .left:
            guard c-1 >= 0 else { return false }
            return !grid[r][c].left
        }
    }

    private func nextCell(from r: Int, _ c: Int, dir: Dir) -> (Int, Int) {
        switch dir {
        case .up:    return (r+1, c)
        case .down:  return (r-1, c)
        case .right: return (r, c+1)
        case .left:  return (r, c-1)
        }
    }

    private func tryMove(_ dir: Dir) {
        // Rotationwinkel
        let angle: CGFloat = {
            switch dir {
            case .up: return .pi/2
            case .down: return -.pi/2
            case .right: return 0
            case .left: return .pi
            }
        }()

        if canMove(from: playerRC.r, playerRC.c, dir: dir) {
            let (nr, nc) = nextCell(from: playerRC.r, playerRC.c, dir: dir)
            playerRC = (nr, nc)
            let target = centerOfCell(nr, nc)

            arrow.removeAllActions()
            let move = SKAction.move(to: target, duration: moveDuration)
            let rotate = SKAction.rotate(toAngle: angle, duration: 0.08, shortestUnitArc: true)
            let pulse = SKAction.sequence([
                SKAction.group([rotate, SKAction.scale(to: 1.12, duration: 0.08)]),
                SKAction.scale(to: 1.0, duration: 0.08)
            ])
            arrow.run(SKAction.group([move, pulse]))
        } else {
            // Blockiert -> Haptik + kurzes "Bump"
            hapticImpact()
            let bump = SKAction.sequence([
                SKAction.scale(to: 0.92, duration: 0.06),
                SKAction.scale(to: 1.0, duration: 0.08)
            ])
            let rotate = SKAction.rotate(toAngle: angle, duration: 0.08, shortestUnitArc: true)
            arrow.run(SKAction.group([bump, rotate]))
        }
    }

    // MARK: - Physics Contact (nicht mehr genutzt für den Player)
    func didBegin(_ contact: SKPhysicsContact) { }

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
