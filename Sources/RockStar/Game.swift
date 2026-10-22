import Foundation

/// Game flow. Each function corresponds to a routine in the original
/// (addresses in comments); the rules live in the UI-free `GameState`
/// (Model/*.swift) and this class sequences them with the original's
/// messages, menus and screens.
@MainActor
final class Game {
    let ui: Console
    var state: GameState
    private var g: GraphicsData { ui.assets.graphics }
    private var bigFont: [UInt8]

    // presentation state
    /// `$BEB7` 1 office, 2 limo, 3 screening room, 4 studio
    private var scene = 1
    /// `$BEDA` phone in Clive's hand
    private var phone = false
    /// `$BED3` 1 = Cecil speaking (bubble tail), 0 = Clive
    private var cecilSpeaking = false
    private var sceneActive = false
    var needsRedraw = false
    /// Portrait shown on the TV while hiring.
    var tvPortrait: Int?
    /// `$6239`: the band rides in the limousine (drawn with their heads).
    private var limoBand = false
    /// Test aid (`--cheat`): start each band with SKILL 100, FAME 120, £3,000,000
    /// so headless scripts can reach contracts, recording and charts quickly.
    var cheat = false
    /// Sound (windowed app only; nil = silent, e.g. headless).
    var sound: SoundPlayer?
    /// TAB cheat menu (windowed app and headless `^`).
    var cheatMenu: CheatMenu?
    /// I: band stats overlay.
    var stats: StatsScreen?
    /// Save slots (autosave + 3 manual).
    var saves = SaveStore.standard()
    /// Snapshot taken at the start of the current turn (also the autosave).
    private(set) var checkpoint: SaveFile?
    /// True while the main menu waits for a choice: saving then stores the live state.
    private(set) var atMainMenu = false
    /// New events already seen this game (NewEvents.swift).
    var usedNewEvents = Set<Int>()
    /// Career year in which the mid-year platinum was celebrated.
    var celebratedYear = 0

    init(console: Console, config: GameConfig = GameConfig(), seed: UInt64? = nil) {
        ui = console
        state = GameState(data: console.assets.gameData, records: console.assets.rockStars,
                          config: config, seed: seed ?? UInt64.random(in: 0...UInt64.max))
        bigFont = hexBytes(console.assets.graphics.bigFont)
        ui.pick = { [unowned self] n in self.state.rng.rnd(n) }
        ui.beforeText = { [unowned self] in
            if self.sceneActive && self.needsRedraw { self.redraw() }
        }
        ui.afterMenu = { [unowned self] in self.needsRedraw = true }
    }

    // MARK: main loop `$61A8`

    func run() async {
        await title()
        var resumed = false
        if let f = await loadMenu() {
            restore(f)
            resumed = true
        } else {
            await chooseDifficulty()
            state.newGame()
            await intro()
        }
        var hire = true
        while true {
            if !resumed {
                if hire { await hireStars() }
                await formBand()
            }
            resumed = false
            while true {
                await turn()
                await careerPlatinumCheck()
                if state.gameDecided { break }
            }
            await ending()
            let same = await ask(33)
            state.newGame()                  // $6277 re-init
            state.config.careerYear = 1; state.config.platinums = 0; state.config.careerRetired = false
            celebratedYear = 0
            ui.strings = [:]
            usedNewEvents.removeAll()
            if same { state.restoreStars(); hire = false } else { hire = true }
            scene = 1; phone = false
        }
    }

    // MARK: speech helpers

    func setSpeaker(cecil: Bool) {
        if cecilSpeaking != cecil { cecilSpeaking = cecil; needsRedraw = true }
    }

    /// Clive speaks and we wait for fire.
    func clive(_ id: Int, _ patches: [Int: String] = [:]) async {
        setSpeaker(cecil: false); await ui.say(id, patches: patches)
    }

    /// Cecil (the player's character) speaks.
    func cecil(_ id: Int, _ patches: [Int: String] = [:]) async {
        setSpeaker(cecil: true); await ui.say(id, patches: patches)
    }

    /// Clive asks a yes/no question.
    func ask(_ id: Int, _ patches: [Int: String] = [:]) async -> Bool {
        setSpeaker(cecil: false); return await ui.yesNo(id, patches: patches)
    }

    func choose(_ id: Int?, _ options: Int, _ patches: [Int: String] = [:]) async -> Int {
        setSpeaker(cecil: false)
        return await ui.menu(id, optionsMessage: options, patches: patches)
    }

    func setPhone(_ on: Bool) {
        // INFERRED: every pick-up plays sfx 0 ($7E83 does; some callers set $BEDA directly).
        if on && !phone { sound?.sfx(0) }
        if phone != on { phone = on; needsRedraw = true }
    }

    func setScene(_ s: Int) {
        if scene != s { scene = s; needsRedraw = true }
        if sceneActive && needsRedraw { redraw() }
    }

    // MARK: screen composition `$7D41`

    func redraw() {
        sceneActive = true
        needsRedraw = false
        ui.windowAttr = nil
        ui.window = TextBox(col: 1, row: 0, width: 30, height: 6)
        var s = Screen()
        s.clear(attr: 0)
        s.drawList(2, g)
        s.applyAttrList(6, g)
        s.drawList(scene + 2, g)
        s.drawList(phone ? scene + 6 : scene + 10, g)
        if cecilSpeaking {
            s.drawList(scene + 18, g); s.applyAttrList(scene + 14, g)
        } else {
            s.drawList(scene + 14, g); s.applyAttrList(scene + 10, g)
        }
        let live = (0..<4).filter { !state.gone[$0] && state.starRecord[$0] >= 0 }
        if scene == 2 {
            // $A2EB + $7DD1: limousine seats, and the band's heads in the windows
            // while they ride to the gig ($6239).
            let sc = ui.assets.scenes
            s.applyCells(sc.limo["\(limoBand ? 1 : 0)-\(max(1, min(state.stars, 4)))"])
            if limoBand {
                for (k, slot) in live.prefix(4).enumerated() {
                    let h = sc.heads[k], p = state.records[state.starRecord[slot]].portraitBytes
                    let first = k == 1 ? 0 : 1          // $63DB keeps a solid top line on slices 1, 3, 4
                    s.blit(Array(p[(first * 5)..<(h[1] * 5)]), bytesWide: 5, x: h[3] * 8, y: h[2] + first)
                }
            }
        }
        if scene == 4 {
            s.applyCells(ui.assets.scenes.studio["\(max(1, min(state.stars, 4)))"])   // $A2E6
            // $7DB4: band portraits in the studio window, x from table $8763
            var x = [13, 11, 8, 6][max(0, min(state.stars, 4) - 1)]
            for i in 0..<4 where !state.gone[i] && state.starRecord[i] >= 0 {
                s.blit(state.records[state.starRecord[i]].portraitBytes, bytesWide: 5, x: x * 8, y: 0x40)
                x += 5
            }
        }
        s.applyAttrList(scene + 6, g)
        if let r = tvPortrait {
            s.blit(state.records[r].portraitBytes, bytesWide: 5, x: 13 * 8, y: 0x47)
        }
        ui.screen = s
        drawPanel()
    }

    /// Status bar: disc lamps, date, cash, sales graph (rows 18-23).
    func drawPanel() {
        guard sceneActive else { ui.onChange(); return }
        var s = ui.screen
        s.clearRect(col: 0, row: 18, width: 32, height: 6)
        for e in g.spriteLists[2] where e.y >= 144 {
            if let sp = g.sprites[e.sprite] { s.drawSprite(sp, y: e.y, col: e.col, mirror: e.mirror) }
        }
        for pair in g.attrLists[6] where pair[0] < g.boxes.count && g.boxes[pair[0]][0] >= 18 {
            s.fillBox(pair[0], attr: UInt8(pair[1]), g)
        }
        // $82EA disc lamps (boxes 63..66)
        for i in 0..<4 { s.fillBox(63 + i, attr: state.discs[i] ? 0x45 : 0x02, g) }
        // $6EEB date
        let font = ui.assets.font
        s.drawText(GameState.dayNames[state.dayOfWeek], col: 18, row: 19, font: font)
        s.drawBigText(String(format: "%02d", state.dayOfMonth), col: 18, row: 20, font: bigFont)
        s.drawText(GameState.monthNames[min(state.month, 11)], col: 18, row: 22, font: font)
        // $6390 cash
        s.drawText("CASH:", col: 0, row: 23, font: font)
        let digits = "£" + String(state.cash)
        s.drawText(digits, col: 15 - digits.count, row: 23, font: font)
        s.drawText("SALES", col: 25, row: 23, font: font)
        // $7E91 sales graph: one pixel column per week
        for (i, v) in state.salesHistory.enumerated() where v > 0 {
            for h in 0..<min(v, 30) { s.set(24 * 8 + 2 + i, 22 * 8 + 5 - h, true) }
        }
        ui.screen = s
        ui.onChange()
    }

    // MARK: day advance `$6F3B` with wages / chart show / royalties

    func day() async {
        let o = state.advanceDay()
        drawPanel()
        switch o {
        case .wages:
            // $6FA6: msg 44, charge the wage bill
            let was = cecilSpeaking
            await clive(44)
            state.payWages()
            drawPanel()
            setSpeaker(cecil: was)
        case .sunday:
            if state.chartShowDue {
                await chartShow()
                await day()   // `$781A` ends with another day advance
            }
            state.weeklyRoyalties()
            drawPanel()
        case .newYear:
            await yearEnd()
        default: break
        }
    }

    // MARK: title `$6ABC` and intro `$6241`

    func title() async {
        sceneActive = false
        sound?.jingle(0)              // $61C1
        var s = Screen()
        s.loadSCR(hexBytes(g.loadingScreen))
        s.clearRect(col: 0, row: 0, width: 32, height: 1)
        s.fillAttr(col: 0, row: 0, width: 32, height: 2, attr: 0x45)   // $7B9B: box 59
        ui.screen = s
        ui.showBox(139, boxId: 194)   // PRESS FIRE/ENTER TO START OR K FOR KEMPSTON JOYSTICK
        // $7B9B: the credits scroll through row 0, one pixel per frame.
        let ticker = ui.live ? Task { @MainActor in
            let text = Array((g.credits ?? "") + " ")
            var px = 0
            while !Task.isCancelled, !text.isEmpty {
                ui.screen.clearRect(col: 0, row: 0, width: 32, height: 1)
                let first = px / 8
                for i in 0...32 {
                    let ch = text[(first + i) % text.count]
                    let glyph = ui.assets.font.glyph(ch)
                    for r in 0..<6 {
                        for b in 0..<8 where glyph[r] & (0x80 >> b) != 0 {
                            ui.screen.set(256 + i * 8 + b - (px % 8) - 256, r + 1, true)
                        }
                    }
                }
                ui.onChange()
                px = (px + 1) % (text.count * 8)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        } : nil
        while true {
            let k = await ui.nextKey()
            if k == .fire || k == .other("K") { break }
        }
        ticker?.cancel()
    }

    // MARK: save / load (not in the original)

    func makeSave() -> SaveFile {
        SaveFile(savedAt: Date(), state: state, strings: ui.strings)
    }

    /// What a manual save stores: the live game at the main menu, otherwise the
    /// start of the current turn (mid-action states can't be resumed).
    func saveForSlot() -> SaveFile? { atMainMenu ? makeSave() : checkpoint }

    func restore(_ f: SaveFile) {
        state = f.state
        ui.strings = f.strings
        scene = 1; phone = false; cecilSpeaking = false; tvPortrait = nil; limoBand = false
        redraw()
    }

    /// Title screen: NEW GAME or one of the saved games. Skipped when there are none.
    func loadMenu() async -> SaveFile? {
        while true {
            let files = (0..<SaveStore.slotNames.count).compactMap { i in saves.load(slot: i).map { (i, $0) } }
            // the star creator is only offered in the window (it can open a file picker)
            let creator = ui.live || ProcessInfo.processInfo.environment["RS_CUSTOM_DIR"] != nil
            guard !files.isEmpty || creator else { return nil }
            let items = ["NEW GAME"] + files.map { "\(SaveStore.slotNames[$0.0]) \($0.1.summary)" }
                + (creator ? ["STAR CREATOR"] : [])
            let title = files.isEmpty ? "ROCK STAR ATE MY HAMSTER" : "LOAD GAME"
            let sel = await pickList(title: title, items: items, initial: files.isEmpty ? 0 : 1)
            if sel == 0 { return nil }
            if sel <= files.count { return files[sel - 1].1 }
            await StarCreator(game: self).run()
            // pick up the edited stars: custom ones first, then the 50 from the tape
            state = GameState(data: state.data, records: CustomStars.load() + Array(state.records.suffix(50)),
                              config: state.config)
        }
    }

    /// New game: choose the difficulty (windowed app; headless uses `--difficulty`).
    func chooseDifficulty() async {
        guard ui.live else { return }
        let all = Difficulty.allCases
        let sel = await pickList(title: "DIFFICULTY", items: all.map(\.label),
                                 initial: all.firstIndex(of: state.config.difficulty) ?? 1)
        state.config.difficulty = all[sel]
        let mode = await pickList(title: "GAME MODE", items: ["CLASSIC: ONE YEAR", "CAREER: YEAR AFTER YEAR"],
                                  initial: state.config.career ? 1 : 0)
        state.config.career = mode == 1
        state.config.careerYear = 1; state.config.platinums = 0; state.config.careerRetired = false
    }

    /// A simple boxed list over the current screen (title-screen menus).
    func pickList(title: String, items: [String], initial: Int) async -> Int {
        let saved = ui.screen, font = ui.assets.font
        let box = TextBox(col: 1, row: 6, width: 30, height: items.count + 3)
        var sel = initial
        ui.menuArea = (top: box.row + 2, left: box.col, right: box.col + box.width - 1, count: items.count)
        defer { ui.screen = saved; ui.menuArea = nil; ui.onChange() }
        while true {
            var s = saved
            s.clearRect(col: box.col, row: box.row, width: box.width, height: box.height)
            s.fillAttr(col: box.col, row: box.row, width: box.width, height: box.height, attr: 0x4F)
            s.fillAttr(col: box.col, row: box.row, width: box.width, height: 1, attr: 0x56)
            s.drawText(title, col: box.col + (box.width - title.count) / 2, row: box.row, font: font)
            for (i, t) in items.enumerated() {
                let row = box.row + 2 + i
                s.drawText(String(t.prefix(box.width - 1)), col: box.col + 1, row: row, font: font)
                if i == sel { s.fillAttr(col: box.col, row: row, width: box.width, height: 1, attr: 0x70) }
            }
            ui.screen = s
            ui.menuSel = sel
            ui.onChange()
            switch await ui.nextKey() {
            case .up: sel = (sel + items.count - 1) % items.count
            case .down: sel = (sel + 1) % items.count
            case .fire: return sel
            default: break
            }
        }
    }

    func intro() async {
        scene = 1; phone = false; cecilSpeaking = false
        redraw()
        ui.showBox(0, boxId: 134)     // $6241: "ONE DAY AT THE OFFICE..." in its own box
        await ui.waitFire()
        needsRedraw = true
        await cecil(1)
        await cecil(2)
        await clive(3)
        await cecil(4)
    }

    // MARK: hiring `$6B23`

    func hireStars() async {
        setScene(3)
        redraw()
        let n = await choose(23, 35) + 1
        state.beginHiring(count: n)
        var slot = 0, r = 0
        let count = state.records.count
        // Side B: the 50 bundled records are offered in tape order (msg 22 skipped).
        while slot < n {
            let rec = state.records[r]
            tvPortrait = r
            needsRedraw = true
            ui.strings[75] = rec.name
            ui.numbers = [0: GameState.wage(of: rec)]
            setSpeaker(cecil: false)
            await ui.show(21)
            // INFERRED: the original waits a few seconds for fire; here any other
            // key rejects at once (UP goes back one record for convenience).
            let k = await ui.nextKey(timeout: 6)
            if k == .fire {
                state.acceptStar(record: r, slot: slot)
                slot += 1
            } else if k == .up {
                r = (r + count - 2) % count
            }
            r = (r + 1) % count   // after the last record: "rewind the tape"
        }
        tvPortrait = nil
        needsRedraw = true
        await day()
    }

    // MARK: band `$6610`: derive stats, name, equipment

    func formBand() async {
        state.formBand()
        if cheat { state.skill = 100; state.fame = 120; state.cash = 3_000_000 }
        scene = 1
        redraw()
        if state.stars != 1 {
            // $64F7
            ui.strings[0] = state.suggestBandName()
            if !(await ask(13)) {
                setSpeaker(cecil: false)
                await ui.show(14)
                ui.strings[0] = await ui.readLine(maxLength: 30)
            }
            state.bandName = ui.strings[0] ?? ""
        } else {
            state.bandName = state.starNames[0]
        }
        ui.strings[0] = state.bandName
        await buyEquipment(again: false)
    }

    /// `$6683`
    func buyEquipment(again: Bool) async {
        let c = state.gearCosts
        ui.numbers = [0: c[0], 1: c[1], 2: c[2]]
        let q = await choose(again ? 116 : 15, 16)
        state.buyEquipment(q)
        drawPanel()
    }

    // MARK: one turn `$66E9` + `$6ADF`

    func turn() async {
        let snap = makeSave()
        checkpoint = snap
        try? saves.save(snap, slot: 0)    // autosave
        setScene(1)
        await contractOffer()
        let options: Int
        switch state.menuKind {
        case .basic: options = 18
        case .withRecord: options = 45
        case .withRelease: options = 190
        }
        let kind = state.menuKind
        atMainMenu = true
        let choice = await choose(17, options)
        atMainMenu = false
        switch choice {
        case 0: await practice()
        case 1: await gig()
        case 2: await publicity()
        case 3: await gifts()
        default: if kind == .withRecord { await record() } else { await release() }
        }
        setScene(1)
        await periodicEvents()
        await maybeNewEvent()
    }

    /// `$6758`
    func contractOffer() async {
        guard let tier = state.contractOffer() else { return }
        ui.numbers = [0: GameState.contractAdvance[tier], 1: state.royaltyPercent(tier: tier)]
        setPhone(true)
        let labelPhrase = ["", "FLOPPY DISCS ", "ROUGH ", "S+M ", "PHONEYGRAM ", "MEGA BIG "][tier]
        sound?.sfx(1)                 // $67A4
        let yes = await ask(tier == 1 ? 19 : 20, tier == 1 ? [:] : [2: labelPhrase])
        state.answerContract(accept: yes)
        // INFERRED: Cecil answers the label on the phone.
        await cecil(yes ? 24 : 25)
        setPhone(false)
        drawPanel()
    }

    // MARK: practice `$68AA`

    func practice() async {
        let days = await choose(26, 27) + 1
        guard state.startPractice(days: days) else { drawPanel(); return }
        drawPanel()
        await clive(28)
        for _ in 0..<days {
            setSpeaker(cecil: false)
            await ui.show(29)
            // $68F4: the practice tune; seed = $BE57 & 31 after a reseed, accuracy = SKILL.
            // INFERRED: the seed comes from the host RNG so the rules' RNG is untouched.
            sound?.tune(seed: Int.random(in: 0...31), skill: state.skill)
            await ui.waitFire()
            state.practiceDay()
            if let d = state.disasterCheck() { await disaster(d) }
            if state.bankrupt { return }
            await day()
            if state.gameDecided { return }
        }
        await clive(30)
    }

    /// `$7260` outcomes.
    func disaster(_ d: Disaster) async {
        switch d {
        case .sued:
            setPhone(true); sound?.sfx(1); await clive(120); setPhone(false)
        case .taxman:
            setPhone(true); sound?.sfx(1); await clive(121); setPhone(false)
        case .equipmentLost(let q):
            await clive([119, 118, 117][min(q, 2)])
            await buyEquipment(again: true)
        }
        drawPanel()
    }

    // MARK: gigs `$6DC3`

    func gig() async {
        let v = await choose(31, 32)
        ui.numbers = [0: GameState.venueSeats[v], 1: GameState.venueHire[v]]
        let p = await choose(34, 38, [4: GameState.venueNames[v] + " "])
        if p == 5 { return }
        let k = await choose(39, 40)
        if k == 6 { return }
        let nights = k + 2
        guard state.startTour(venue: v, nights: nights) else { drawPanel(); return }
        scene = 2
        await stageIntro()
        redraw()
        for _ in 0..<nights {
            await day()
            if state.gameDecided { break }
            limoBand = true; needsRedraw = true      // $6E6B
            await moodCheck()
            if state.stars == 0 || state.bankrupt { limoBand = false; break }
            await cecil(41)
            limoBand = false; needsRedraw = true     // $6E8C
            await cecil(42)
            let r = state.playGig(venue: v, price: p)
            ui.numbers = [0: r.tickets, 1: GameState.ticketPrices[p], 2: r.takings]
            drawPanel()
            await clive(43)
        }
    }

    /// `$74B5` before each show.
    func moodCheck() async {
        func name(_ s: Int) { ui.strings[72] = state.starNames[s] }
        switch state.moodCheck() {
        case .content(let d):
            if let d { await disaster(d) }
        case .demand(let s, let cost):
            name(s); ui.numbers = [0: cost]
            let yes = await ask(209)
            state.answerDemand(slot: s, cost: cost, pay: yes)
            if !yes { await cecil(210) }
        case .quits(let s):
            name(s)
            await clive(213)
            await cecil(212)
        case .ultimatum(let s, let cost):
            name(s); ui.numbers = [0: cost]
            let yes = await ask(211)
            state.answerUltimatum(slot: s, cost: cost, pay: yes)
            if !yes { await cecil(212) }
        case .trouble(let s, let cost):
            name(s); ui.numbers = [0: cost]
            await clive(37)
            let jailed = state.troubleHeadline()
            await newspaper(headline: jailed ? 166 : 165, side: nil, portrait: s)
            redraw()
            await clive(jailed ? 168 : 167)
            state.payStarBill(slot: s, cost: cost)
        }
        drawPanel()
    }

    /// `$A81C`: print text into box `boxId` (`$AEB0`), word-wrapped to the box width.
    /// The big font (`$81A2`) uses two columns per character and two rows per line.
    func printBox(_ text: String, box boxId: Int, big: Bool = false, into s: inout Screen) {
        let b = ui.box(boxId)
        for (i, l) in ui.wrap(text, width: b[3] - b[1]).enumerated() {
            let row = b[0] + i * (big ? 2 : 1)
            guard row < b[2] else { break }
            if big { s.drawBigText(l, col: b[1], row: row, font: bigFont) }
            else { s.drawText(l, col: b[1], row: row, font: ui.assets.font) }
        }
    }

    /// Message text with its leading spaces kept (the sponsor names are padded with
    /// spaces to centre them; the printer skips one space at a line start).
    func paddedText(_ id: Int) -> String {
        let t = ui.assets.messages[id].map { p -> String in
            if case .text(let v) = p { return v } else { return "" }
        }.joined()
        let lead = t.prefix(while: { $0 == " " }).count
        return String(repeating: " ", count: max(0, lead - 1)) + t.trimmingCharacters(in: .whitespaces)
    }

    /// `$8248` stage-intro poster (`$82BA` when sponsored).
    func stageIntro() async {
        sceneActive = false
        var s = Screen()
        s.clear(attr: 0)
        if state.sponsor != 0 {
            printBox(ui.resolve(151), box: 57, into: &s)                       // CECIL PITT MANAGEMENT AND
            printBox(ui.resolve(152), box: 58, into: &s)                       // PRESENT
            printBox(paddedText(152 + state.sponsor), box: 49, big: true, into: &s)
            printBox(paddedText(157 + state.sponsor), box: 51, big: true, into: &s)
        } else {
            printBox(ui.resolve(148), box: 48, into: &s)
            printBox(ui.resolve(149), box: 49, big: true, into: &s)
        }
        printBox(state.bandName, box: 50, big: true, into: &s)                 // msg 111 = STR0
        for (r, c) in [(0, 0), (0, 30), (21, 0), (21, 30)] {                  // record icons
            s.drawBigChar("&", x: c * 8, y: r * 8 + 2, font: bigFont)
        }
        var x = [13, 10, 6, 3][max(0, min(state.stars, 4) - 1)]   // table $875F
        for i in 0..<4 where !state.gone[i] && state.starRecord[i] >= 0 {
            s.blit(state.records[state.starRecord[i]].portraitBytes, bytesWide: 5, x: x * 8, y: 0x38)
            x += 7
        }
        s.applyAttrList(5, g)
        s.applyAttrList(max(1, min(state.stars, 4)), g)
        ui.screen = s
        ui.onChange()
        sound?.jingle(6)              // $82B3
        await ui.waitFire()
    }

    // MARK: publicity `$7F51`

    func publicity() async {
        await clive(131)
        switch state.publicityStunt() {
        case .nobodyCares(let h, let side):
            await newspaper(headline: h, side: side, portrait: nil)
            redraw()
            sound?.jingle(2)          // $7F8C (after msg 146) and $7F99 (after msg 114)
            await clive(146)
            sound?.jingle(2)
            await cecil(114)
        case .bandStory(let h, let side, let victim, let died):
            await newspaper(headline: h, side: side, portrait: victim)
            redraw()
            sound?.jingle(1)          // $7FEF
            if died {
                ui.strings[72] = state.starNames[victim]
                await clive(208)
            } else {
                await clive(147)
            }
        }
        await day()
    }

    /// "THE STUN" (`$8156` frame, `$8009` other story, `$802D` star story).
    func newspaper(headline: Int, side: Int?, portrait: Int?) async {
        sceneActive = false
        var s = Screen()
        s.clear(attr: 0)
        s.drawList(0, g)                                             // "S" masthead
        if let filler = g.sprites["9489"] {                          // body text texture
            for y in stride(from: 0x88, to: 0xB8, by: 8) {
                for c in [1, 3, 5, 7, 10, 12, 14, 16] { s.drawSprite(filler, y: y, col: c, mirror: false) }
            }
        }
        printBox(ui.resolve(127), box: 0x29, big: true, into: &s)   // TUN
        printBox(ui.resolve(128), box: 0x2B, into: &s)              // BY ACE STUN SNOOPER
        printBox(ui.resolve(129), box: 0x2C, into: &s)              // WIN A ...
        printBox(ui.resolve(130), box: 0x2D, into: &s)              // THE
        printBox(ui.resolve(headline), box: 0x2A, big: true, into: &s)
        if let side { printBox(ui.resolve(side), box: 0x2E, into: &s) }
        if let p = portrait, state.starRecord[p] >= 0 {
            printBox(ui.resolve(145), box: 0x2F, into: &s)          // SEE PAGE 9
            s.blit(state.records[state.starRecord[p]].portraitBytes, bytesWide: 5, x: 0x19 * 8, y: 0x38)
        } else {
            s.drawList(1, g)                                         // page-3 girl
        }
        s.applyAttrList(0, g)
        ui.screen = s
        ui.onChange()
        sound?.jingle(3)              // $7F7E / $8073 / $6AA4
        await ui.waitFire()
    }

    // MARK: gifts `$6CB0`

    func gifts() async {
        let c = await choose(126, 50, [17: state.stars == 1 ? " " : "S "])
        ui.numbers = [0: GameState.giftPrices[c] * state.stars]
        await clive(167)
        state.giveGifts(c)
        drawPanel()
        await day()
    }

    // MARK: recording `$7198`

    func record() async {
        let s = await choose(46, 47)
        if s == 6 { return }
        state.startRecording(studio: s)
        drawPanel()
        await day()
        if state.bankrupt || state.yearOver { return }
        setScene(4)
        await cecil(48)
        while state.tracksCut < 10 {
            for _ in 0..<state.daysPerTrack {
                await day()
                if state.bankrupt || state.yearOver { return }
            }
            await cecil(36)
            if state.dialAccident() {
                await clive(51)
                await cecil(122)
                await clive(123)
                continue
            }
            let suggestion = state.suggestTrackName()
            let first = state.tracksCut == 0
            var name = suggestion
            if !(await ask(first ? 125 : 124, [10: suggestion + " "])) {
                setSpeaker(cecil: false)
                await ui.show(14)
                name = await ui.readLine(maxLength: 30)
            }
            state.nameTrack(name)
            ui.strings[state.tracksCut] = name
        }
        state.finishRecording()
        await clive(49)
        if state.producerRansomDue() {
            setPhone(true)
            sound?.sfx(1)             // $7479
            let pay = await ask(112)
            state.answerRansom(pay: pay)
            drawPanel()
            await clive(pay ? 113 : 115)
            await cecil(114)
            setPhone(false)
            await day()
        }
    }

    // MARK: releases `$732C` / `$7369` / `$73A9`

    func release() async {
        if !state.albumReleased {
            setSpeaker(cecil: false)
            if sceneActive && needsRedraw { redraw() }   // clear the main menu box first
            let c = await ui.choose(ui.options(fromMessage: 52, box: 11), box: 11)
            if c == 0 {
                await ui.show(53)
                let name = await ui.readLine(maxLength: 30)
                state.releaseAlbum(named: name)
                ui.strings[11] = name
                await clive(54)
                await day()
                return
            }
        }
        for i in 0..<10 { ui.strings[1 + i] = state.trackNames[i] }
        setSpeaker(cecil: false)
        await ui.show(55)
        let t = await ui.choose((0..<10).map { ui.resolve(56 + $0) }, box: 12)
        state.beginSingle(track: t)
        if await ask(66) {
            let d = await choose(67, 68)
            let l = await choose(69, 70)
            setSpeaker(cecil: false)
            await ui.show(71)
            let f = await ui.choose((73...78).map { ui.resolve($0) }, box: 25)
            let cost = state.makeVideo(director: d, location: l, feature: f)
            ui.numbers = [0: cost]
            drawPanel()
            await clive(79)
        } else {
            state.skipVideo()
        }
        state.launchSingle()
        await day()
    }

    // MARK: chart show `$781A`

    func chartShow() async {
        await clive(191)
        await cecil(6)
        if state.singleReleased { await showChart(state.runSinglesChart()) }
        if state.albumReleased { await showChart(state.runAlbumsChart()) }
        redraw()
    }

    /// `$7861` / `$785C`: chart screen. Black paper with red ink (attr $42), the big
    /// title in box 72/73, then each position as 4 rows: big number (cols 0-1, "10" uses
    /// cols 0-3), the big movement glyph `$A64F` ('*' $47 same, '+' $45 moved, '<' $46 new)
    /// beside it (two rows lower for 10), the band in rows 0-1 and the title in rows 2-3
    /// of cols 4-31, with paper colours alternating per entry (`$BF27` ^ $10).
    /// INFERRED: the original scrolls the entries in one by one (10 first); the rebuild
    /// shows the settled pages 6-10 and 1-5.
    func showChart(_ t: ChartTable) async {
        sceneActive = false
        let font = ui.assets.font
        for page in [Array(5..<10), Array(0..<5)] {
            var s = Screen()
            s.clear(attr: 0x42)
            printBox(ui.resolve(t.albums ? 179 : 178), box: t.albums ? 73 : 72, big: true, into: &s)
            for (k, i) in page.enumerated() {
                let row = 4 + 4 * k
                let num = ui.resolve(180 + 9 - i)
                s.drawBigText(num, col: 0, row: row, font: bigFont)
                guard i < t.rows.count else { continue }
                let band: String, titleText: String
                switch t.rows[i] {
                case .rival(let slot):
                    band = ui.resolve(80 + slot)
                    titleText = t.albums ? state.rivalAlbumTitles[slot] : state.rivalSongTitles[slot]
                case .player:
                    band = state.bandName
                    titleText = t.albums ? state.albumName : state.trackNames[state.singleTrack]
                }
                let (glyph, attr): (Character, UInt8)
                switch t.markers[i] { case .same: (glyph, attr) = ("*", 0x47)
                                      case .moved: (glyph, attr) = ("+", 0x45)
                                      case .new: (glyph, attr) = ("<", 0x46) }
                let mrow = num.count > 1 ? row + 2 : row
                s.drawBigChar(glyph, x: 16, y: mrow * 8 + 2, font: bigFont)
                s.fillAttr(col: 2, row: mrow, width: 2, height: 2, attr: attr)
                let paper: UInt8 = k % 2 == 0 ? 0x70 : 0x60
                s.fillAttr(col: 4, row: row, width: 28, height: 2, attr: paper)
                s.fillAttr(col: 4, row: row + 2, width: 28, height: 2, attr: paper & ~0x40)
                for (j, l) in ui.wrap(band, width: 28).prefix(2).enumerated() { s.drawText(l, col: 4, row: row + j, font: font) }
                for (j, l) in ui.wrap(titleText, width: 28).prefix(2).enumerated() { s.drawText(l, col: 4, row: row + 2 + j, font: font) }
            }
            ui.screen = s
            ui.onChange()
            // INFERRED: the original plays each entry's tune ($807D rivals, $80EE the
            // player at $BEF1) while it scrolls in; the rebuild plays one per page.
            sound?.tune(seed: Int.random(in: 0...31), skill: 255)
            await ui.waitFire()
        }
        sound?.stopMusic()
    }

    // MARK: periodic events `$6ADF`

    func periodicEvents() async {
        if state.gameDecided { return }
        // $A3E6 sponsor
        if state.sponsor == 0 {
            if let c = state.sponsorOffer() {
                setPhone(true)
                sound?.sfx(1)         // $A422
                let yes = await ask(164, [5: GameState.sponsorNames[c] + " "])
                state.answerSponsor(accept: yes)
                await cecil(yes ? 24 : 25)
                setPhone(false)
                drawPanel()
                await day()
            }
        } else if state.sponsorPullOutDue {
            setPhone(true)
            sound?.sfx(1)             // $A46E
            await clive(169)
            state.sponsorPullOut()
            setPhone(false)
            drawPanel()
            await day()
        }
        switch state.tickEventCounter() {
        case .charity: await charity()
        case .bootleg: await bootleg()
        case .none: break
        }
        if let sp = state.sponsorScandalTick() {   // jingle 3 plays with the newspaper
            await clive(202)
            await newspaper(headline: 202 + sp, side: nil, portrait: nil)
            redraw()
        }
    }

    /// `$62CC`
    func charity() async {
        guard state.charityEligible else { return }
        setPhone(true)
        sound?.sfx(1)                 // $62E2
        let yes = await ask(8)
        let r = state.answerCharity(accept: yes)
        sound?.jingle(r.real == yes ? 1 : 2)   // $6339 / $630A / $634B / $6320
        await cecil(r.real ? (yes ? 11 : 9) : (yes ? 12 : 10))
        if let h = r.headline {
            await newspaper(headline: h, side: nil, portrait: state.pickRandomLiveStar())
            redraw()
        }
        setPhone(false)
        drawPanel()
        await day()
    }

    /// `$A48D`
    func bootleg() async {
        guard state.bootlegEligible else { return }
        setPhone(true)
        state.startBootleg()
        sound?.sfx(1)                 // $A4B3
        let c = await choose(170, 171)
        let r = state.resolveBootleg(c)
        ui.numbers = [0: r.cost]
        drawPanel()
        await clive(r.message)
        setPhone(false)
        await day()
    }

    // MARK: endings `$6A1A` / `$6A60` / `$6A6C` / `$6A73`

    func ending() async {
        scene = 1
        redraw()
        if state.config.career {
            await careerEnding()
        } else if state.won {
            sound?.jingle(5)          // $6A7D
            await clive(200); await cecil(201)
        } else {
            sound?.jingle(7)          // $6A24
            await clive(state.bankrupt ? 196 : state.yearOver ? 197 : 198); await cecil(114)
        }
        sound?.jingle(4)              // $6A31
        ui.showBox(199, boxId: 193)   // $6A51
        await ui.waitFire()
        needsRedraw = true
    }
}
