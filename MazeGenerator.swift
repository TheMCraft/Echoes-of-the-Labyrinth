import Foundation

/// Generates simple mazes compatible with GameScene expectations.
enum MazeGenerator {
    /// Returns a Maze with the specified size. If a seed is provided, use it for deterministic randomness.
    static func generate(cols: Int, rows: Int, seed: UInt64?) -> Maze {
        var maze = Maze(cols: cols, rows: rows)
        var rng = SeededGenerator(seed: seed ?? UInt64(Date().timeIntervalSince1970))

        // Start with outer border walls on all cells touching the edges
        for r in 0..<rows {
            for c in 0..<cols {
                var cell: CellWall = []
                if r == 0 { cell.insert(.wallUp) }
                if r == rows - 1 { cell.insert(.wallDown) }
                if c == 0 { cell.insert(.wallLeft) }
                if c == cols - 1 { cell.insert(.wallRight) }
                maze.grid[maze.index(c, r)] = cell
            }
        }

        // Carve a few random internal walls to make corridors. This is a very simple generator
        // but sufficient for the GameScene rendering and movement rules.
        let attempts = (cols * rows) / 2
        for _ in 0..<attempts {
            let c = Int.random(in: 1..<(cols-1), using: &rng)
            let r = Int.random(in: 1..<(rows-1), using: &rng)
            // randomly add a wall on one side of this internal cell
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: maze.grid[maze.index(c, r)].insert(.wallUp)
            case 1: maze.grid[maze.index(c, r)].insert(.wallRight)
            case 2: maze.grid[maze.index(c, r)].insert(.wallDown)
            default: maze.grid[maze.index(c, r)].insert(.wallLeft)
            }
        }

        return maze
    }
}

// MARK: - Deterministic RNG

/// A simple seeded generator backed by SplitMix64 for reproducibility.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
