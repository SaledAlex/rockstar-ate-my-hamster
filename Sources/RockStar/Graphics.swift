import Foundation

/// Original screen graphics, exported by tools/make_assets.py (`graphics.json`).
struct GraphicsData: Decodable {
    struct Entry: Decodable { let sprite: String; let y: Int; let col: Int; let mirror: Bool }
    struct Sprite: Decodable {
        let w: Int, h: Int, data: String
        var bytes: [UInt8] { hexBytes(data) }
    }
    /// `$8434` sprite lists: 0 masthead, 1 page-3 girl, 2 status bar + bubble,
    /// 3-6 scenes, 7-10 phone in hand, 11-14 phone on desk, 15-18 / 19-22 bubble tails.
    let spriteLists: [[Entry]]
    let sprites: [String: Sprite]
    /// `$830F` attribute lists: [box id, attribute] pairs.
    let attrLists: [[[Int]]]
    /// `$AEB0` boxes: top, left, bottom, right (cells, bottom/right exclusive).
    let boxes: [[Int]]
    /// `$90B5` big font, 28 bytes (16x14) per char from $20 to $5A.
    let bigFont: String
    /// `$7C19` credits ticker text (title screen, `$7B9B`).
    let credits: String?
    /// Tape block CODE1 (SCREEN$), 6912 bytes.
    let loadingScreen: String
}

/// Cells the original draws with code in the limousine (`$A2EB`/`$7DD1`) and the
/// studio (`$A2E6`), captured by tools/make_scenes.py (`scenes.json`).
struct SceneLayers: Decodable {
    /// "flag-stars" -> "row,col" -> 8 bytes hex. flag = `$6239` (band seated in the limo).
    let limo: [String: [String: String]]
    /// "stars" -> cells.
    let studio: [String: [String: String]]
    /// `$A6AA`: bytes wide, rows, pixel y, column of the 4 limo head slices.
    let heads: [[Int]]
}

func hexBytes(_ s: String) -> [UInt8] {
    var out = [UInt8](); out.reserveCapacity(s.count / 2)
    var it = s.makeIterator()
    while let a = it.next(), let b = it.next() { out.append(UInt8(String([a, b]), radix: 16)!) }
    return out
}

extension Screen {
    /// `$7F13`: draw a sprite (direct store) at pixel row y, byte column x.
    /// Mirrored sprites are bit-reversed and drawn right-to-left from column x.
    mutating func drawSprite(_ sp: GraphicsData.Sprite, y: Int, col: Int, mirror: Bool) {
        let d = sp.bytes
        for r in 0..<sp.h {
            for xb in 0..<sp.w {
                var b = d[r * sp.w + xb]
                let c: Int
                if mirror {
                    var rev: UInt8 = 0
                    for k in 0..<8 where b & (1 << k) != 0 { rev |= 0x80 >> k }
                    b = rev; c = col - xb
                } else {
                    c = col + xb
                }
                guard c >= 0 && c < Screen.cols else { continue }
                for k in 0..<8 { set(c * 8 + k, y + r, b & (0x80 >> k) != 0) }
            }
        }
    }

    /// Overwrite whole character cells ("row,col" -> 8 bytes hex).
    mutating func applyCells(_ cells: [String: String]?) {
        for (k, v) in cells ?? [:] {
            let rc = k.split(separator: ",").compactMap { Int($0) }
            guard rc.count == 2 else { continue }
            for (i, b) in hexBytes(v).enumerated() {
                for bit in 0..<8 { set(rc[1] * 8 + bit, rc[0] * 8 + i, b & (0x80 >> bit) != 0) }
            }
        }
    }

    mutating func drawList(_ n: Int, _ g: GraphicsData) {
        guard n < g.spriteLists.count else { return }
        for e in g.spriteLists[n] {
            if let sp = g.sprites[e.sprite] { drawSprite(sp, y: e.y, col: e.col, mirror: e.mirror) }
        }
    }

    mutating func fillBox(_ box: Int, attr: UInt8, _ g: GraphicsData) {
        guard box < g.boxes.count else { return }
        let b = g.boxes[box]
        let bottom = min(b[2], Screen.rows), right = min(b[3], Screen.cols)
        guard bottom > b[0], right > b[1] else { return }
        fillAttr(col: b[1], row: b[0], width: right - b[1], height: bottom - b[0], attr: attr)
    }

    /// `$81BA`
    mutating func applyAttrList(_ n: Int, _ g: GraphicsData) {
        guard n < g.attrLists.count else { return }
        for pair in g.attrLists[n] { fillBox(pair[0], attr: UInt8(pair[1]), g) }
    }

    /// Big font (16x14), used for the date, headlines, stage names.
    mutating func drawBigChar(_ ch: Character, x: Int, y: Int, font: [UInt8]) {
        var code = Int(ch.asciiValue ?? 0x20)
        if code >= 0x61 && code <= 0x7A { code -= 0x20 }
        guard code >= 0x20 && code <= 0x5A else { return }
        let base = (code - 0x20) * 28
        for r in 0..<14 {
            for xb in 0..<2 {
                let b = font[base + r * 2 + xb]
                for k in 0..<8 { set(x + xb * 8 + k, y + r, b & (0x80 >> k) != 0) }
            }
        }
    }

    mutating func drawBigText(_ s: String, col: Int, row: Int, font: [UInt8]) {
        for (i, ch) in s.enumerated() { drawBigChar(ch, x: (col + 2 * i) * 8, y: row * 8 + 2, font: font) }  // $AA8D: y = row*8+2
    }

    /// Spectrum display file layout -> bitmap + attributes.
    mutating func loadSCR(_ data: [UInt8]) {
        guard data.count >= 6912 else { return }
        for y in 0..<Screen.height {
            let base = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
            for cx in 0..<Screen.cols {
                let b = data[base + cx]
                for k in 0..<8 { set(cx * 8 + k, y, b & (0x80 >> k) != 0) }
            }
        }
        attrs = Array(data[6144..<6912])
    }
}
