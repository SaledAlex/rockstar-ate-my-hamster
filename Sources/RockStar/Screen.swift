import CoreGraphics
import Foundation

/// ZX Spectrum style display: 256x192 1bpp bitmap plus 32x24 colour attributes.
struct Screen {
    static let width = 256, height = 192, cols = 32, rows = 24

    /// Spectrum palette (normal, bright), RGB.
    static let palette: [[UInt32]] = [
        [0x000000, 0x0000D7, 0xD70000, 0xD700D7, 0x00D700, 0x00D7D7, 0xD7D700, 0xD7D7D7],
        [0x000000, 0x0000FF, 0xFF0000, 0xFF00FF, 0x00FF00, 0x00FFFF, 0xFFFF00, 0xFFFFFF],
    ]

    var pixels = [Bool](repeating: false, count: width * height)
    /// Attribute byte per 8x8 cell, Spectrum layout: flash<<7 | bright<<6 | paper<<3 | ink.
    var attrs = [UInt8](repeating: 0x38, count: cols * rows)
    /// Character last printed in each cell (nil once anything else draws there).
    /// Enhanced mode re-renders these with a modern font.
    var textCells = [Character?](repeating: nil, count: cols * rows)

    mutating func clear(attr: UInt8 = 0x07) {
        pixels = [Bool](repeating: false, count: Screen.width * Screen.height)
        attrs = [UInt8](repeating: attr, count: Screen.cols * Screen.rows)
        textCells = [Character?](repeating: nil, count: Screen.cols * Screen.rows)
    }

    mutating func set(_ x: Int, _ y: Int, _ on: Bool) {
        guard x >= 0, y >= 0, x < Screen.width, y < Screen.height else { return }
        pixels[y * Screen.width + x] = on
        textCells[(y >> 3) * Screen.cols + (x >> 3)] = nil
    }

    mutating func fillAttr(col: Int, row: Int, width: Int, height: Int, attr: UInt8) {
        for r in row..<min(row + height, Screen.rows) {
            for c in col..<min(col + width, Screen.cols) where c >= 0 && r >= 0 {
                attrs[r * Screen.cols + c] = attr
            }
        }
    }

    mutating func clearRect(col: Int, row: Int, width: Int, height: Int) {
        for y in (row * 8)..<min((row + height) * 8, Screen.height) {
            for x in (col * 8)..<min((col + width) * 8, Screen.width) {
                pixels[y * Screen.width + x] = false
            }
        }
        for r in max(row, 0)..<min(row + height, Screen.rows) {
            for c in max(col, 0)..<min(col + width, Screen.cols) { textCells[r * Screen.cols + c] = nil }
        }
    }

    /// Draw one character cell like $AA60: blank row, 6 glyph rows, blank row.
    mutating func drawChar(_ ch: Character, col: Int, row: Int, font: Font) {
        let glyph = font.glyph(ch)
        for r in 0..<8 {
            let bits: UInt8 = (r >= 1 && r <= 6) ? glyph[r - 1] : 0
            for b in 0..<8 {
                set(col * 8 + b, row * 8 + r, bits & (0x80 >> b) != 0)
            }
        }
        if col >= 0, row >= 0, col < Screen.cols, row < Screen.rows, ch != " " {
            textCells[row * Screen.cols + col] = ch
        }
    }

    mutating func drawText(_ s: String, col: Int, row: Int, font: Font) {
        for (i, ch) in s.enumerated() { drawChar(ch, col: col + i, row: row, font: font) }
    }

    /// Blit a 1bpp bitmap (row-major, `bytesWide` bytes per row) at pixel position.
    mutating func blit(_ data: [UInt8], bytesWide: Int, x: Int, y: Int) {
        let rows = data.count / bytesWide
        for r in 0..<rows {
            for xb in 0..<bytesWide {
                let byte = data[r * bytesWide + xb]
                for b in 0..<8 { set(x + xb * 8 + b, y + r, byte & (0x80 >> b) != 0) }
            }
        }
    }

    func makeImage(flashPhase: Bool = false) -> CGImage? {
        var rgba = [UInt32](repeating: 0, count: Screen.width * Screen.height)
        for y in 0..<Screen.height {
            for x in 0..<Screen.width {
                let a = attrs[(y / 8) * Screen.cols + x / 8]
                let bright = Int((a >> 6) & 1)
                var ink = Int(a & 7), paper = Int((a >> 3) & 7)
                if a & 0x80 != 0 && flashPhase { swap(&ink, &paper) }
                let rgb = Screen.palette[bright][pixels[y * Screen.width + x] ? ink : paper]
                // Little-endian ARGB -> stored as BGRA bytes with premultipliedFirst.
                rgba[y * Screen.width + x] = 0xFF00_0000 | rgb
            }
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: Screen.width, height: Screen.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Screen.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

