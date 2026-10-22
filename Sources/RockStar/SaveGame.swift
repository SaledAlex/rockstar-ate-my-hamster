import Foundation

/// A saved game (not in the original): the whole rules state plus the
/// runtime message strings (band name, star names, track names...).
/// Games resume at the main menu of the saved turn.
struct SaveFile: Codable {
    static let currentVersion = 1
    var version = SaveFile.currentVersion
    var savedAt: Date
    var state: GameState
    var strings: [Int: String]

    /// One line for the load menu, e.g. "THE HAMSTERS 14 MAR £81320".
    var summary: String {
        let band = state.bandName.isEmpty ? "NO NAME" : state.bandName
        let date = "\(state.dayOfMonth) \(GameState.monthNames[min(state.month, 11)])"
        return "\(band.prefix(8)) \(date) £\(state.cash)"
    }
}

/// Save slots in ~/Library/Application Support/RockStarAteMyHamster/
/// (override with RS_SAVE_DIR). Slot 0 is the autosave written at the start
/// of every turn; slots 1-3 are manual saves from the TAB menu.
struct SaveStore {
    static let slotNames = ["AUTO", "SLOT 1", "SLOT 2", "SLOT 3"]
    let dir: URL

    static func standard() -> SaveStore {
        if let d = ProcessInfo.processInfo.environment["RS_SAVE_DIR"] {
            return SaveStore(dir: URL(fileURLWithPath: d, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SaveStore(dir: base.appendingPathComponent("RockStarAteMyHamster", isDirectory: true))
    }

    private func url(_ slot: Int) -> URL {
        dir.appendingPathComponent(slot == 0 ? "autosave.json" : "slot\(slot).json")
    }

    func save(_ file: SaveFile, slot: Int) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(file).write(to: url(slot), options: .atomic)
    }

    /// nil when the slot is empty, unreadable or from another version.
    func load(slot: Int) -> SaveFile? {
        guard let d = try? Data(contentsOf: url(slot)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let f = try? dec.decode(SaveFile.self, from: d), f.version == SaveFile.currentVersion
        else { return nil }
        return f
    }
}
