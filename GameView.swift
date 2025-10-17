import SwiftUI
import SpriteKit
import CoreHaptics

// MARK: - SpriteKit Scene
final class SwipeScene: SKScene, @MainActor SKPhysicsContactDelegate {

    // MARK: Nodes & World
    private let worldNode = SKNode()
    private let arrow = SKShapeNode()
    private var cam: SKCameraNode!
    
    // Key
    private var keyNode: SKShapeNode?
    private var userHasKey: Bool = false

    // Sichtfeld
    private let cropNode = SKCropNode()
    private let maskNode = SKShapeNode(circleOfRadius: 180)

    // Welt
    private var worldSide: CGFloat = 0
    private var worldRect: CGRect {
        CGRect(x: -worldSide/2, y: -worldSide/2, width: worldSide, height: worldSide)
    }

    // Grid / Maze
    private struct Cell {
        var top = true, right = true, bottom = true, left = true
        var visited = false
    }
    private var cols = 14
    private var rows = 10
    private var grid: [[Cell]] = []
    private var cellSize: CGFloat = 0
    private var mazeOrigin: CGPoint = .zero

    private var playerRC: (r: Int, c: Int) = (0, 0)

    // Speichere Outline-Knoten
    private var wallOutlines: [SKShapeNode] = []

    // Haptics & Input
    private var haptics: CHHapticEngine?
    private var touchStart: CGPoint?

    // Tuning
    private let swipeMinDistance: CGFloat = 20
    private let cameraZoom: CGFloat = 1
    private let moveDuration: TimeInterval = 0.12
    private struct Coord: Hashable {
        let r: Int
        let c: Int
    }

    private enum Dir { case up, down, left, right }
    
    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        addChild(cropNode)
        cropNode.addChild(worldNode)

        maskNode.fillColor = .white
        maskNode.strokeColor = .clear
        cropNode.maskNode = maskNode

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupWorld()
        addBackground()            // <-- nach setupWorld
        buildMazeAndWalls()
        setupArrowAtStart()
        spawnKey()
        setupCamera()
        setupHaptics()
        updateCameraConstraints()
    }


    override func didChangeSize(_ oldSize: CGSize) {
        updateCameraConstraints()
    }

    override func update(_ currentTime: TimeInterval) {
        maskNode.position = arrow.position
    }

    // MARK: - Hintergrund
    private func addBackground() {
        let bg = SKSpriteNode(imageNamed: "floor") // Bild in Assets hinzufügen
        bg.size = worldRect.size
        bg.position = CGPoint(x: 0, y: 0)
        bg.zPosition = -100
        worldNode.addChild(bg)   // <- statt addChild(self), ins worldNode
    }


    // MARK: - World
    private func setupWorld() {
        worldSide = max(size.width, size.height) * 4.0

        let border = SKNode()
        border.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(
            x: -worldSide/2, y: -worldSide/2, width: worldSide, height: worldSide
        ))
        border.physicsBody?.categoryBitMask = 0x1 << 1
        border.physicsBody?.isDynamic = false
        worldNode.addChild(border)
    }

    // MARK: - Maze
    private func buildMazeAndWalls() {
        let thickness: CGFloat = 24
        let inset = worldSide * 0.15

        let mazeRect = worldRect.insetBy(dx: inset, dy: inset)
        cellSize = min(
            (mazeRect.width / CGFloat(cols)).rounded(.down),
            (mazeRect.height / CGFloat(rows)).rounded(.down)
        )
        let mazeW = cellSize * CGFloat(cols)
        let mazeH = cellSize * CGFloat(rows)
        mazeOrigin = CGPoint(x: mazeRect.midX - mazeW/2, y: mazeRect.midY - mazeH/2)

        grid = Array(repeating: Array(repeating: Cell(), count: cols), count: rows)

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

        carveMaze(from: (r: 0, c: 0))

        grid[0][0].bottom = false
        grid[rows-1][cols-1].top = false

        func addWall(center: CGPoint, size: CGSize) {
            let wall = SKNode()
            wall.position = center
            wall.physicsBody = SKPhysicsBody(rectangleOf: size)
            wall.physicsBody?.isDynamic = false
            wall.physicsBody?.categoryBitMask = 0x1 << 2
            wall.physicsBody?.collisionBitMask = 0
            worldNode.addChild(wall)

            // Outline für visuelles Feedback
            let outline = SKShapeNode(rectOf: size)
            outline.position = center
            outline.strokeColor = .yellow
            outline.lineWidth = 2
            outline.isHidden = !GameSettings.shared.isDebugMode
            outline.zPosition = 50
            worldNode.addChild(outline)
            wallOutlines.append(outline)
        }

        for r in 0..<rows {
            for c in 0..<cols {
                let cellMinX = mazeOrigin.x + CGFloat(c) * cellSize
                let cellMinY = mazeOrigin.y + CGFloat(r) * cellSize
                let centerX  = cellMinX + cellSize/2
                let centerY  = cellMinY + cellSize/2

                if grid[r][c].bottom {
                    let y = cellMinY
                    addWall(center: CGPoint(x: centerX, y: y),
                            size: CGSize(width: cellSize, height: thickness))
                }
                if grid[r][c].right {
                    let x = cellMinX + cellSize
                    addWall(center: CGPoint(x: x, y: centerY),
                            size: CGSize(width: thickness, height: cellSize))
                }
                if r == rows - 1 && grid[r][c].top {
                    let y = cellMinY + cellSize
                    addWall(center: CGPoint(x: centerX, y: y),
                            size: CGSize(width: cellSize, height: thickness))
                }
                if c == 0 && grid[r][c].left {
                    let x = cellMinX
                    addWall(center: CGPoint(x: x, y: centerY),
                            size: CGSize(width: thickness, height: cellSize))
                }
            }
        }
    }

    // MARK: - Arrow
    private func setupArrowAtStart() {
        playerRC = (0, 0)
        arrow.path = arrowPath(size: 60)
        arrow.fillColor = .systemPink
        arrow.strokeColor = .clear
        arrow.zPosition = 10
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

    // MARK: - Movement

    // Decide swipe direction by dominant axis
    private func classifySwipe(dx: CGFloat, dy: CGFloat) -> Dir {
        // If the horizontal magnitude is greater, go left/right; otherwise up/down
        if abs(dx) > abs(dy) {
            return dx >= 0 ? .right : .left
        } else {
            return dy >= 0 ? .up : .down
        }
    }

    private func canMove(from r: Int, _ c: Int, dir: Dir) -> Bool {
        switch dir {
        case .up:    return r+1 < rows && !grid[r][c].top
        case .down:  return r-1 >= 0 && !grid[r][c].bottom
        case .right: return c+1 < cols && !grid[r][c].right
        case .left:  return c-1 >= 0 && !grid[r][c].left
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
            if !GameSettings.shared.isDebugMode {
                showNearbyWalls(dir)
            }
            hapticImpact()
            let bump = SKAction.sequence([
                SKAction.scale(to: 0.92, duration: 0.06),
                SKAction.scale(to: 1.0, duration: 0.08)
            ])
            let rotate = SKAction.rotate(toAngle: angle, duration: 0.08, shortestUnitArc: true)
            arrow.run(SKAction.group([bump, rotate]))
        }
        if keyDistanceInCells() == 0 {
            userHasKey = true
            keyNode?.removeFromParent()
            onKeyStateChange?(true)
            keyPickupFeedback()
        }
            
    }
    
    var onKeyStateChange: ((Bool) -> Void)?

    private func showNearbyWalls(_ dir: Dir) {
        let (r, c) = playerRC
        var wallPos = centerOfCell(r, c)

        switch dir {
        case .up:
            wallPos.y += cellSize / 2
        case .down:
            wallPos.y -= cellSize / 2
        case .right:
            wallPos.x += cellSize / 2
        case .left:
            wallPos.x -= cellSize / 2
        }

        for outline in wallOutlines {
            if outline.position.distance(to: wallPos) < cellSize * 0.3 {
                outline.isHidden = false
                outline.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.5),
                    SKAction.run { outline.isHidden = true }
                ]))
            }
        }
    }

    private func spawnKey() { //BUG: Key kann in unerreichbaren Stellen des Labyrinths spawnen
        // BFS aller erreichbaren Zellen
        func reachableCells(from start: (Int, Int)) -> Set<Coord> {
            var visited: Set<Coord> = [Coord(r: start.0, c: start.1)]
            var queue: [Coord] = [Coord(r: start.0, c: start.1)]
            var head = 0
            // harte Obergrenze gegen Logikfehler
            let maxNodes = rows * cols

            while head < queue.count {
                let current = queue[head]; head += 1
                let r = current.r, c = current.c

                for dir in [Dir.up, .down, .left, .right] {
                    if canMove(from: r, c, dir: dir) {
                        let (nr, nc) = nextCell(from: r, c, dir: dir)
                        let next = Coord(r: nr, c: nc)
                        if !visited.contains(next) {
                            visited.insert(next)
                            queue.append(next)
                            if visited.count >= maxNodes { return visited }
                        }
                    }
                }
            }
            return visited
        }

        let start = playerRC
        let reachable = Array(reachableCells(from: start))   // [Coord]
        if reachable.isEmpty { return }

        // mind. 5 Schritte entfernt, Startfeld raus
        let minSteps = 5
        let far = reachable.filter { coord in
            guard !(coord.r == start.r && coord.c == start.c) else { return false }
            let dr = abs(coord.r - start.r)
            let dc = abs(coord.c - start.c)
            return dr + dc >= minSteps
        }

        // Fallbacks: weit entfernt → sonst irgendeine andere erreichbare Zelle → sonst abbrechen
        let pick: Coord? = far.randomElement()
            ?? reachable.first { !($0.r == start.r && $0.c == start.c) }
            ?? nil
        guard let target = pick else { return }

        // existierenden Key ersetzen
        keyNode?.removeFromParent()

        let keyPos = centerOfCell(target.r, target.c)
        let key = SKShapeNode(circleOfRadius: cellSize * 0.25)
        key.fillColor = .systemYellow
        key.strokeColor = .white
        key.glowWidth = 4
        key.zPosition = 20
        key.position = keyPos

        // optional: leichter Puls
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        key.run(SKAction.repeatForever(pulse))

        worldNode.addChild(key)
        keyNode = key
    }

    private func keyDistanceInCells() -> Int {
        guard let key = keyNode, cellSize > 0 else { return 0 }
        let kp = key.position
        let kr = max(0, min(rows - 1, Int(round(((kp.y - mazeOrigin.y) / cellSize) - 0.5))))
        let kc = max(0, min(cols - 1, Int(round(((kp.x - mazeOrigin.x) / cellSize) - 0.5))))
        return abs(kr - playerRC.r) + abs(kc - playerRC.c)
    }

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

    private func hapticImpact(duration: TimeInterval? = nil,
                              intensity: Float = 0.9,
                              sharpness: Float = 0.7) {
        guard let engine = haptics else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)

        let event: CHHapticEvent
        if let d = duration, d > 0 {
            event = CHHapticEvent(eventType: .hapticContinuous, parameters: [i, s], relativeTime: 0, duration: d)
        } else {
            event = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)
        }

        do {
            try? engine.start()
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch { }
    }
    
    // State
    private var isHolding = false
    private var holdWorkItem: DispatchWorkItem?
    private let longPressDelay: TimeInterval = 0.35

    // Helpers
    private func startHoldDetection() {
        holdWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isHolding = true
            self.onHoldStart()
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressDelay, execute: work)
    }

    private func cancelPendingHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    private func endActiveHold() {
        if isHolding {
            isHolding = false
            onHoldEnd()
        }
    }

    // Override touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = touches.first?.location(in: self)
        startHoldDetection()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let start = touchStart,
              let cur = touches.first?.location(in: self) else { return }
        let dx = cur.x - start.x
        let dy = cur.y - start.y
        let distance = hypot(dx, dy)

        // If user starts swiping before the long‑press fires, cancel pending hold
        if !isHolding && distance > swipeMinDistance {
            cancelPendingHold()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { touchStart = nil }
        if isHolding {
            endActiveHold()            // end long‑press
            return                      // skip swipe
        }
        cancelPendingHold()            // no hold -> treat as swipe
        guard let start = touchStart,
              let end = touches.first?.location(in: self) else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance >= swipeMinDistance else { return }
        let direction = classifySwipe(dx: dx, dy: dy)
        tryMove(direction)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelPendingHold()
        endActiveHold()
        touchStart = nil
    }

    private var holdTask: Task<Void, Never>? // ohne @MainActor hier!

    private func onHoldStart() {
        holdTask?.cancel()

        holdTask = Task {
            await self.runHoldSequence()
        }
    }

    @MainActor
    private func runHoldSequence() async {
        hapticImpact(duration: 1.0, intensity: 0.5, sharpness: 0.5)

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let baseDelay: UInt64 = 150_000_000
        let growthFactor: Double = 1.15
        let count = keyDistanceInCells()

        var currentDelay = Double(baseDelay)

        for i in 0..<count {
            try? Task.checkCancellation()
            print("Index \(i)")
            hapticImpact(duration: 0.1, intensity: 0.6, sharpness: 0.6)
            try? await Task.sleep(nanoseconds: UInt64(currentDelay))
            currentDelay *= growthFactor
        }

        for _ in 0..<2 {
            try? Task.checkCancellation()
            hapticImpact(duration: 0.1, intensity: 0.9, sharpness: 0.9)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private func onHoldEnd() {
        holdTask?.cancel()
        holdTask = nil
    }
    
    private func keyPickupFeedback() {
        guard haptics != nil else { return }

        Task { @MainActor in
            // Kurzer kräftiger Startimpuls
            hapticImpact(duration: 0.08, intensity: 1.0, sharpness: 0.9)
            try? await Task.sleep(nanoseconds: 100_000_000)

            // Zwei schnelle, weichere „Echo“-Impacts
            hapticImpact(duration: 0.05, intensity: 0.7, sharpness: 0.5)
            try? await Task.sleep(nanoseconds: 80_000_000)
            hapticImpact(duration: 0.05, intensity: 0.6, sharpness: 0.4)
            try? await Task.sleep(nanoseconds: 150_000_000)

            // Kleiner „Nachglüher“ – sanfter Ausklang
            hapticImpact(duration: 0.1, intensity: 0.3, sharpness: 0.2)
        }
    }

}

// MARK: - Hilfs-Extension
private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        return hypot(x - other.x, y - other.y)
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
    
    @State private var userHasKey = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .onAppear {
                    // Scene bekommt Callback
                    scene.onKeyStateChange = { hasKey in
                        userHasKey = hasKey
                    }
                }

            if userHasKey {
                Image(systemName: "key.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.yellow)
                    .padding(20)
                    .shadow(radius: 3)
                    .transition(.scale)
            }
        }
    }
}
