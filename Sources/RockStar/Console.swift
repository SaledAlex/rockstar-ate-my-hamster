import Foundation

/// Keys the game cares about. The original accepts keyboard or Kempston joystick.
enum Key: Equatable { case up, down, fire, delete, other(Character) }

/// A text area in character cells.
struct TextBox { var col: Int, row: Int, width: Int, height: Int }

/// Text window + menus + input, the rebuild's equivalent of $A8DA / $6D9D / $A5C2.
/// Game logic awaits these calls, so it reads like the original's sequential code.
@MainActor
final class Console {
    let assets: Assets
    var screen = Screen()
    var onChange: () -> Void = {}

    /// Runtime string slots (<STRn>) and number slots (<NUMn>) used by messages.
    var strings: [Int: String] = [:]
    var numbers: [Int: Int] = [:]
    /// Picks a random alternative 0...n for `{a|b}` groups. The game routes this
    /// through the original RNG (`$A941` calls `$A51F`), so printing advances it.
    var pick: (Int) -> Int = { Int.random(in: 0...$0) }

    /// Speech bubble (box 1: rows 0-5, cols 1-30).
    var window = TextBox(col: 1, row: 0, width: 30, height: 6)
    /// Called before a bubble is (re)drawn, e.g. to switch the speaker's tail.
    var beforeText: () -> Void = {}
    /// Called after a menu choice (the scene under the menu box needs restoring).
    var afterMenu: () -> Void = {}
    /// When set, text boxes get this attribute (screens without a scene).
    var windowAttr: UInt8?
    /// True while typing a name: space is a character, not fire.
    private var textMode = false

    /// True in the window (animations, sound); false in headless mode.
    var live = false

    /// True while a menu is waiting for a choice (used by the headless driver).
    private(set) var inMenu = false
    var isWaitingForKey: Bool { keyWaiter != nil }
    private var keyWaiter: CheckedContinuation<Key, Never>?
    private var waiterID = 0

    init(assets: Assets) {
        self.assets = assets
        screen.clear()
    }

    // MARK: input

    /// Called for S outside text entry (mute toggle).
    var onMute: () -> Void = {}
    /// Called for G outside text entry (original / enhanced graphics).
    var onToggleGraphics: () -> Void = {}
    /// Called for M outside text entry (music only on/off).
    var onToggleMusic: () -> Void = {}
    /// The open menu's rows/columns (for mouse hover and clicks), and its selection.
    var menuArea: (top: Int, left: Int, right: Int, count: Int)?
    var menuSel = 0

    /// Cheat menu hook: gets first look at every key outside name entry and
    /// returns true when it consumed it.
    var interceptKey: ((Key) -> Bool)?

    func keyPressed(_ key: Key) {
        if !textMode, let f = interceptKey, f(key) { return }
        if !textMode, key == .other("S") { onMute(); return }
        if !textMode, key == .other("G") { onToggleGraphics(); return }
        if !textMode, key == .other("M") { onToggleMusic(); return }
        guard let k = keyWaiter else { return }
        keyWaiter = nil
        k.resume(returning: textMode ? key : normalize(key))
    }

    /// Original controls ($A549): fire = 0 / ENTER, up = 9 7 P, down = 8 6 L.
    private func normalize(_ key: Key) -> Key {
        guard case .other(let c) = key else { return key }
        switch c {
        case "0", " ": return .fire
        case "9", "7", "P": return .up
        case "8", "6", "L": return .down
        default: return key
        }
    }

    func nextKey() async -> Key {
        await withCheckedContinuation { keyWaiter = $0; waiterID += 1 }
    }

    /// Wait for a key, or return nil after `seconds` (used by "do nothing to reject").
    func nextKey(timeout seconds: Double) async -> Key? {
        let myID = waiterID + 1
        let timer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled, self.waiterID == myID, let k = self.keyWaiter {
                self.keyWaiter = nil
                k.resume(returning: .other("\u{0}"))
            }
        }
        let k = await nextKey()
        timer.cancel()
        if k == .other("\u{0}") { return nil }
        return k
    }

    func waitFire() async {
        while true { if await nextKey() == .fire { return } }
    }

    // MARK: messages

    /// Resolve message `id`. `patches` replaces part n (the original pokes
    /// phrase refs at runtime, e.g. the venue in msg 34).
    func resolve(_ id: Int, patches: [Int: String] = [:]) -> String {
        var pieces: [String] = []
        for (i, part) in assets.messages[id].enumerated() {
            if let p = patches[i] { pieces.append(p); continue }
            switch part {
            case .text(let t): pieces.append(t)
            case .random(let alts): pieces.append(alts[min(max(pick(alts.count - 1), 0), alts.count - 1)])
            case .string(let n): pieces.append((strings[n] ?? "") + " ")
            case .number(let n): pieces.append(String(numbers[n] ?? 0) + " ")
            }
        }
        return joinPieces(pieces).replacingOccurrences(of: "`", with: "£")
    }

    /// Word-wrap like the printer (`$A81C`): a word joins a line only if it and a
    /// following space fit in the box width (a line's first word may fill it exactly). Runs of spaces inside a line are kept
    /// (option lists use them to align prices); spaces at a line break are dropped.
    func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = [], line = ""
        var tokens: [(String, String)] = []
        var sp = "", w = ""
        for ch in text {
            if ch == " " {
                if !w.isEmpty { tokens.append((sp, w)); sp = ""; w = "" }
                sp.append(ch)
            } else { w.append(ch) }
        }
        if !w.isEmpty { tokens.append((sp, w)) }
        for (space, word0) in tokens {
            var word = word0
            while word.count > width && width > 0 {   // hard-split very long words
                if !line.isEmpty { lines.append(line); line = "" }
                lines.append(String(word.prefix(width))); word = String(word.dropFirst(width))
            }
            if line.isEmpty { line = word }
            else if line.count + space.count + word.count + 1 <= width { line += space + word }
            else { lines.append(line); line = word }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    func clear(_ b: TextBox) {
        screen.clearRect(col: b.col, row: b.row, width: b.width, height: b.height)
        if let a = windowAttr { screen.fillAttr(col: b.col, row: b.row, width: b.width, height: b.height, attr: a) }
    }

    /// Print text in the bubble; pages of `window.height` lines wait for fire
    /// between them. Returns the row after the last line.
    @discardableResult
    func showText(_ text: String) async -> Int {
        beforeText()
        let lines = wrap(text, width: window.width)
        var start = 0
        while true {
            clear(window)
            let page = Array(lines[start..<min(start + window.height, lines.count)])
            for (i, l) in page.enumerated() {
                screen.drawText(l, col: window.col, row: window.row + i, font: assets.font)
            }
            onChange()
            start += window.height
            if start >= lines.count { return window.row + page.count }
            await waitFire()
        }
    }

    /// Set RS_TRACE=1 to log every message and menu to stderr (headless debugging).
    static let trace = ProcessInfo.processInfo.environment["RS_TRACE"] != nil

    @discardableResult
    func show(_ id: Int, patches: [Int: String] = [:]) async -> Int {
        let text = resolve(id, patches: patches)
        if Console.trace { FileHandle.standardError.write("[msg \(id)] \(text)\n".data(using: .utf8)!) }
        return await showText(text)
    }

    /// Show a message and wait for fire (`$A5C2`).
    func say(_ id: Int, patches: [Int: String] = [:]) async {
        await show(id, patches: patches)
        await waitFire()
    }

    func sayText(_ text: String) async {
        if Console.trace { FileHandle.standardError.write("[text] \(text)\n".data(using: .utf8)!) }
        await showText(text)
        await waitFire()
    }

    // MARK: menus (`$6D9D` / `$AADB`)

    /// `$AEB0` box `id`: top, left, bottom, right (text area; bottom/right exclusive).
    func box(_ id: Int) -> [Int] { assets.graphics.boxes[id] }

    /// `$AAB5`: clear the box plus a one-cell border to white (attr $78) and draw a
    /// one-pixel frame on the outer pixels of that border.
    func drawFrame(_ id: Int) {
        let b = box(id)
        let top = max(b[0] - 1, 0), left = max(b[1] - 1, 0)
        let bottom = min(b[2], Screen.rows - 1), right = min(b[3], Screen.cols - 1)
        screen.clearRect(col: left, row: top, width: right - left + 1, height: bottom - top + 1)
        screen.fillAttr(col: left, row: top, width: right - left + 1, height: bottom - top + 1, attr: 0x78)
        let x0 = left * 8, y0 = top * 8, x1 = right * 8 + 7, y1 = bottom * 8 + 7
        for x in x0...x1 { screen.set(x, y0, true); screen.set(x, y1, true) }
        for y in y0...y1 { screen.set(x0, y, true); screen.set(x1, y, true) }
    }

    /// Framed box with a message, as `$AAB5` does for the intro and the prompts.
    func showBox(_ id: Int, boxId: Int) {
        let text = resolve(id)
        if Console.trace { FileHandle.standardError.write("[box \(id)] \(text)\n".data(using: .utf8)!) }
        drawFrame(boxId)
        let b = box(boxId)
        for (i, l) in wrap(text, width: b[3] - b[1]).prefix(b[2] - b[0]).enumerated() {
            screen.drawText(l, col: b[1], row: b[0] + i, font: assets.font)
        }
        onChange()
    }

    /// `$6D9D` / `$AADB`: a framed menu in box `boxId`, one option per line; the
    /// selected line is highlighted (attr $68) across the whole frame width.
    func choose(_ options: [String], box boxId: Int) async -> Int {
        let b = box(boxId)
        var sel = 0
        menuArea = (top: b[0], left: max(b[1] - 1, 0), right: min(b[3], Screen.cols - 1), count: options.count)
        defer { menuArea = nil }
        if Console.trace { FileHandle.standardError.write("[menu] \(options.joined(separator: " / "))\n".data(using: .utf8)!) }
        drawFrame(boxId)
        let left = max(b[1] - 1, 0), right = min(b[3], Screen.cols - 1)
        for (i, o) in options.enumerated() { screen.drawText(o, col: b[1], row: b[0] + i, font: assets.font) }
        while true {
            for i in options.indices {
                screen.fillAttr(col: left, row: b[0] + i, width: right - left + 1, height: 1, attr: i == sel ? 0x68 : 0x78)
            }
            onChange()
            inMenu = true
            menuSel = sel
            let key = await nextKey()
            inMenu = false
            switch key {
            case .up: sel = (sel + options.count - 1) % options.count
            case .down: sel = (sel + 1) % options.count
            case .fire: afterMenu(); return sel
            case .other(let c):
                if let n = c.wholeNumberValue, n >= 1, n <= options.count { afterMenu(); return n - 1 }
            default: break
            }
        }
    }

    /// Menu box per option message (the A register at each `$6D9D` call site).
    static let menuBoxes: [Int: Int] = [7: 2, 16: 3, 18: 4, 45: 9, 190: 9, 27: 5, 32: 6, 38: 7, 40: 8,
                                        47: 10, 52: 11, 35: 195, 50: 196, 171: 71, 68: 23, 70: 24]

    /// Message in the bubble, then a menu built from option message `optionsId`.
    func menu(_ id: Int?, optionsMessage optionsId: Int, patches: [Int: String] = [:]) async -> Int {
        if let id { await show(id, patches: patches) }
        let boxId = Console.menuBoxes[optionsId] ?? 4
        return await choose(options(fromMessage: optionsId, box: boxId), box: boxId)
    }

    /// `$6355`: yes/no (msg 7, box 2); true = YES.
    func yesNo(_ id: Int, patches: [Int: String] = [:]) async -> Bool {
        await show(id, patches: patches)
        return await choose(options(fromMessage: 7, box: 2), box: 2) == 0
    }

    /// The options message printed into the menu box: one option per wrapped line.
    func options(fromMessage id: Int, box boxId: Int) -> [String] {
        let b = box(boxId)
        return wrap(resolve(id), width: b[3] - b[1])
    }

    // MARK: text entry (`$646F`)

    /// Type a name in box 0 (`$A5EA`: framed, bottom rows, over the status bar);
    /// ENTER finishes (needs at least 2 chars).
    func readLine(maxLength: Int = 30) async -> String {
        textMode = true
        defer { textMode = false; afterMenu() }
        var s = ""
        let b = box(0)
        while true {
            drawFrame(0)
            let shown = s + "@"   // $40 = solid cursor glyph
            screen.drawText(String(shown.suffix(b[3] - b[1])), col: b[1], row: b[0], font: assets.font)
            onChange()
            switch await nextKey() {
            case .fire:
                let t = s.trimmingCharacters(in: .whitespaces)
                if t.count >= 2 { return t }
            case .delete: if !s.isEmpty { s.removeLast() }
            case .other(let c):
                let u = Character(c.uppercased())
                if s.count < maxLength, let a = u.asciiValue, a >= 0x20, a < 0x60, u != "@" { s.append(u) }
            default: break
            }
        }
    }
}
