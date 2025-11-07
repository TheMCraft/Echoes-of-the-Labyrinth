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

        // EXAKT denselben Shader-Code wie in SwipeScene.setupOuterBackground()
        let shader = SKShader(source: """
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
        """)
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
