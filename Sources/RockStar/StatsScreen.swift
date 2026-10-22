import Foundation

/// Band stats overlay (not in the original, which hides all of these numbers).
/// Press I at any prompt (except name entry) to open it; any key closes it.
@MainActor
final class StatsScreen {
    private unowned let game: Game
    private var ui: Console { game.ui }
    private(set) var open = false
    private var saved = Screen()

    nonisolated static let labels = ["NONE", "FLOPPY DISCS", "ROUGH", "S+M", "PHONEYGRAM", "MEGA BIG"]

    init(game: Game) {
        self.game = game
        let previous = game.ui.interceptKey
        game.ui.interceptKey = { [unowned self] key in
            self.handle(key) || (previous?(key) ?? false)
        }
    }

    private func handle(_ key: Key) -> Bool {
        if open { close(); return true }
        guard key == .other("I"), game.cheatMenu?.open != true else { return false }
        open = true
        saved = ui.screen
        draw()
        return true
    }

    private func close() {
        open = false
        ui.screen = saved
        ui.onChange()
    }

    /// The original's mood bands (`$74B5`): >= 9 content, 4-8 makes demands,
    /// <= 3 trouble or quit ultimatums.
    static func moodWord(_ m: UInt8) -> String {
        switch m {
        case 9...: return "HAPPY"
        case 4...8: return "DEMANDING"
        default: return "ABOUT TO QUIT"
        }
    }

    private func draw() {
        let st = game.state, font = ui.assets.font
        var s = Screen()
        s.clear(attr: 0x07)
        var row = 0
        func line(_ text: String, attr: UInt8 = 0x07) {
            s.drawText(String(text.prefix(32)), col: 0, row: row, font: font)
            s.fillAttr(col: 0, row: row, width: 32, height: 1, attr: attr)
            row += 1
        }
        let d = st.config.difficulty
        line(" BAND STATS".padding(toLength: 32, withPad: " ", startingAt: 0), attr: 0x56)
        line((st.bandName.isEmpty ? "NO BAND YET" : st.bandName), attr: 0x46)
        line("\(GameState.dayNames[st.dayOfWeek]) \(st.dayOfMonth) \(GameState.monthNames[min(st.month, 11)])  \(d.rawValue.uppercased())"
             + (st.config.sandbox ? " SANDBOX" : ""), attr: 0x45)
        if st.config.career { line("CAREER YEAR \(st.config.careerYear)  PLATINUMS \(st.config.platinums)", attr: 0x45) }
        row += 1
        line("CASH        £\(st.cash)")
        line("FAME        \(st.fame)/255")
        line("SKILL       \(st.skill)/255")
        line("STREET CRED \(st.hype)/15")
        line("RECORD DEAL \(StatsScreen.labels[min(st.label, 5)])"
             + (st.label > 0 ? " \(st.royaltyPercent(tier: st.label))%" : ""))
        func pos(_ p: Int) -> String { p == 0 ? "-" : (p <= 10 ? "#\(p)" : "OUT") }
        line("SINGLE \(pos(st.singlePos))  ALBUM \(pos(st.albumPos))")
        let t = d.discThresholds
        let got = st.discs.filter { $0 }.count
        line("DISCS \(got)/4  POINTS \(st.discPoints)" + (got < 4 ? " NEXT \(t[got])" : ""), attr: 0x46)
        row += 1
        line("ROCK STARS       MOOD    WAGE", attr: 0x05)
        var bill = 0
        for i in 0..<4 where !st.gone[i] {
            let wage = st.wages[i] * d.wagePercent / 100
            bill += wage
            let name = String(st.starNames[i].prefix(16)).padding(toLength: 17, withPad: " ", startingAt: 0)
            let mood = StatsScreen.moodWord(st.mood[i])
            let attr: UInt8 = st.mood[i] >= 9 ? 0x04 : (st.mood[i] >= 4 ? 0x06 : 0x02)
            line(name + "\(st.mood[i])".padding(toLength: 3, withPad: " ", startingAt: 0) + "£\(wage)", attr: 0x07)
            line("  " + mood, attr: attr | 0x40)
        }
        if st.stars == 0 { line("NONE") }
        line("WAGE BILL £\(bill) EVERY FRIDAY", attr: 0x05)
        row = 23
        line("PRESS ANY KEY", attr: 0x0F)
        ui.screen = s
        ui.onChange()
    }
}
