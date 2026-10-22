import Foundation

/// The game's 6-row font (ASCII 0x20-0x7F), taken from $86A7 in the original.
struct Font {
    let data: [UInt8]

    func glyph(_ ch: Character) -> [UInt8] {
        var code = Int(ch.asciiValue ?? 0x3F)
        if ch == "£" { code = 0x60 }  // the original stores £ as `
        if code >= 0x61 && code <= 0x7A { code -= 0x20 }  // font has capitals only
        if code < 0x20 || code > 0x7F { code = 0x3F }
        let i = (code - 0x20) * 6
        return Array(data[i..<i + 6])
    }
}

/// One piece of a message, mirroring the reference types decoded at $A8DA.
enum MessagePart: Codable {
    case text(String)
    case random([String])
    case string(Int)
    case number(Int)

    private enum Keys: String, CodingKey { case t, v }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .t) {
        case "text": self = .text(try c.decode(String.self, forKey: .v))
        case "rand": self = .random(try c.decode([String].self, forKey: .v))
        case "str": self = .string(try c.decode(Int.self, forKey: .v))
        default: self = .number(try c.decode(Int.self, forKey: .v))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let s): try c.encode("text", forKey: .t); try c.encode(s, forKey: .v)
        case .random(let a): try c.encode("rand", forKey: .t); try c.encode(a, forKey: .v)
        case .string(let n): try c.encode("str", forKey: .t); try c.encode(n, forKey: .v)
        case .number(let n): try c.encode("num", forKey: .t); try c.encode(n, forKey: .v)
        }
    }
}

struct RockStarRecord: Codable {
    let name: String
    let stats: [UInt8]
    let portrait: String

    /// 40x48 1bpp bitmap, 5 bytes per row.
    var portraitBytes: [UInt8] {
        var out = [UInt8]()
        var it = portrait.makeIterator()
        while let a = it.next(), let b = it.next() {
            out.append(UInt8(String([a, b]), radix: 16)!)
        }
        return out
    }
}

struct Assets {
    let font: Font
    let messages: [[MessagePart]]
    let rockStars: [RockStarRecord]
    let gameData: GameData
    let graphics: GraphicsData
    let scenes: SceneLayers

    static func load() throws -> Assets {
        func url(_ name: String) throws -> URL {
            guard let u = Bundle.module.url(forResource: "Resources/\(name)", withExtension: nil)
            else { throw CocoaError(.fileNoSuchFile) }
            return u
        }
        let dec = JSONDecoder()
        return Assets(
            font: Font(data: [UInt8](try Data(contentsOf: url("font.bin")))),
            messages: try dec.decode([[MessagePart]].self, from: Data(contentsOf: url("messages.json"))),
            // custom stars (CustomStars.swift) come first, then the 50 from the tape
            rockStars: CustomStars.load() + (try dec.decode([RockStarRecord].self, from: Data(contentsOf: url("rockstars.json")))),
            gameData: try dec.decode(GameData.self, from: Data(contentsOf: url("gamedata.json"))),
            graphics: try dec.decode(GraphicsData.self, from: Data(contentsOf: url("graphics.json"))),
            scenes: try dec.decode(SceneLayers.self, from: Data(contentsOf: url("scenes.json"))))
    }
}
