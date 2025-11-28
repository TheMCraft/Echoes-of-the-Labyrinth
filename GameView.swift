import SwiftUI
import SpriteKit
import CoreHaptics
import simd

// MARK: - SpriteKit Scene
final class SwipeScene: SKScene, @MainActor SKPhysicsContactDelegate {

    // MARK: Nodes & World
    private let worldNode = SKNode()
    private let arrow = SKSpriteNode(imageNamed: "player")
    private var cam: SKCameraNode!

    // Background outside vision
    private let bgLayer = SKNode()
    private var outerBG: SKSpriteNode?
    private var bgShader: SKShader?
    private var bgStartTime: CFTimeInterval = 0
    // New: parallax stars outside the vision
    private let starsFar = SKNode()
    private let starsNear = SKNode()
    private var starsSpawnedForSize: CGSize = .zero

    // Key
    private var keyNode: SKShapeNode?
    private var userHasKey: Bool = false

    // Sichtfeld
    private let cropNode = SKCropNode()
    private let maskNode = SKShapeNode(circleOfRadius: 180)
    private let visionShadow = SKShapeNode() // subtiler innerer Schattenring
    private let effectsLayer = SKNode()      // Layer für Effekte (Ripple/Dust)
    private let echoLayer = SKNode()         // Layer für Echo-Animationen
    private var chargeNode: SKShapeNode?     // Auflade-Ring
    private let overlayLayer = SKNode()      // Nicht gecroppt: über dem Hintergrund für epische Effekte

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
        // Background layer (drawn behind everything)
        bgLayer.zPosition = -10000
        addChild(bgLayer)
        setupOuterBackground()

        // Add starfield layers behind crop/world
        starsFar.zPosition = -9999
        starsNear.zPosition = -9998
        bgLayer.addChild(starsFar)
        bgLayer.addChild(starsNear)

        addChild(cropNode)
        cropNode.addChild(worldNode)

        maskNode.fillColor = .white
        maskNode.strokeColor = .clear
        cropNode.maskNode = maskNode

        // Effekte-Layer wird innerhalb des Crops geclipped
        effectsLayer.zPosition = 900
        cropNode.addChild(effectsLayer)

        // Echo-Layer über anderen Effekten
        echoLayer.zPosition = 960
        cropNode.addChild(echoLayer)

        // Overlay-Layer über allem, nicht gecroppt
        overlayLayer.zPosition = 5000
        addChild(overlayLayer)

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupWorld()
        addBackground()
        buildMazeAndWalls()
        setupArrowAtStart()
        setupVisionShadow()
        setupAmbientDust()
        spawnKey()
        setupCamera()
        setupHaptics()
        updateCameraConstraints()
        // Spawn stars after camera is available (size-aware)
        setupParallaxStars()
    }


    override func didChangeSize(_ oldSize: CGSize) {
        updateCameraConstraints()
        updateOuterBackgroundFrame()
        setupParallaxStars()
    }

    override func update(_ currentTime: TimeInterval) {
        maskNode.position = arrow.position
        visionShadow.position = arrow.position // Schattenring folgt dem Maskenmittelpunkt
        // Echo-Layer positioniert sich auf die gleiche Weltposition wie der Pfeil
        echoLayer.position = worldNode.convert(arrow.position, to: cropNode)
        
        // Animate background shader
        if bgStartTime == 0 { bgStartTime = currentTime }
        let t = Float(currentTime - bgStartTime)
        if let shader = bgShader {
            shader.uniformNamed("u_time")?.floatValue = t
            // Center stays at screen center -> 0.5, 0.5
        }
        // keep background aligned with camera
        if let cam = cam, let bg = outerBG { bg.position = cam.position }
        // Parallax starfield follows camera subtly
        if let cam = cam {
            let px = cam.position.x
            let py = cam.position.y
            starsFar.position = CGPoint(x: px * 0.04, y: py * 0.04)
            starsNear.position = CGPoint(x: px * 0.08, y: py * 0.08)
        }

        checkKeyProximity()
    }
    
    private var nearKeyTask: Task<Void, Never>? = nil
    private var isNearKey: Bool = false

    private func checkKeyProximity() {
        let near = keyDistanceInCells() == 1 && !userHasKey

        if near && !isNearKey {
            isNearKey = true
            startNearKeyVibration()
        } else if !near && isNearKey {
            isNearKey = false
            stopNearKeyVibration()
        }
    }

    private func startNearKeyVibration() {
        nearKeyTask?.cancel()
        nearKeyTask = Task {
            while !Task.isCancelled {
                hapticImpact(duration: 0.05, intensity: 0.3, sharpness: 0.2)
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 Sek Abstand
            }
        }
    }

    private func stopNearKeyVibration() {
        nearKeyTask?.cancel()
        nearKeyTask = nil
    }
    

    // MARK: - Hintergrund
    private func addBackground() {
        let bg = SKSpriteNode(imageNamed: "floor") // Bild in Assets hinzufügen
        bg.size = worldRect.size
        bg.position = CGPoint(x: 0, y: 0)
        bg.zPosition = -100
        worldNode.addChild(bg)   // <- statt addChild(self), ins worldNode
    }

    // Outer background (outside vision circle)
    private func setupOuterBackground() {
        guard let view = self.view else { return }
        let visibleW = view.bounds.width * cameraZoom
        let visibleH = view.bounds.height * cameraZoom
        let size = CGSize(width: visibleW + 40, height: visibleH + 40) // slight bleed

        // Richer aurora-like gradient with gentle swirl, bands and pulse
        let src = """
        vec3 hsv2rgb(vec3 c){
            vec3 p = abs(fract(c.xxx + vec3(0.0, 0.6666667, 0.3333333))*6.0 - 3.0);
            return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
        }
        void main() {
            vec2 uv = v_tex_coord; // 0..1
            vec2 center = vec2(0.5, 0.5);
            vec2 p = uv - center;
            float t = u_time;

            // gentle global rotation
            float angRot = t * 0.04;
            float cs = cos(angRot), sn = sin(angRot);
            mat2 R = mat2(cs, -sn, sn, cs);
            p = R * p;
            uv = p + center;

            float r = length(p);
            float ang = atan(p.y, p.x);

            // soft swirl depending on radius
            float swirl = 0.08 * sin(6.0 * r - t * 0.8);
            ang += swirl;
            vec2 pr = vec2(cos(ang), sin(ang)) * r;

            // Base aurora palette driven by time and angle
            float g = smoothstep(0.98, 0.18, r);
            float hue = 0.58 + 0.08 * sin(t * 0.12) + 0.05 * sin(ang * 3.0 + t * 0.3);
            float sat = 0.40 + 0.25 * sin(t * 0.07 + 2.0);
            float val = 0.18 + 0.45 * g;
            vec3 base = hsv2rgb(vec3(hue, clamp(sat, 0.0, 1.0), clamp(val, 0.0, 1.0)));

            // Animated soft bands
            float band1 = sin((pr.x * 3.8 + pr.y * 4.2) * 3.14159 + t * 0.55) * 0.06;
            float band2 = sin((pr.x * -6.2 + pr.y * 5.4) * 3.14159 - t * 0.32) * 0.045;
            float band3 = sin((pr.x * 2.4 - pr.y * 3.7) * 3.14159 + t * 0.18) * 0.03;
            vec3 col = base + (band1 + band2 + band3);

            // Gentle radial pulse and a faint ring
            float pulse = 0.03 * sin(6.28318 * (r * 1.0 - t * 0.12));
            float ring = smoothstep(0.36, 0.34, r) - smoothstep(0.44, 0.42, r);
            col += vec3(pulse) + vec3(0.08) * ring;

            // Very subtle grain to avoid flat areas
            float n = fract(sin(dot(uv, vec2(12.9898,78.233)) + t * 0.1) * 43758.5453);
            col += (n - 0.5) * 0.02;

            // Vignette at edges
            float vig = smoothstep(1.15, 0.64, r);
            col *= vec3(vig);

            gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
        }
        """
        let shader = SKShader(source: src, uniforms: [
            SKUniform(name: "u_time", float: 0)
        ])
        bgShader = shader

        let node = SKSpriteNode(color: .black, size: size)
        node.shader = shader
        node.zPosition = -10000
        node.alpha = 1.0
        node.position = cam?.position ?? .zero
        outerBG = node
        bgLayer.removeAllChildren()
        bgLayer.addChild(node)
        
        backgroundColor = .black // fallback color
    }

    private func updateOuterBackgroundFrame() {
        guard let view = self.view, let bg = outerBG else { return }
        let visibleW = view.bounds.width * cam.xScale
        let visibleH = view.bounds.height * cam.yScale
        bg.size = CGSize(width: visibleW + 40, height: visibleH + 40)
        if let cam = cam { bg.position = cam.position }
    }

    // New: create and update a parallax starfield outside the vision circle
    private func setupParallaxStars() {
        guard let view = self.view, cam != nil else { return }
        
        // Baseline: what the viewport would have spawned (for density reference)
        let visibleW = view.bounds.width * cam.xScale
        let visibleH = view.bounds.height * cam.yScale
        let pad: CGFloat = 220
        let baselineAreaW = visibleW + pad * 2
        let baselineAreaH = visibleH + pad * 2
        let baselineArea = max(1.0, baselineAreaW * baselineAreaH)

        // Target: spawn across the entire map (worldRect) with a bit of bleed
        let mapAreaW = worldRect.width + pad * 2
        let mapAreaH = worldRect.height + pad * 2
        let mapArea = max(1.0, mapAreaW * mapAreaH)

        let targetSize = CGSize(width: worldRect.width, height: worldRect.height)
        // Avoid re-spawn if map size hasn't changed much
        if abs(targetSize.width - starsSpawnedForSize.width) < 10 && abs(targetSize.height - starsSpawnedForSize.height) < 10 {
            return
        }
        starsSpawnedForSize = targetSize

        // Clear old
        starsFar.removeAllActions()
        starsNear.removeAllActions()
        starsFar.removeAllChildren()
        starsNear.removeAllChildren()

        // Density scaling to keep roughly the same look across the full map
        let areaRatio = CGFloat(mapArea / baselineArea)
        let baseFar = 120
        let baseNear = 60
        let scaledFar = Int((CGFloat(baseFar) * areaRatio).rounded())
        let scaledNear = Int((CGFloat(baseNear) * areaRatio).rounded())
        // Safety caps to avoid extreme node counts on very large maps
        let farCount = min(max(scaledFar, baseFar), 2200)
        let nearCount = min(max(scaledNear, baseNear), 1200)

        // Spawn across an area larger than the full map, so panning never shows edges
        let area = CGSize(width: mapAreaW, height: mapAreaH)
        spawnStars(count: farCount, area: area, into: starsFar, radiusRange: 0.6...1.4, alpha: 0.7, twinkleRange: 1.2...2.2, drift: 6)
        spawnStars(count: nearCount, area: area, into: starsNear, radiusRange: 1.0...2.4, alpha: 0.9, twinkleRange: 0.8...1.6, drift: 10)
    }

    private func spawnStars(count: Int,
                            area: CGSize,
                            into container: SKNode,
                            radiusRange: ClosedRange<CGFloat>,
                            alpha: CGFloat,
                            twinkleRange: ClosedRange<TimeInterval>,
                            drift: CGFloat) {
        let halfW = area.width / 2
        let halfH = area.height / 2
        for _ in 0..<count {
            let r = CGFloat.random(in: radiusRange)
            let s = SKShapeNode(circleOfRadius: r)
            s.fillColor = .white
            s.strokeColor = .clear
            s.alpha = alpha * CGFloat.random(in: 0.5...1.0)
            s.blendMode = .add
            s.position = CGPoint(x: CGFloat.random(in: -halfW...halfW),
                                 y: CGFloat.random(in: -halfH...halfH))
            container.addChild(s)

            // Twinkle animation
            let t1 = TimeInterval.random(in: twinkleRange)
            let t2 = TimeInterval.random(in: twinkleRange)
            let wait = SKAction.wait(forDuration: TimeInterval.random(in: 0.0...1.0))
            let twinkle = SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: s.alpha * 0.3, duration: t1 * 0.5),
                SKAction.fadeAlpha(to: s.alpha, duration: t2 * 0.5)
            ]))
            s.run(SKAction.sequence([wait, twinkle]))

            // Slow drift
            let dx = CGFloat.random(in: -drift...drift)
            let dy = CGFloat.random(in: -drift...drift)
            let move = SKAction.moveBy(x: dx, y: dy, duration: TimeInterval.random(in: 3.0...6.0))
            move.timingMode = .easeInEaseOut
            s.run(SKAction.repeatForever(SKAction.sequence([move, move.reversed()])))
        }
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
        // Configure player sprite size relative to cell size
        let s = max(28, min(cellSize * 0.6, 72))
        arrow.size = CGSize(width: s, height: s)
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

    // MARK: - Vision Shadow
    private func setupVisionShadow() {
        // Mask-Radius aus Pfad ableiten (Fallback: 180)
        let radius: CGFloat = {
            if let path = maskNode.path { return path.boundingBox.width * 0.5 }
            return 180
        }()
        let circleRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        let circlePath = CGPath(ellipseIn: circleRect, transform: nil)

        visionShadow.path = circlePath
        visionShadow.fillColor = .clear
        visionShadow.strokeColor = .black
        visionShadow.alpha = 0.28
        visionShadow.lineWidth = 28
        visionShadow.glowWidth = 6
        visionShadow.isAntialiased = true
        visionShadow.zPosition = 1000

        visionShadow.position = arrow.position
        cropNode.addChild(visionShadow)
    }

    // MARK: - Camera
    private func setupCamera() {
        cam = SKCameraNode()
        camera = cam
        addChild(cam)
        cam.setScale(cameraZoom)
        cam.position = arrow.position
        updateOuterBackgroundFrame()
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

        updateOuterBackgroundFrame()
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
            // tiny movement haptic
            hapticImpact(duration: 0.2, intensity: 0.15, sharpness: 0.2)
            
            let (nr, nc) = nextCell(from: playerRC.r, playerRC.c, dir: dir)
            playerRC = (nr, nc)
            let target = centerOfCell(nr, nc)

            // Trail-Ghost am Startpunkt
            spawnArrowGhost(at: arrow.position, angle: arrow.zRotation)

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
            cameraShake(intensity: 6, duration: 0.12)
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
            spawnSparkles(at: arrow.position)
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
                // kurzer Flash
                let oldColor = outline.strokeColor
                outline.strokeColor = .white
                outline.glowWidth = 4
                outline.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.12),
                    SKAction.run {
                        outline.strokeColor = oldColor
                        outline.glowWidth = 0
                    },
                    SKAction.wait(forDuration: 0.38),
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

        // Spawn-Funken
        spawnSparkles(at: keyPos)
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
        if let p = touchStart { spawnRipple(at: p) }
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
        // Start: Aufladeanimation + langer Haptik-Impuls
        startEchoCharge()
        hapticImpact(duration: 1.0, intensity: 0.5, sharpness: 0.5)

        // Dauer der Aufladung
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // Ende der Aufladung visualisieren
        stopEchoCharge()
        ejectChargeBurst()                 // Ring wird aus dem Sichtfeld geschleudert (über Overlay)
        spawnIncomingOrbs(count: 28)       // Viele kleine Kreise kommen von außen ins Sichtfeld

        let baseDelay: UInt64 = 150_000_000
        let growthFactor: Double = 1.15
        let count = keyDistanceInCells()

        var currentDelay = Double(baseDelay)

        // Zwischenimpulse: Wellen, die zurückkommen
        for i in 0..<count {
            try? Task.checkCancellation()
            print("Index \(i)")
            hapticImpact(duration: 0.1, intensity: 0.6, sharpness: 0.6)
            spawnEchoWave()
            try? await Task.sleep(nanoseconds: UInt64(currentDelay))
            currentDelay *= growthFactor
        }

        // Doppelimpuls am Ende: Endanimation (keine Rückkehrwelle)
        for _ in 0..<2 {
            try? Task.checkCancellation()
            hapticImpact(duration: 0.1, intensity: 0.9, sharpness: 0.9)
            spawnEndFlash()
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private func onHoldEnd() {
        holdTask?.cancel()
        holdTask = nil
        clearEchoVisuals()
    }

    private func clearEchoVisuals() {
        stopEchoCharge()
        echoLayer.removeAllActions()
        echoLayer.removeAllChildren()
        overlayLayer.removeAllActions()
        overlayLayer.removeAllChildren()
    }

    // MARK: - Echo Visuals
    private func startEchoCharge() {
        // vorhandene Charge entfernen
        chargeNode?.removeAllActions()
        chargeNode?.removeFromParent()

        let r: CGFloat = 36
        let ring = SKShapeNode(circleOfRadius: r)
        ring.position = .zero
        ring.fillColor = .clear
        ring.strokeColor = .white
        ring.lineWidth = 3
        ring.alpha = 0.25
        ring.glowWidth = 3
        ring.zPosition = 0
        echoLayer.addChild(ring)
        chargeNode = ring

        // Rotation + langsames Aufhellen
        let rotate = SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 1.2))
        let brighten = SKAction.fadeAlpha(to: 0.55, duration: 0.6)
        let thicken = SKAction.customAction(withDuration: 0.6) { node, t in
            if let s = node as? SKShapeNode { s.lineWidth = 3 + 4 * (t / 0.6) }
        }
        ring.run(SKAction.group([rotate, brighten, thicken]))

        // pulsierender innerer Kern
        let core = SKShapeNode(circleOfRadius: 10)
        core.fillColor = .white
        core.strokeColor = .clear
        core.alpha = 0.0
        core.zPosition = -1
        echoLayer.addChild(core)
        let corePulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.35, duration: 0.4),
            SKAction.fadeAlpha(to: 0.1, duration: 0.4)
        ]))
        core.run(corePulse, withKey: "corePulse")
        core.name = "echoCore"
    }

    private func stopEchoCharge() {
        if let ring = chargeNode {
            ring.removeAllActions()
            let fade = SKAction.fadeOut(withDuration: 0.2)
            ring.run(SKAction.sequence([fade, .removeFromParent()]))
            chargeNode = nil
        }
        if let core = echoLayer.childNode(withName: "echoCore") {
            core.removeAllActions()
            core.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.15), .removeFromParent()
            ]))
        }
    }

    private func spawnEchoWave() {
        // Mehrteilig: mehrere Arc-Segmente rotieren und ziehen nach innen
        let baseR = min(visionRadius, 180)
        let arcCount = Int.random(in: 3...4)
        let baseAngle = CGFloat.random(in: 0..<(2 * .pi))
        for i in 0..<arcCount {
            let span = CGFloat.random(in: .pi/6 ... .pi/3) // 30°–60°
            let start = baseAngle + CGFloat(i) * (2 * .pi / CGFloat(arcCount))
            let end = start + span
            let path = makeArcPath(radius: baseR, startAngle: start, endAngle: end)

            let arc = SKShapeNode(path: path)
            arc.position = .zero
            arc.strokeColor = SKColor.white
            arc.fillColor = SKColor.clear
            arc.lineWidth = 3
            arc.glowWidth = 4
            arc.alpha = 0.0
            arc.zPosition = 4
            echoLayer.addChild(arc)

            // Animation: auftauchen, nach innen skalieren, rotieren und ausblenden
            let appear = SKAction.fadeAlpha(to: 0.7, duration: 0.06)
            let inward = SKAction.scale(to: 0.35, duration: 0.28)
            inward.timingMode = SKActionTimingMode.easeIn
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -1.2...1.2), duration: 0.28)
            let fade = SKAction.fadeOut(withDuration: 0.2)

            let delay = SKAction.wait(forDuration: TimeInterval(0.02 * Double(i)))
            arc.run(SKAction.sequence([
                delay,
                appear,
                SKAction.group([inward, spin, SKAction.sequence([SKAction.wait(forDuration: 0.12), fade])]),
                .removeFromParent()
            ]))
        }

        // kleiner Kern-Ping zur Mitte
        let ping = SKShapeNode(circleOfRadius: 8)
        ping.position = .zero
        ping.fillColor = SKColor.white
        ping.strokeColor = SKColor.clear
        ping.alpha = 0.0
        ping.zPosition = 6
        echoLayer.addChild(ping)
        let grow = SKAction.scale(to: 1.8, duration: 0.18)
        grow.timingMode = SKActionTimingMode.easeOut
        ping.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.06),
            SKAction.group([grow, SKAction.fadeOut(withDuration: 0.18)]),
            .removeFromParent()
        ]))
    }

    private func spawnEndFlash() {
        // Epischer Finish-Blast im Overlay: elliptischer Shock + Shards + Halo
        let center = self.convert(arrow.position, from: worldNode)
        let r = visionRadius

        // Elliptischer Shockwave-Ring
        let ring = SKShapeNode(circleOfRadius: max(r * 0.85, 36))
        ring.position = center
        ring.fillColor = SKColor.clear
        ring.strokeColor = SKColor.white
        ring.lineWidth = 5
        ring.glowWidth = 10
        ring.alpha = 0.9
        ring.zPosition = 20
        overlayLayer.addChild(ring)

        let sx: CGFloat = CGFloat.random(in: 1.5...2.1)
        let sy: CGFloat = CGFloat.random(in: 0.6...0.9)
        ring.xScale = 0.9
        ring.yScale = 0.9
        let scaleX = SKAction.scaleX(to: sx, duration: 0.16)
        let scaleY = SKAction.scaleY(to: sy, duration: 0.16)
        let fade = SKAction.fadeOut(withDuration: 0.16)
        let spin = SKAction.rotate(byAngle: CGFloat.random(in: -0.5...0.5), duration: 0.16)
        let group = SKAction.group([scaleX, scaleY, fade, spin])
        ring.run(SKAction.sequence([group, .removeFromParent()]))

        // Shards (Dreiecke) die nach außen fliegen und rotieren
        let shardCount = 12
        for _ in 0..<shardCount {
            let tri = SKShapeNode(path: makeTrianglePath(size: CGFloat.random(in: 8...14)))
            tri.position = center
            tri.fillColor = SKColor.white
            tri.strokeColor = SKColor.clear
            tri.alpha = 0.95
            tri.zPosition = 22
            overlayLayer.addChild(tri)

            let ang = CGFloat.random(in: 0..<(2 * .pi))
            let dist = CGFloat.random(in: r * 0.25 ... r * 0.6)
            let dx = cos(ang) * dist
            let dy = sin(ang) * dist
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.28)
            move.timingMode = SKActionTimingMode.easeOut
            let rot = SKAction.rotate(byAngle: CGFloat.random(in: -2.5...2.5), duration: 0.28)
            let fadeShard = SKAction.fadeOut(withDuration: 0.28)
            tri.run(SKAction.sequence([SKAction.group([move, rot, fadeShard]), .removeFromParent()]))
        }

        // Leucht-Halo
        let halo = SKShapeNode(circleOfRadius: r * 1.1)
        halo.position = center
        halo.fillColor = SKColor.clear
        halo.strokeColor = SKColor.white
        halo.glowWidth = 18
        halo.lineWidth = 2
        halo.alpha = 0.25
        halo.zPosition = 18
        overlayLayer.addChild(halo)
        halo.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.25),
                SKAction.scale(to: 1.25, duration: 0.25)
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Path helpers
    private func makeArcPath(radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addArc(center: CGPoint.zero, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return p
    }

    private func makeTrianglePath(size: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: size))
        p.addLine(to: CGPoint(x: -size * 0.6, y: -size * 0.6))
        p.addLine(to: CGPoint(x: size * 0.6, y: -size * 0.6))
        p.closeSubpath()
        return p
    }

    // MARK: - Epic overlay effects (helpers)
    private var visionRadius: CGFloat {
        if let p = maskNode.path { return p.boundingBox.width * 0.5 }
        return 180
    }

    private func ejectChargeBurst() {
        // Zentrum im Szenen-Koordinatensystem
        let center = self.convert(arrow.position, from: worldNode)
        let r = visionRadius

        // Weißer Expand-Ring, der über den Sichtkreis hinaus schießt
        let ring = SKShapeNode(circleOfRadius: max(r * 0.92, 40))
        ring.position = center
        ring.fillColor = SKColor.clear
        ring.strokeColor = SKColor.white
        ring.lineWidth = 6
        ring.alpha = 0.6
        ring.glowWidth = 8
        ring.zPosition = 10
        overlayLayer.addChild(ring)

        let expand = SKAction.scale(to: 1.65, duration: 0.38)
        expand.timingMode = SKActionTimingMode.easeOut
        let fade = SKAction.fadeOut(withDuration: 0.38)
        let spin = SKAction.rotate(byAngle: .pi * 0.6, duration: 0.38)
        ring.run(SKAction.sequence([SKAction.group([expand, fade, spin]), .removeFromParent()]))

        // Radiale Outburst-Partikel (kleine Kreise, die nach außen fliegen)
        let count = 18
        for _ in 0..<count {
            let dotR: CGFloat = CGFloat.random(in: 2.0...3.2)
            let dot = SKShapeNode(circleOfRadius: dotR)
            dot.position = point(onCircleWithRadius: r * 1.0 + CGFloat.random(in: -6...6), around: center)
            dot.fillColor = SKColor.white
            dot.strokeColor = SKColor.clear
            dot.alpha = 0.9
            dot.zPosition = 12
            overlayLayer.addChild(dot)

            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let dist = CGFloat.random(in: r * 0.2 ... r * 0.6)
            let dx = cos(angle) * dist
            let dy = sin(angle) * dist
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.4)
            move.timingMode = SKActionTimingMode.easeOut
            let fadeDot = SKAction.fadeOut(withDuration: 0.4)
            dot.run(SKAction.sequence([SKAction.group([move, fadeDot]), SKAction.removeFromParent()]))
        }

        // Kurzer Screen‑Flash für mehr Wucht
        spawnScreenFlash(intensity: 0.18, duration: 0.18)
    }

    private func spawnIncomingOrbs(count: Int) {
        let center = self.convert(arrow.position, from: worldNode)
        let r = visionRadius
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let startDist = r + CGFloat.random(in: 30...160)
            let endDist = CGFloat.random(in: r * 0.2 ... r * 0.75)
            let start = CGPoint(x: center.x + cos(angle) * startDist,
                                y: center.y + sin(angle) * startDist)
            let end = CGPoint(x: center.x + cos(angle) * endDist,
                              y: center.y + sin(angle) * endDist)

            let orbR: CGFloat = CGFloat.random(in: 2.0...3.4)
            let orb = SKShapeNode(circleOfRadius: orbR)
            orb.position = start
            orb.fillColor = SKColor.white
            orb.strokeColor = SKColor.clear
            orb.alpha = 0.0
            orb.zPosition = 8
            overlayLayer.addChild(orb)

            let dur = TimeInterval(CGFloat.random(in: 0.38...0.85))
            let move = SKAction.move(to: end, duration: dur)
            move.timingMode = SKActionTimingMode.easeIn
            let fadeIn = SKAction.fadeAlpha(to: 0.65, duration: dur * 0.4)
            let fadeOut = SKAction.fadeOut(withDuration: dur * 0.6)
            orb.run(SKAction.sequence([SKAction.group([move, SKAction.sequence([fadeIn, fadeOut])]), SKAction.removeFromParent()]))
        }
    }

    private func spawnScreenFlash(intensity: CGFloat, duration: TimeInterval) {
        guard let view = self.view else { return }
        let size = CGSize(width: view.bounds.width * cam.xScale, height: view.bounds.height * cam.yScale)
        let rect = SKShapeNode(rectOf: size)
        rect.position = cam.position
        rect.fillColor = SKColor.white
        rect.strokeColor = SKColor.clear
        rect.alpha = intensity
        rect.zPosition = 100
        overlayLayer.addChild(rect)
        rect.run(SKAction.sequence([SKAction.fadeOut(withDuration: duration), SKAction.removeFromParent()]))
    }

    private func point(onCircleWithRadius radius: CGFloat, around center: CGPoint) -> CGPoint {
        let angle = CGFloat.random(in: 0..<(2 * .pi))
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
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

// Re-add missing helpers inside class scope
extension SwipeScene {
    // Ambient dust inside crop
    fileprivate func setupAmbientDust() {
        let spawn = SKAction.run { [weak self] in
            guard let self = self else { return }
            let count = Int.random(in: 1...2)
            for _ in 0..<count { self.spawnDustDot() }
        }
        let wait = SKAction.wait(forDuration: 0.35, withRange: 0.2)
        effectsLayer.run(SKAction.repeatForever(SKAction.sequence([spawn, wait])))
    }

    fileprivate func spawnDustDot() {
        let radius: CGFloat = CGFloat.random(in: 1.5...2.8)
        let dot = SKShapeNode(circleOfRadius: radius)
        let maxR: CGFloat = 140
        let a = CGFloat.random(in: 0..<(2 * .pi))
        let r = sqrt(CGFloat.random(in: 0...1)) * maxR
        let pos = CGPoint(x: arrow.position.x + cos(a) * r, y: arrow.position.y + sin(a) * r)
        dot.position = pos
        dot.fillColor = .white.withAlphaComponent(0.12)
        dot.strokeColor = .clear
        dot.zPosition = 1
        effectsLayer.addChild(dot)
        let drift = CGVector(dx: CGFloat.random(in: -8...8), dy: CGFloat.random(in: 6...16))
        let move = SKAction.move(by: drift, duration: 1.6)
        let fade = SKAction.fadeOut(withDuration: 1.6)
        dot.run(SKAction.sequence([SKAction.group([move, fade]), SKAction.removeFromParent()]))
    }

    // Arrow ghost trail (now uses the player sprite texture)
    fileprivate func spawnArrowGhost(at position: CGPoint, angle: CGFloat) {
        guard let texture = arrow.texture else { return }
        let ghost = SKSpriteNode(texture: texture)
        ghost.size = arrow.size
        ghost.position = position
        ghost.zRotation = angle
        ghost.zPosition = arrow.zPosition - 1
        ghost.alpha = 0.28
        worldNode.addChild(ghost)
        let fade = SKAction.fadeOut(withDuration: 0.25)
        let scale = SKAction.scale(to: 0.96, duration: 0.25)
        ghost.run(SKAction.sequence([SKAction.group([fade, scale]), SKAction.removeFromParent()]))
    }

    // Tap ripple inside crop
    fileprivate func spawnRipple(at p: CGPoint) {
        let ripple = SKShapeNode(circleOfRadius: 6)
        ripple.position = p
        ripple.fillColor = .clear
        ripple.strokeColor = .white
        ripple.lineWidth = 2
        ripple.alpha = 0.35
        ripple.zPosition = 950
        effectsLayer.addChild(ripple)
        let grow = SKAction.scale(to: 4.0, duration: 0.35)
        let fade = SKAction.fadeOut(withDuration: 0.35)
        ripple.run(SKAction.sequence([SKAction.group([grow, fade]), SKAction.removeFromParent()]))
    }

    // Subtle world shake
    fileprivate func cameraShake(intensity: CGFloat, duration: TimeInterval) {
        let dx = intensity, dy = intensity
        let left = SKAction.moveBy(x: -dx, y: 0, duration: duration * 0.2)
        let up = SKAction.moveBy(x: 0, y: dy, duration: duration * 0.2)
        let right = SKAction.moveBy(x: dx, y: 0, duration: duration * 0.2)
        let down = SKAction.moveBy(x: 0, y: -dy, duration: duration * 0.2)
        let back = SKAction.moveTo(x: 0, duration: duration * 0.2)
        let backY = SKAction.moveTo(y: 0, duration: duration * 0.2)
        worldNode.run(SKAction.sequence([left, up, right, down, SKAction.group([back, backY])]))
    }

    // Sparkles at events
    fileprivate func spawnSparkles(at p: CGPoint) {
        let n = 10
        for _ in 0..<n {
            let r: CGFloat = CGFloat.random(in: 1.8...3.0)
            let s = SKShapeNode(circleOfRadius: r)
            s.position = p
            s.fillColor = .yellow
            s.strokeColor = .white
            s.lineWidth = 0.5
            s.alpha = 0.9
            s.zPosition = 200
            worldNode.addChild(s)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let dist = CGFloat.random(in: 20...60)
            let dx = cos(angle) * dist
            let dy = sin(angle) * dist
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.35)
            move.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: 0.35)
            s.run(SKAction.sequence([SKAction.group([move, fade]), SKAction.removeFromParent()]))
        }
    }

    // Haptic+VFX on key pickup
    fileprivate func keyPickupFeedback() {
        guard haptics != nil else { return }
        Task { @MainActor in
            hapticImpact(duration: 0.08, intensity: 1.0, sharpness: 0.9)
            try? await Task.sleep(nanoseconds: 100_000_000)
            hapticImpact(duration: 0.05, intensity: 0.7, sharpness: 0.5)
            try? await Task.sleep(nanoseconds: 80_000_000)
            hapticImpact(duration: 0.05, intensity: 0.6, sharpness: 0.4)
            try? await Task.sleep(nanoseconds: 150_000_000)
            hapticImpact(duration: 0.1, intensity: 0.3, sharpness: 0.2)
            SoundManager.shared.play("level-finished")
        }
    }
}
