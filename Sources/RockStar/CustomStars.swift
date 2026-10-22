import AppKit

/// Custom rock stars (not in the original), read from
/// ~/Library/Application Support/RockStarAteMyHamster/custom-stars/stars.json
/// (override the folder with RS_CUSTOM_DIR). They are offered first when hiring,
/// before the 50 stars from the tape. See the README.txt written into that folder.
struct CustomStar: Codable {
    var name: String
    /// "vocals", "guitar", "keyboards" or "drums" (sets the equipment prices).
    var instrument: String?
    /// Starting values in the original's ranges; defaults are average tape stars.
    var fame: Int?        // tape stars: 1...30
    var skill: Int?       // tape stars: 0...15
    var mood: Int?        // tape stars: 3...90 (higher = happier for longer)
    var wage: Int?        // pounds per week, 10...99,990
    /// 0...7: which suggested band name / music voice the star brings.
    var voice: Int?
    /// 0...7 units of equipment to buy for this star.
    var gear: Int?
    /// PNG/JPEG next to stars.json; scaled to 40x48 and dithered to 1-bit.
    var portrait: String?
}

enum CustomStars {
    static var dir: URL {
        if let d = ProcessInfo.processInfo.environment["RS_CUSTOM_DIR"] {
            return URL(fileURLWithPath: d, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RockStarAteMyHamster/custom-stars", isDirectory: true)
    }

    /// Records for every valid entry in stars.json (empty when there is none).
    /// Also writes the README and an example file the first time.
    static func load() -> [RockStarRecord] {
        // Tests and headless scripts stay deterministic unless RS_CUSTOM_DIR is set.
        let env = ProcessInfo.processInfo.environment
        if env["RS_CUSTOM_DIR"] == nil,
           NSClassFromString("XCTestCase") != nil || CommandLine.arguments.contains("--script") { return [] }
        writeHelpFiles()
        return entries().map(record)
    }

    /// The raw entries of stars.json (empty if missing or invalid).
    static func entries() -> [CustomStar] {
        let file = dir.appendingPathComponent("stars.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        do {
            return try JSONDecoder().decode([CustomStar].self, from: data)
        } catch {
            FileHandle.standardError.write("custom-stars/stars.json: \(error)\n".data(using: .utf8)!)
            return []
        }
    }

    static func save(_ list: [CustomStar]) throws {
        writeHelpFiles()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(list).write(to: dir.appendingPathComponent("stars.json"), options: .atomic)
    }

    /// Pack a custom star into the tape record format (stats bytes as in rules_core).
    static func record(_ c: CustomStar) -> RockStarRecord {
        func clamp(_ v: Int?, _ d: Int, _ lo: Int, _ hi: Int) -> UInt8 { UInt8(max(lo, min(hi, v ?? d))) }
        let bitsFor: [String: UInt8] = ["drums": 0x80, "keyboards": 0x40, "keys": 0x40, "guitar": 0x20]
        let instrumentBits = bitsFor[(c.instrument ?? "vocals").lowercased()] ?? 0
        let gear = clamp(c.gear, 4, 0, 7)
        let wage10 = max(1, min(9_999, (c.wage ?? 2_000) / 10))
        let digits = [wage10 / 1000, wage10 / 100 % 10, wage10 / 10 % 10, wage10 % 10].map(UInt8.init)
        let stats: [UInt8] = [clamp(c.fame, 15, 1, 255), clamp(c.voice, Int.random(in: 0...7), 0, 7),
                              clamp(c.skill, 7, 0, 255), clamp(c.mood, 35, 1, 250),
                              instrumentBits | gear] + digits + [0x55]
        let name = String(c.name.uppercased().filter { $0.isASCII }.prefix(20))
        return RockStarRecord(name: name, stats: stats, portrait: portrait(c, name: name).map { String(format: "%02x", $0) }.joined())
    }

    /// 240 bytes: 40x48, 1 bit per pixel, set = ink. Uses the picture if given,
    /// otherwise draws the star's initials.
    static func portrait(_ c: CustomStar, name: String) -> [UInt8] {
        let w = 40, h = 48
        var gray = [UInt8](repeating: 255, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()
        gray.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if let p = c.portrait, let img = NSImage(contentsOf: dir.appendingPathComponent(p)),
               let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                // fill the 40x48 frame, cropping the longer side (centred)
                let s = max(CGFloat(w) / CGFloat(cg.width), CGFloat(h) / CGFloat(cg.height))
                let dw = CGFloat(cg.width) * s, dh = CGFloat(cg.height) * s
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
            } else {
                let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                ctx.setStrokeColor(gray: 0, alpha: 1); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: 6, y: 10, width: 28, height: 30))
                let a = NSAttributedString(string: initials, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.black])
                let sz = a.size()
                a.draw(at: CGPoint(x: (CGFloat(w) - sz.width) / 2, y: 25 - sz.height / 2))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // Floyd-Steinberg dither to 1 bit
        var err = gray.map { Double($0) }
        var out = [UInt8](repeating: 0, count: w * h / 8)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let ink = err[i] < 128
                if ink { out[y * 5 + x / 8] |= 0x80 >> UInt8(x % 8) }
                let e = err[i] - (ink ? 0 : 255)
                if x + 1 < w { err[i + 1] += e * 7 / 16 }
                if y + 1 < h {
                    if x > 0 { err[i + w - 1] += e * 3 / 16 }
                    err[i + w] += e * 5 / 16
                    if x + 1 < w { err[i + w + 1] += e / 16 }
                }
            }
        }
        return out
    }

    static func writeHelpFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let readme = dir.appendingPathComponent("README.txt")
        guard !fm.fileExists(atPath: readme.path) else { return }
        let help = """
        CUSTOM ROCK STARS
        =================
        Put your own rock stars in a file called stars.json in this folder. They are
        offered first when you hire your band, before the 50 stars from the tape.
        Start from stars.example.json: copy it to stars.json and edit it.

        Every field except "name" is optional:
          name        up to 20 letters (shown in capitals)
          instrument  "vocals", "guitar", "keyboards" or "drums" (sets equipment prices)
          fame        starting fame, tape stars are 1-30
          skill       starting skill, tape stars are 0-15
          mood        how long they stay happy, tape stars are 3-90
          wage        pounds per week (10 - 99990); tape stars: £50 - £18,000
          voice       0-7, which suggested band name / music style they bring
          gear        0-7, how much equipment they need
          portrait    a PNG or JPEG in this folder; it is cropped to 40x48 and turned
                      into black-and-white Spectrum pixels. No picture = initials.

        Restart the game after editing. If the file has a typo, the game ignores it and
        runs with the normal 50 stars.
        """
        try? help.write(to: readme, atomically: true, encoding: .utf8)
        let example = """
        [
          {"name": "Alex The Axe", "instrument": "guitar", "fame": 25, "skill": 12,
           "mood": 40, "wage": 3000, "gear": 5, "portrait": "alex.png"},
          {"name": "Dirty Dave", "instrument": "drums", "fame": 10, "skill": 8, "wage": 500}
        ]
        """
        try? example.write(to: dir.appendingPathComponent("stars.example.json"), atomically: true, encoding: .utf8)
    }
}
