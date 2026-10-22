import Foundation

/// Static rule tables dumped from the original RAM by tools/make_assets.py
/// (`Resources/gamedata.json`). Addresses refer to `decompiled/snap/sideA_ram.bin`.
struct RivalData: Codable {
    /// `$ABC8+5s`: [counter|bit7 climbing, score, peak score, counter on respawn, counter after peak]
    let single: [UInt8]
    /// `$AC5E+5s`, same layout.
    let album: [UInt8]
    /// `$7CE7+3s`: indices into `nameStrings` for the band's single titles.
    let songChoices: [Int]
    /// index into `nameStrings` (57 - slot).
    let albumTitle: Int
}

struct GameData: Codable {
    /// `$BE59` (64 bytes, values 0..15).
    let rngTable: [UInt8]
    /// 30 rival bands; their names are messages 80...109.
    let rivals: [RivalData]
    /// `$C7FC` respawn scores [25,45,33,21,19,36], index `$C7FB` starts at `respawnStart`.
    let respawnScores: [UInt8]
    let respawnStart: Int
    /// `$ACF4`: 58 ref strings (track names, rival song names, album titles).
    let nameStrings: [[MessagePart]]
    /// `$C6E2`: 8 suggested band names, indexed by the lead star's voice byte.
    let bandNames: [[MessagePart]]
    /// `$C7E7` video-score rank table, `$C7F1` fame rank table.
    let videoRankTable: [Int]
    let fameRankTable: [Int]
    /// `$C71F` royalty % by contract tier (index 0 unused = 255).
    let royaltyPercent: [Int]
    /// `$BE99` days per track by studio.
    let studioDays: [Int]

    static func load(bundle: Bundle = .module) throws -> GameData {
        guard let u = bundle.url(forResource: "Resources/gamedata.json", withExtension: nil)
        else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(GameData.self, from: Data(contentsOf: u))
    }
}

/// Join message/string pieces the way the printer at `$A97D` does:
/// punctuation overwrites the preceding space.
func joinPieces(_ pieces: [String]) -> String {
    var s = ""
    for piece in pieces {
        if let f = piece.first, "!,.?".contains(f), s.hasSuffix(" ") { s.removeLast() }
        s += piece
    }
    return s.trimmingCharacters(in: .whitespaces)
}

extension SpectrumRNG {
    /// `$64C7`: copy a ref string into a STR slot. Random groups are resolved at
    /// copy time with rnd(highest index), followed by a reseed (`$64DE`).
    mutating func expand(_ parts: [MessagePart]) -> String {
        var pieces: [String] = []
        for p in parts {
            switch p {
            case .text(let t): pieces.append(t)
            case .random(let alts):
                pieces.append(alts[min(rnd(alts.count - 1), alts.count - 1)])
                reseed()
            case .string, .number: break
            }
        }
        return joinPieces(pieces)
    }
}
