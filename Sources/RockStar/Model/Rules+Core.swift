import Foundation

/// What a day advance (`$6F3B`) asks the presentation layer to do next.
enum DayOutcome: Equatable {
    /// Time is stopped (game decided) or the year just ended.
    case none
    case quiet
    /// Friday: show msg 44 then call `payWages()`.
    case wages
    /// Sunday: if `chartShowDue`, run the chart show, then `weeklyRoyalties()`.
    case sunday
    /// Career mode: 31 December has passed; the calendar is back at 1 January.
    case newYear
}

extension GameState {
    // MARK: calendar (rules_core §5)

    static let dayNames = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// `$6F3B`: one day passes. The caller then handles wages/Sunday.
    mutating func advanceDay() -> DayOutcome {
        if gameDecided { return .none }
        dayOfWeek = (dayOfWeek + 1) % 7
        if dayOfMonth == GameState.monthLengths[month] {
            month += 1
            if month == 12 && config.career {
                month = 0; week = 0; dayOfMonth = 1
                salesHistory = [Int](repeating: 0, count: salesHistory.count)
                return .newYear
            }
            if month == 12 {
                guard config.sandbox else {
                    yearOver = true
                    return .none
                }
                month = 0; week = 0
                salesHistory = [Int](repeating: 0, count: salesHistory.count)
            }
            dayOfMonth = 1
        } else {
            dayOfMonth += 1
        }
        switch dayOfWeek {
        case 4: return .wages
        case 6: return .sunday
        default: return .quiet
        }
    }

    /// Weekly wage bill (`$6FA6`).
    var wageBill: Int {
        if config.faithfulBugs {
            // Faithful: pays the first $BF24 slots, not the slots still in the band.
            return (0..<stars).reduce(0) { $0 + wages[$1] }
        }
        return (0..<4).filter { !gone[$0] }.reduce(0) { $0 + wages[$1] }
    }

    /// Friday wages (after msg 44). Returns the amount charged.
    @discardableResult
    mutating func payWages() -> Int {
        let bill = wageBill * config.difficulty.wagePercent / 100
        if !bankrupt { charge(bill) }   // $63EC skips when already bankrupt
        return bill
    }

    /// `$781A` only runs when something has been released.
    var chartShowDue: Bool { albumReleased || singleReleased }

    /// Day advance with all consequences resolved silently (tests, simulation).
    /// Returns the list of outcomes processed.
    @discardableResult
    mutating func advanceDayAuto() -> [DayOutcome] {
        let o = advanceDay()
        var out = [o]
        switch o {
        case .wages: payWages()
        case .sunday:
            if chartShowDue {
                _ = runChartShow()
                out += advanceDayAuto()   // `$781A` ends with its own `$6F3B`
            }
            weeklyRoyalties()
        default: break
        }
        return out
    }

    var dateText: String { "\(GameState.dayNames[dayOfWeek]) \(String(format: "%02d", dayOfMonth)) \(GameState.monthNames[min(month, 11)])" }

    // MARK: rock star records (§3)

    static func wage(of record: RockStarRecord) -> Int {
        let s = record.stats.map(Int.init)
        return 10 * (1000 * s[5] + 100 * s[6] + 10 * s[7] + s[8])
    }

    // MARK: hiring (§7.1, §4.1)

    /// `$6B23`: choose band size n (1...4).
    mutating func beginHiring(count n: Int) {
        hiredCount = n
        stars = n
    }

    /// Accept tape record `r` into `slot` (copies portrait, name, stats, wage).
    mutating func acceptStar(record r: Int, slot: Int) {
        let st = records[r].stats
        starRecord[slot] = r
        starNames[slot] = records[r].name
        image[slot] = st[0]; imageBak[slot] = st[0]
        voice[slot] = st[1]
        ability[slot] = st[2]; abilityBak[slot] = st[2]
        mood[slot] = st[3]; moodBak[slot] = st[3]
        kind[slot] = st[4]
        wages[slot] = GameState.wage(of: records[r])
    }

    /// `$6C7D`: "play with the same rock stars" restore.
    mutating func restoreStars() {
        image = imageBak
        ability = abilityBak
        mood = moodBak
        stars = hiredCount
    }

    /// `$6C65` + `$651C`: set slot status and derive SKILL, FAME and voices.
    mutating func formBand() {
        gone = [true, true, true, true]
        stars = hiredCount
        for i in 0..<stars { gone[i] = false }
        hype = 0
        let n = stars
        var bonus = 0
        switch n {
        case 1:
            bandName = starNames[0]
            for i in 1...3 {
                image[i] = image[0]; ability[i] = ability[0]; voice[i] = voice[0]; kind[i] = kind[0]
            }
        case 2:
            image[2] = image[0]; image[3] = image[1]
            voice[2] = voice[0]
            kind[2] = kind[0]
            if !config.faithfulBugs {
                // Fixed: the original leaves $BF05/$BF06 stale for 2-star bands.
                ability[2] = ability[0]; ability[3] = ability[1]
            }
            bonus = 40
        case 3:
            image[3] = image[0]
            ability[3] = ability[2]
            bonus = 60
        default:
            bonus = 80
        }
        // `$6609` sums 5 bytes: slot 0's backup copy counts twice. 8-bit sums.
        let skillSum = (ability.map(Int.init).reduce(0, +) + Int(abilityBak[0])) & 0xFF
        let fameSum = (image.map(Int.init).reduce(0, +) + Int(imageBak[0]) + bonus) & 0xFF
        skill = skillSum >> 2
        fame = fameSum >> 2
        // `$65C8` music voices; $BEF2 picks the suggested band name.
        bandVoice = Int(kind[0] & 0x80 != 0 ? voice[2] : voice[0]) & 7
    }

    /// `$64A9`: suggested band name from the list at `$C6E2`.
    mutating func suggestBandName() -> String {
        rng.expand(data.bandNames[bandVoice])
    }

    // MARK: equipment (§7.2)

    /// Unit prices (new, second hand, dodgy) by instrument class bits of s4.
    static func gearUnitPrices(kind: UInt8) -> [Int] {
        if kind & 0x80 != 0 { return [500, 300, 200] }
        if kind & 0x40 != 0 { return [1000, 600, 400] }
        if kind & 0x20 != 0 { return [300, 200, 100] }
        return [1000, 700, 300]
    }

    /// `$6683`: NUM0/1/2 prices for the current band.
    var gearCosts: [Int] {
        var t = [0, 0, 0]
        for i in 0..<stars {
            let u = Int(kind[i] & 7)
            let p = GameState.gearUnitPrices(kind: kind[i])
            for q in 0..<3 { t[q] += u * p[q] }
        }
        return t
    }

    mutating func buyEquipment(_ quality: Int) {
        equipment = quality
        charge(gearCosts[quality])
    }

    // MARK: record contracts (§8.1)

    static let contractAdvance = [0, 5_000, 10_000, 20_000, 30_000, 50_000]
    static let labelNames = ["", "FLOPPY DISCS", "ROUGH RECORDS", "S+M RECORDS", "PHONEYGRAM RECORDS", "MEGA BIG RECORDS"]

    func royaltyPercent(tier: Int) -> Int { tier >= 1 && tier <= 5 ? data.royaltyPercent[tier] : 0 }

    /// `$6758`: returns the tier offered this turn, if any (marks it as made
    /// and provisionally signs, like the original).
    mutating func contractOffer() -> Int? {
        guard label == 0, skill >= 60, fame >= 40 else { return nil }
        let tier: Int
        switch fame {
        case ..<70: tier = 1
        case ..<110: tier = 2
        case ..<160: tier = 3
        case ..<250: tier = 4
        default: tier = 5
        }
        if offerMade[tier] { return nil }
        offerMade[tier] = true
        label = tier
        return tier
    }

    mutating func answerContract(accept: Bool) {
        if accept {
            fameUp()
            hypeUp()
            credit(GameState.contractAdvance[label])
        } else {
            label = 0
        }
    }

    // MARK: menu (§4.4)

    enum MenuKind { case basic, withRecord, withRelease }

    var menuKind: MenuKind {
        if label == 0 { return .basic }
        return albumInCan ? .withRelease : .withRecord
    }
}
