import Foundation

// Logical maze model used by MazeGenerator and (optionally) rendering.
struct Maze {
    let cols: Int
    let rows: Int
    var grid: [CellWall]

    init(cols: Int, rows: Int) {
        precondition(cols > 0 && rows > 0, "Maze dimensions must be positive")
        self.cols = cols
        self.rows = rows
        self.grid = Array(repeating: [], count: cols * rows)
    }

    /// Convert (column, row) to linear index for the backing array.
    @inline(__always)
    func index(_ c: Int, _ r: Int) -> Int { r * cols + c }

    /// Bounds check helper if needed by callers.
    func inBounds(_ c: Int, _ r: Int) -> Bool {
        (0..<cols).contains(c) && (0..<rows).contains(r)
    }
}

/// Bitmask for walls around a cell.
struct CellWall: OptionSet {
    let rawValue: UInt8

    init(rawValue: UInt8) { self.rawValue = rawValue }

    static let wallUp    = CellWall(rawValue: 1 << 0)
    static let wallRight = CellWall(rawValue: 1 << 1)
    static let wallDown  = CellWall(rawValue: 1 << 2)
    static let wallLeft  = CellWall(rawValue: 1 << 3)
}
