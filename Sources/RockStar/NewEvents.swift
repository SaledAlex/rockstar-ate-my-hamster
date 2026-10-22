import Foundation

/// New random events (not in the original). After a turn there's a 1-in-5
/// chance of one; each event happens at most once per game until all have been
/// seen. They use their own random numbers so the original RNG sequence is
/// untouched. Windowed app only (headless runs stay deterministic); start with
/// `--classic-events` to switch them off.
extension Game {
    struct NewEvent {
        let id: Int
        let canHappen: (GameState) -> Bool
        let run: (Game) async -> Void
    }

    /// Name of a random star still in the band.
    func randomStar() -> (slot: Int, name: String)? {
        let live = (0..<4).filter { !state.gone[$0] }
        guard let s = live.randomElement() else { return nil }
        return (s, state.starNames[s])
    }

    func moodChange(_ slot: Int, _ d: Int) {
        state.mood[slot] = UInt8(max(1, min(250, Int(state.mood[slot]) + d)))
    }

    /// Clive speaks free text.
    func cliveSays(_ text: String) async {
        setSpeaker(cecil: false); await ui.sayText(text)
    }

    /// Clive asks; options are short labels (max 13 characters, max 3 options).
    func cliveAsks(_ text: String, _ options: [String]) async -> Int {
        setSpeaker(cecil: false)
        _ = await ui.showText(text)
        return await ui.choose(options, box: options.count == 2 && options.allSatisfy { $0.count <= 3 } ? 2 : 3)
    }

    static let newEvents: [NewEvent] = [
        // 0: festival
        NewEvent(id: 0, canHappen: { $0.fame >= 60 }) { g in
            let fee = 2_000 + g.state.fame * 150
            g.setPhone(true); g.sound?.sfx(1)
            let a = await g.cliveAsks("BOSS! THE GLASTONBERRY FESTIVAL WANTS \(g.state.bandName) TO HEADLINE! "
                + "THEY'LL PAY £\(fee), BUT IT'S THREE DAYS IN A MUDDY FIELD.", ["YES", "NO"])
            g.setPhone(false)
            if a == 0 {
                g.state.credit(fee); g.state.fameUp(); g.state.fameUp(); g.state.skillUp(); g.state.hypeUp()
                for i in 0..<4 where !g.state.gone[i] { g.moodChange(i, -3) }
                await g.cliveSays("WHAT A GIG! THE CROWD WENT WILD. THE BAND ARE STILL WASHING THE MUD OUT OF THEIR HAIR AND THEY'RE NOT HAPPY ABOUT IT.")
                for _ in 0..<3 { await g.day() }
            } else {
                await g.cliveSays("FAIR ENOUGH. A SKIFFLE BAND FROM SWINDON TOOK THE SLOT INSTEAD.")
            }
        },
        // 1: TV show
        NewEvent(id: 1, canHappen: { $0.singleReleased || $0.fame >= 100 }) { g in
            g.setPhone(true); g.sound?.sfx(1)
            let a = await g.cliveAsks("TOP OF THE POPSICLES WANT \(g.state.bandName) ON THE SHOW THIS THURSDAY! "
                + "LIVE TELEVISION, BOSS. WHAT COULD POSSIBLY GO WRONG?", ["YES", "NO"])
            g.setPhone(false)
            guard a == 0 else { await g.cliveSays("PROBABLY WISE. LAST WEEK'S BAND SET FIRE TO THE PRESENTER."); return }
            if Int.random(in: 0..<4) == 0, let s = g.randomStar() {
                g.state.fameDown(); g.state.fameDown(); g.state.hypeUp(); g.state.hypeUp(); g.state.hypeUp()
                await g.cliveSays("DISASTER! \(s.name) SWORE AT THE PRESENTER ON LIVE TV! 20,000 COMPLAINTS... "
                    + "BUT THE KIDS THINK WE'RE DEAD COOL NOW.")
            } else {
                g.state.fameUp(); g.state.fameUp(); g.state.hypeUp()
                await g.cliveSays("THE NATION LOVED IT! MY MUM EVEN SAID THE DRUMMER LOOKED NICE.")
            }
            g.drawPanel()
        },
        // 2: band feud
        NewEvent(id: 2, canHappen: { s in (0..<4).filter { !s.gone[$0] }.count >= 2 }) { g in
            let live = (0..<4).filter { !g.state.gone[$0] }.shuffled()
            let a = live[0], b = live[1]
            let na = g.state.starNames[a], nb = g.state.starNames[b]
            let c = await g.cliveAsks("TROUBLE, BOSS! \(na) AND \(nb) ARE FIGHTING OVER WHO GETS THE BIGGER "
                + "DRESSING ROOM. WHO DO WE BACK?", [String(na.prefix(13)), String(nb.prefix(13)), "PAY £20000"])
            switch c {
            case 0: g.moodChange(a, 5); g.moodChange(b, -5)
                await g.cliveSays("\(na) IS DELIGHTED. \(nb) IS SULKING IN THE CUPBOARD.")
            case 1: g.moodChange(b, 5); g.moodChange(a, -5)
                await g.cliveSays("\(nb) IS DELIGHTED. \(na) HAS LOCKED THEMSELVES IN THE TOUR BUS.")
            default:
                g.state.charge(20_000); g.moodChange(a, 3); g.moodChange(b, 3)
                await g.cliveSays("TWO IDENTICAL DRESSING ROOMS. EVERYONE'S HAPPY EXCEPT THE ACCOUNTANT.")
            }
            g.drawPanel()
        },
        // 3: the hamster
        NewEvent(id: 3, canHappen: { $0.fame >= 30 }) { g in
            guard let s = g.randomStar() else { return }
            let c = await g.cliveAsks("THE PAPERS SAY \(s.name) HAS 'ADOPTED' A HAMSTER. NOBODY HAS SEEN THE "
                + "HAMSTER SINCE. THE PRESS WANT A STATEMENT!", ["DENY IT ALL", "PHOTO SHOOT", "SAY NOTHING"])
            switch c {
            case 0:
                if Bool.random() { g.state.fameUp(); await g.cliveSays("THEY BELIEVED US! THE HAMSTER IS NOW OFFICIALLY 'ON HOLIDAY'.") }
                else { g.state.fameDown(); await g.cliveSays("THEY FOUND A TINY COLLAR IN THE DRESSING ROOM. IT DOESN'T LOOK GOOD.") }
            case 1:
                g.state.charge(5_000); g.state.fameUp(); g.state.fameUp()
                await g.cliveSays("£5000 FOR A RENTED HAMSTER AND A PHOTOGRAPHER. FRONT PAGE: 'HAMSTER ALIVE AND WELL!'")
            default:
                g.state.hypeUp()
                await g.cliveSays("THE MYSTERY ONLY MAKES US MORE DANGEROUS. THE KIDS ARE WEARING HAMSTER T-SHIRTS.")
            }
            g.drawPanel()
        },
        // 4: tax rebate
        NewEvent(id: 4, canHappen: { _ in true }) { g in
            let amount = Int.random(in: 2...15) * 1_000
            g.state.credit(amount)
            await g.cliveSays("A LETTER FROM THE TAXMAN... A REBATE OF £\(amount)! MUST BE A MISTAKE. QUICK, SPEND IT!")
            g.drawPanel()
        },
        // 5: stolen van
        NewEvent(id: 5, canHappen: { _ in true }) { g in
            let c = await g.cliveAsks("BAD VIBES, BOSS! SOMEONE NICKED THE TOUR VAN WITH ALL THE GEAR IN IT. "
                + "REPLACING IT WILL COST £15000.", ["PAY UP", "MAKE DO"])
            if c == 0 { g.state.charge(15_000); await g.cliveSays("NEW VAN, NEW GEAR. IT'S EVEN GOT A CASSETTE PLAYER.") }
            else {
                g.state.skill = max(g.state.skill - 20, 0)
                await g.cliveSays("THE BAND ARE PLAYING ON BORROWED GEAR FROM A SCHOOL BAND. IT SOUNDS... UNIQUE.")
            }
            g.drawPanel()
        },
        // 6: cookbook
        NewEvent(id: 6, canHappen: { $0.fame >= 50 }) { g in
            guard let s = g.randomStar() else { return }
            let c = await g.cliveAsks("A PUBLISHER WANTS \(s.name) TO WRITE A COOKBOOK: 'COOKING WITH GREASE'. "
                + "£25000 ADVANCE. BUT IT'S A BIT NAFF, BOSS.", ["YES", "NO"])
            if c == 0 {
                g.state.credit(25_000); g.moodChange(s.slot, 4); g.state.hypeDown()
                await g.cliveSays("THE BOOK IS A BESTSELLER WITH MUMS. THE FANS ARE LESS IMPRESSED.")
            } else {
                g.state.hypeUp()
                await g.cliveSays("TRUE ROCK AND ROLL INTEGRITY! \(s.name) SULKS AND EATS A SANDWICH.")
                g.moodChange(s.slot, -2)
            }
            g.drawPanel()
        },
        // 7: awards
        NewEvent(id: 7, canHappen: { $0.fame >= 120 }) { g in
            let c = await g.cliveAsks("\(g.state.bandName) ARE NOMINATED AT THE BRIT-ISH AWARDS! "
                + "WE'LL NEED SHINY NEW OUTFITS: £10000. SHALL WE GO?", ["YES", "NO"])
            guard c == 0 else { await g.cliveSays("SUIT YOURSELF. WE'LL WATCH IT ON TELLY WITH A KEBAB."); return }
            g.state.charge(10_000)
            if Bool.random() {
                for _ in 0..<4 { g.state.fameUp() }
                for i in 0..<4 where !g.state.gone[i] { g.moodChange(i, 5) }
                g.sound?.jingle(1)
                await g.cliveSays("WE WON! BEST NEW GROUP! \(g.state.bandName) ARE THE TALK OF THE TOWN, BOSS!")
            } else {
                g.state.fameUp()
                await g.cliveSays("WE LOST TO A NOVELTY CHRISTMAS RECORD ABOUT A DANCING TURKEY. STILL, THE FREE BAR WAS GOOD.")
            }
            g.drawPanel()
        },
        // 8: world tour
        NewEvent(id: 8, canHappen: { $0.fame >= 150 }) { g in
            let c = await g.cliveAsks("BOSS! A PROMOTER WANTS \(g.state.bandName) ON A WORLD TOUR! TOKYO, NEW YORK, "
                + "SYDNEY... AND SCUNTHORPE. IT COSTS £50000 UP FRONT AND TAKES A WEEK.", ["YES", "NO"])
            guard c == 0 else { await g.cliveSays("SHAME. I'D ALREADY PACKED MY SUNGLASSES."); return }
            g.state.charge(50_000)
            for i in 0..<4 where !g.state.gone[i] { g.moodChange(i, -4) }
            if Int.random(in: 0..<3) > 0 {
                let take = g.state.fame * 600
                g.state.credit(take); for _ in 0..<3 { g.state.fameUp() }; g.state.skillUp()
                await g.cliveSays("SOLD OUT EVERYWHERE! WE MADE £\(take). THE BAND ARE JET-LAGGED AND GRUMPY BUT WHO CARES?")
            } else {
                g.state.credit(20_000)
                await g.cliveSays("JAPAN LOVED US. THE REST OF THE WORLD DIDN'T. WE ONLY MADE £20000. SCUNTHORPE WAS NICE THOUGH.")
            }
            for _ in 0..<7 { await g.day() }
        },
        // 9: solo album
        NewEvent(id: 9, canHappen: { s in (0..<4).filter { !s.gone[$0] }.count >= 2 }) { g in
            guard let s = g.randomStar() else { return }
            let c = await g.cliveAsks("\(s.name) WANTS TO MAKE A SOLO ALBUM OF YODELLING CLASSICS. "
                + "IF WE SAY NO, THEY'LL SULK FOR WEEKS.", ["ALLOW IT", "FORBID IT"])
            if c == 0 {
                g.moodChange(s.slot, 8)
                if Bool.random() { g.state.fameUp(); await g.cliveSays("UNBELIEVABLE! IT'S A HIT IN SWITZERLAND. GOOD FOR THE BAND'S PROFILE!") }
                else { g.state.hypeDown(); await g.cliveSays("IT SOLD FOUR COPIES. ALL TO \(s.name)'S MUM. STILL, THEY'RE HAPPY.") }
            } else {
                g.moodChange(s.slot, -6)
                await g.cliveSays("\(s.name) HAS LOCKED THEMSELVES IN THE BOG AND IS YODELLING IN PROTEST.")
            }
            g.drawPanel()
        },
        // 10: autobiography
        NewEvent(id: 10, canHappen: { $0.fame >= 70 }) { g in
            guard let s = g.randomStar() else { return }
            let c = await g.cliveAsks("\(s.name) HAS WRITTEN A TELL-ALL BOOK: 'I WAS A TEENAGE ROCK GOD'. "
                + "IT SAYS RUDE THINGS ABOUT THE REST OF THE BAND!", ["LET IT RUN", "BUY RIGHTS"])
            if c == 0 {
                g.state.fameUp(); g.state.fameUp()
                for i in 0..<4 where !g.state.gone[i] && i != s.slot { g.moodChange(i, -4) }
                await g.cliveSays("THE PAPERS ARE SERIALISING IT! FAME UP... BUT NOBODY IN THE BAND IS SPEAKING TO \(s.name).")
            } else {
                g.state.charge(30_000)
                await g.cliveSays("£30000 AND THE MANUSCRIPT IS IN THE SHREDDER. YOUR SECRETS ARE SAFE, BOSS.")
            }
            g.drawPanel()
        },
        // 11: charity single
        NewEvent(id: 11, canHappen: { $0.fame >= 40 }) { g in
            let c = await g.cliveAsks("BIG NAMES ARE RECORDING A CHARITY SINGLE: 'DO THEY KNOW IT'S TEATIME?'. "
                + "THEY WANT \(g.state.bandName) TO SING A LINE!", ["YES", "NO"])
            if c == 0 {
                g.state.fameUp(); g.state.fameUp(); g.state.hypeUp()
                await g.cliveSays("NUMBER ONE FOR SIX WEEKS! WE GOT ONE WORD: 'TEA'. BUT EVERYONE SAW US SING IT.")
                for _ in 0..<2 { await g.day() }
            } else {
                g.state.fameDown()
                await g.cliveSays("THE PAPERS CALL US HEARTLESS. 'ROCK SCROOGES' IS NOT A GOOD HEADLINE, BOSS.")
            }
            g.drawPanel()
        },
        // 12: rival band diss
        NewEvent(id: 12, canHappen: { $0.fame >= 50 }) { g in
            let rival = g.ui.resolve(80 + Int.random(in: 0..<30))
            let c = await g.cliveAsks("\(rival) TOLD THE MUSIC PAPERS THAT \(g.state.bandName) "
                + "COULDN'T PLAY A KAZOO! WHAT DO WE DO?", ["SLAG THEM", "IGNORE IT", "SUE (£20000)"])
            switch c {
            case 0:
                g.state.hypeUp(); g.state.hypeUp()
                if Bool.random() { g.state.fameUp(); await g.cliveSays("OUR REPLY WAS SO RUDE IT WAS PRINTED WITH STARS IN IT. THE FANS LOVED IT!") }
                else { g.state.fameDown(); await g.cliveSays("THEY HIT BACK HARDER. NOW EVERYONE THINKS WE CAN'T PLAY A KAZOO.") }
            case 1:
                await g.cliveSays("VERY DIGNIFIED, BOSS. NOBODY NOTICED. WHICH IS SORT OF THE PROBLEM.")
            default:
                g.state.charge(20_000)
                if Int.random(in: 0..<5) < 3 { g.state.credit(50_000); await g.cliveSays("WE WON! £50000 IN DAMAGES AND A KAZOO-PLAYING TEST WE PASSED WITH FLYING COLOURS.") }
                else { await g.cliveSays("WE LOST. THE JUDGE HEARD US PLAY AND SIDED WITH THEM.") }
            }
            g.drawPanel()
        },
        // 13: rival manager poaches a star
        NewEvent(id: 13, canHappen: { s in s.fame >= 80 && s.stars >= 2 }) { g in
            guard let s = g.randomStar() else { return }
            let w = g.state.wages[s.slot]
            let c = await g.cliveAsks("A SLIMY RIVAL MANAGER IS TRYING TO STEAL \(s.name)! THEY'LL STAY IF WE "
                + "RAISE THEIR WAGE TO £\(w * 3 / 2) A WEEK.", ["PAY UP", "CALL BLUFF", "LET THEM GO"])
            switch c {
            case 0:
                g.state.wages[s.slot] = w * 3 / 2; g.moodChange(s.slot, 5)
                await g.cliveSays("\(s.name) IS STAYING, AND HAS ALREADY ORDERED A GOLD-PLATED TOOTHBRUSH.")
            case 1 where Bool.random():
                g.moodChange(s.slot, -3)
                await g.cliveSays("IT WAS A BLUFF! \(s.name) IS STAYING, BUT SULKING.")
            default:
                g.state.starLeaves(s.slot)
                await g.cliveSays("\(s.name) HAS GONE. THE PAPERS SAY OUR BAND IS FINISHED. FAME HALVED, BOSS.")
            }
            g.redraw()
        },
        // 14: trashed hotel
        NewEvent(id: 14, canHappen: { $0.stars > 0 }) { g in
            let bill = Int.random(in: 1...5) * 5_000
            let c = await g.cliveAsks("THE BAND THREW A TELLY OUT OF A HOTEL WINDOW. INTO THE POOL. WITH THE "
                + "MAYOR IN IT. THE BILL IS £\(bill).", ["PAY IT", "BLAME FANS"])
            if c == 0 {
                g.state.charge(bill); g.state.hypeUp()
                await g.cliveSays("PAID. THE MAYOR SAYS NO HARD FEELINGS AND WANTS AN AUTOGRAPH.")
            } else {
                g.state.fameDown(); g.state.fameDown()
                await g.cliveSays("THE FANS ARE FURIOUS AT BEING BLAMED. THERE ARE PROTESTS OUTSIDE THE OFFICE.")
            }
            g.drawPanel()
        },
        // 15: fan club
        NewEvent(id: 15, canHappen: { $0.fame >= 60 }) { g in
            let c = await g.cliveAsks("THE OFFICIAL \(g.state.bandName) FAN CLUB HAS 10000 MEMBERS! "
                + "SHALL WE FLOG THEM T-SHIRTS, MUGS AND HAMSTER CAGES?", ["SELL MERCH", "KEEP IT REAL"])
            if c == 0 {
                let take = g.state.fame * 120
                g.state.credit(take); g.state.hypeDown()
                await g.cliveSays("£\(take) IN A WEEK! THE HAMSTER CAGES SOLD OUT FIRST, FUNNILY ENOUGH.")
            } else {
                g.state.hypeUp(); g.state.hypeUp()
                await g.cliveSays("NO SELLING OUT! THE FANS RESPECT US FOR IT. THE ACCOUNTANT IS CRYING.")
            }
            g.drawPanel()
        },
    ]

    static let newEventNames = ["FESTIVAL", "TV SHOW", "BAND FEUD", "HAMSTER SCANDAL", "TAX REBATE",
                                "STOLEN VAN", "COOKBOOK", "AWARDS NIGHT", "WORLD TOUR", "SOLO ALBUM",
                                "AUTOBIOGRAPHY", "CHARITY SINGLE", "RIVAL BAND DISS", "STAR POACHED",
                                "TRASHED HOTEL", "FAN CLUB"]

    /// Called after each turn.
    func maybeNewEvent() async {
        // test aid: RS_FORCE_EVENT=n runs event n after every turn (also headless)
        if let f = ProcessInfo.processInfo.environment["RS_FORCE_EVENT"], let n = Int(f),
           Game.newEvents.indices.contains(n), state.stars > 0, !state.gameDecided {
            await Game.newEvents[n].run(self); setPhone(false); drawPanel(); return
        }
        let cfg = EventSettings.shared
        guard ui.live, !CommandLine.arguments.contains("--classic-events"), cfg.chance > 0,
              !state.gameDecided, state.stars > 0, Int.random(in: 0..<cfg.chance) == 0 else { return }
        let allowed = Game.newEvents.filter { cfg.isOn($0.id) && $0.canHappen(state) }
        var pool = allowed.filter { !usedNewEvents.contains($0.id) }
        if pool.isEmpty {
            usedNewEvents.removeAll()
            pool = allowed
        }
        guard let e = pool.randomElement() else { return }
        usedNewEvents.insert(e.id)
        await e.run(self)
        setPhone(false)
        drawPanel()
    }
}

/// Which new events are switched on, and how often they happen (cheat menu).
/// Remembered between launches.
@MainActor
final class EventSettings {
    static let shared = EventSettings()
    private let d = UserDefaults.standard
    /// One event after every `chance` turns on average; 0 = never.
    static let chances = [2, 3, 5, 10, 0]

    var disabled: Set<Int> {
        get { Set(d.array(forKey: "disabledEvents") as? [Int] ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "disabledEvents") }
    }
    var chance: Int {
        get { d.object(forKey: "eventChance") as? Int ?? 5 }
        set { d.set(newValue, forKey: "eventChance") }
    }
    func isOn(_ id: Int) -> Bool { !disabled.contains(id) }
    func toggle(_ id: Int) { if disabled.contains(id) { disabled.remove(id) } else { disabled.insert(id) } }
    func nextChance() {
        let c = EventSettings.chances
        chance = c[((c.firstIndex(of: chance) ?? 2) + 1) % c.count]
    }
    var chanceLabel: String { chance == 0 ? "NEVER" : "1 IN \(chance) TURNS" }
}
