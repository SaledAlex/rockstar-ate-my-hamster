import Foundation

/// Cheat menu / sandbox toggle (not in the original). TAB opens it at any
/// prompt except name entry; it edits `game.state` directly and restores the
/// screen on close, so the game carries on where it was.
@MainActor
final class CheatMenu {
    private unowned let game: Game
    private var ui: Console { game.ui }
    private(set) var open = false
    private var saved = Screen()
    private(set) var sel = 0
    private var note = ""
    /// false: main page; true: the new-events page.
    private var eventsPage = false
    /// First item shown (the events page scrolls).
    private var offset = 0
    private static let visibleRows = 13

    private static let box = TextBox(col: 3, row: 1, width: 26, height: 18)

    init(game: Game) {
        self.game = game
        game.ui.interceptKey = { [unowned self] key in self.handle(key) }
    }

    private var items: [String] {
        if eventsPage {
            let cfg = EventSettings.shared
            return ["HOW OFTEN: " + cfg.chanceLabel, "ALL ON", "ALL OFF"]
                + Game.newEventNames.enumerated().map { (cfg.isOn($0.offset) ? "[X] " : "[ ] ") + $0.element }
                + ["BACK"]
        }
        return ["CASH +£100,000", "CASH +£1,000,000", "FAME +50", "SKILL +50",
         "STREET CRED MAX", "MAKE BAND HAPPY", "GOLD DISC +1",
         "SANDBOX: " + (game.state.config.sandbox ? "ON" : "OFF"),
         "SAVE TO SLOT 1", "SAVE TO SLOT 2", "SAVE TO SLOT 3", "NEW EVENTS...", "CLOSE"]
    }

    /// Mouse support: item rows of the open menu.
    var itemArea: (top: Int, left: Int, right: Int, count: Int) {
        let b = CheatMenu.box
        return (b.row + 2, b.col, b.col + b.width - 1, min(items.count - offset, CheatMenu.visibleRows))
    }

    func hover(_ row: Int) {
        let i = row + offset
        guard open, i != sel, items.indices.contains(i) else { return }
        sel = i
        draw()
    }

    func click(_ row: Int) {
        let i = row + offset
        guard open, items.indices.contains(i) else { return }
        sel = i
        apply(i)
        if open { draw() }
    }

    /// Returns true when the key was consumed.
    private func handle(_ key: Key) -> Bool {
        if !open {
            guard key == .other("\t") else { return false }
            open = true; sel = 0; note = ""; eventsPage = false; offset = 0
            saved = ui.screen
            draw()
            return true
        }
        switch key {
        case .up: sel = (sel + items.count - 1) % items.count
        case .down: sel = (sel + 1) % items.count
        case .fire, .other(" "), .other("0"): apply(sel)
        case .other("\u{1B}") where eventsPage: eventsPage = false; sel = 12; offset = 0
        case .other("\t"), .other("\u{1B}"): close()
        case .other(let c) where !eventsPage:
            if let n = c.wholeNumberValue, n >= 1, n <= items.count { sel = n - 1; apply(sel) }
        default: break
        }
        if open { draw() }
        return true
    }

    private func apply(_ i: Int) {
        if eventsPage { applyEvents(i); return }
        var s = game.state
        switch i {
        case 0: s.credit(100_000); note = "KERCHING!"
        case 1: s.credit(1_000_000); note = "KERCHING!"
        case 2: s.fame = min(s.fame + 50, 255); note = "FAME \(s.fame)"
        case 3: s.skill = min(s.skill + 50, 255); note = "SKILL \(s.skill)"
        case 4: s.hype = 15; note = "CRED 15"
        case 5:
            for k in 0..<4 where !s.gone[k] { s.mood[k] = 20 }
            note = "EVERYONE'S HAPPY"
        case 6:
            // Disc points thresholds from $7004 (40/100/170/250); the 4th = platinum = win.
            let thresholds = s.config.difficulty.discThresholds
            if let next = s.discs.firstIndex(of: false) {
                s.discs[next] = true
                s.discPoints = max(s.discPoints, thresholds[next])
                note = next == 3 ? "PLATINUM! (WIN AT END OF TURN)" : "GOLD DISC \(next + 1)"
            } else { note = "ALREADY PLATINUM" }
        case 7:
            s.config.sandbox.toggle()
            note = s.config.sandbox ? "NO BANKRUPTCY, NO YEAR END" : "NORMAL RULES"
        case 8, 9, 10:
            game.state = s
            let slot = i - 7
            if let f = game.saveForSlot(), (try? game.saves.save(f, slot: slot)) != nil {
                note = game.atMainMenu ? "SAVED TO SLOT \(slot)" : "SAVED (START OF TURN)"
            } else { note = "NOTHING TO SAVE YET" }
            return
        case 11:
            eventsPage = true; sel = 0; offset = 0; note = "FIRE TOGGLES, ESC = BACK"
            return
        default:
            game.state = s
            close()
            return
        }
        game.state = s
        // refresh the status panel (cash, disc lamps) under the menu
        ui.screen = saved
        game.drawPanel()
        saved = ui.screen
    }

    private func applyEvents(_ i: Int) {
        let cfg = EventSettings.shared, n = Game.newEventNames.count
        switch i {
        case 0: cfg.nextChance(); note = cfg.chance == 0 ? "NEW EVENTS OFF" : "ABOUT \(cfg.chanceLabel)"
        case 1: cfg.disabled = []; note = "ALL EVENTS ON"
        case 2: cfg.disabled = Set(0..<n); note = "ALL EVENTS OFF"
        case 3..<(3 + n):
            cfg.toggle(i - 3)
            note = Game.newEventNames[i - 3] + (cfg.isOn(i - 3) ? " ON" : " OFF")
        default: eventsPage = false; sel = 11; offset = 0; note = ""
        }
    }

    private func close() {
        open = false
        ui.screen = saved
        game.drawPanel()   // cash/discs may have changed
        ui.onChange()
    }

    private func draw() {
        let b = CheatMenu.box, font = ui.assets.font
        var scr = saved
        scr.clearRect(col: b.col, row: b.row, width: b.width, height: b.height)
        scr.fillAttr(col: b.col, row: b.row, width: b.width, height: b.height, attr: 0x4F)
        scr.fillAttr(col: b.col, row: b.row, width: b.width, height: 1, attr: 0x56)
        let title = eventsPage ? "NEW EVENTS" : "CHEAT MENU"
        scr.drawText(title, col: b.col + (b.width - title.count) / 2, row: b.row, font: font)
        let all = items
        if sel < offset { offset = sel }
        if sel >= offset + CheatMenu.visibleRows { offset = sel - CheatMenu.visibleRows + 1 }
        if offset > 0 { scr.drawText("^", col: b.col + b.width - 2, row: b.row + 1, font: font) }
        if offset + CheatMenu.visibleRows < all.count {
            scr.drawText("V", col: b.col + b.width - 2, row: b.row + 15, font: font)
        }
        for i in offset..<min(all.count, offset + CheatMenu.visibleRows) {
            let item = all[i]
            let row = b.row + 2 + i - offset
            scr.drawText(eventsPage ? item : "\(i + 1) \(item)", col: b.col + 1, row: row, font: font)
            if i == sel { scr.fillAttr(col: b.col, row: row, width: b.width, height: 1, attr: 0x70) }
        }
        let st = game.state
        scr.drawText("FAME \(st.fame) SKILL \(st.skill) CRED \(st.hype)", col: b.col + 1, row: b.row + 15, font: font)
        scr.drawText(String(note.prefix(b.width - 2)), col: b.col + 1, row: b.row + 16, font: font)
        scr.drawText("TAB/ESC: BACK TO GAME", col: b.col + 1, row: b.row + 17, font: font)
        scr.fillAttr(col: b.col, row: b.row + 17, width: b.width, height: 1, attr: 0x4E)
        ui.screen = scr
        ui.onChange()
    }
}
