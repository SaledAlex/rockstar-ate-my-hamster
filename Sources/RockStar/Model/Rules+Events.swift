import Foundation

enum Disaster: Equatable {
    case sued          // msg 120
    case taxman        // msg 121
    case equipmentLost(quality: Int)   // msg 119 / 118 / 117, then re-buy (msg 116)
}

/// Result of the pre-show mood check `$74B5`.
enum MoodEvent: Equatable {
    /// Everyone content (moods -1); optional disaster from the 1-in-~7 check.
    case content(Disaster?)
    /// msg 209: show-improvement demand, YES/NO.
    case demand(slot: Int, cost: Int)
    /// msg 213 then msg 212: the star quits outright (successful bands).
    case quits(slot: Int)
    /// msg 211: ultimatum, YES/NO (NO = fired).
    case ultimatum(slot: Int, cost: Int)
    /// msg 37: trouble after the show; call `troubleHeadline()` then `payStarBill`.
    case trouble(slot: Int, cost: Int)
}

enum PublicityResult: Equatable {
    /// Headline 132...135 with side story 136...138; nothing happens.
    case nobodyCares(headline: Int, side: Int)
    /// Headline 140...144 about a band member; 144 kills `victim`.
    case bandStory(headline: Int, side: Int, victim: Int, died: Bool)
}

enum PeriodicEvent { case none, charity, bootleg }

extension GameState {
    // MARK: practice (rules_gigs §2)

    static let practiceCostPerDay = 100

    /// Pay for `days` practice days up front. Returns false if that bankrupted us.
    mutating func startPractice(days: Int) -> Bool {
        if !bankrupt { charge(GameState.practiceCostPerDay * days) }
        return !bankrupt
    }

    /// One practice day before the disaster check and the day advance.
    mutating func practiceDay() {
        skillUp()
        hypeDown()
        rng.reseed()   // reseed + practice tune ($80EE)
    }

    // MARK: disasters `$7260` (rules_core §6.5)

    var cashAtLeastMillion: Bool { cash >= 1_000_000 }

    mutating func disasterCheck() -> Disaster? {
        guard discs[0], cashAtLeastMillion else { return nil }
        if oneShot & 1 == 0, rng.rnd(4) == 3, discs[1] {
            oneShot |= 1
            charge(1_000_000)
            return .sued
        }
        if oneShot & 2 == 0, rng.rnd(1) == 1, discs[2] {
            oneShot |= 2
            charge(1_000_000)
            return .taxman
        }
        if oneShot & 4 == 0 {
            oneShot |= 4
            return .equipmentLost(quality: equipment)
        }
        return nil
    }

    // MARK: gigs (rules_gigs §3)

    static let venueSeats = [200, 500, 1_500, 4_000, 10_000]
    static let venueHire = [10, 1_000, 2_800, 7_000, 16_500]
    static let venueNames = ["PUB", "CLUB", "UNIVERSITY", "CONCERT HALL", "STADIUM"]
    static let ticketPrices = [2, 5, 10, 15, 20]
    static let demandPerFame = [9, 6, 4, 2, 1]

    /// `$6D06`: tickets = min(fame*10*DEMAND[p], seats[v]); takings = tickets*price.
    static func ticketSales(fame: Int, venue: Int, price: Int) -> (tickets: Int, takings: Int) {
        let tickets = min(fame * 10 * demandPerFame[price], venueSeats[venue])
        return (tickets, tickets * ticketPrices[price])
    }

    /// Pay venue hire for the whole tour; sponsor costs 20 fame. False if bankrupt.
    mutating func startTour(venue: Int, nights: Int) -> Bool {
        if !bankrupt { charge(GameState.venueHire[venue] * nights) }
        if bankrupt { return false }
        firstNight = true   // $BEB3 = 2
        if sponsor != 0 { fameDown(); fameDown() }   // $82E1/$82E4
        return true
    }

    /// One show after the mood check: takings, SKILL+10, hype+1, FAME +/-10.
    mutating func playGig(venue: Int, price: Int) -> (tickets: Int, takings: Int) {
        let r = GameState.ticketSales(fame: fame, venue: venue, price: price)
        credit(r.takings)
        skillUp()
        hypeUp()
        if skill >= 70 { fameUp() } else { fameDown() }
        return r
    }

    // MARK: moods (rules_gigs §4, rules_events §9)

    /// `$7603`: lowest mood among live stars (ties -> last); sets `currentStar`.
    mutating func unhappiestStar() -> (mood: Int, slot: Int) {
        var m = 0xFF, slot = 0
        for i in 0..<4 where !gone[i] && Int(mood[i]) <= m {
            m = Int(mood[i]); slot = i
        }
        currentStar = slot
        return (m, slot)
    }

    /// `$75E4`: every mood -1 (0 and 255 are skipped).
    mutating func allMoodsDown() {
        for i in 0..<4 where mood[i] != 0 && mood[i] != 0xFF { mood[i] -= 1 }
    }

    /// `$75E0`: every mood +1 (0 and 255 are skipped, 8-bit).
    mutating func allMoodsUp() {
        for i in 0..<4 where mood[i] != 0 && mood[i] != 0xFF { mood[i] &+= 1 }
    }

    mutating func moodCheck() -> MoodEvent {
        let (m, i) = unhappiestStar()
        if m >= 9 {
            allMoodsDown()
            firstNight = false
            if rng.rnd(10) == 7 { return .content(disasterCheck()) }
            return .content(nil)
        }
        let cost = (rng.rnd(8) + 1) * 10_000
        if m >= 4 {
            firstNight = false
            if discs[2] { starLeaves(i); return .quits(slot: i) }
            return .demand(slot: i, cost: cost)
        }
        if rng.rnd(2) == 1 && !firstNight {
            let bill = (rng.rnd(7) + 1) * 10_000
            return .trouble(slot: i, cost: bill)
        }
        firstNight = false
        if discs[1] { starLeaves(i); return .quits(slot: i) }
        return .ultimatum(slot: i, cost: cost)
    }

    /// msg 209 answer.
    mutating func answerDemand(slot: Int, cost: Int, pay: Bool) {
        if pay {
            charge(cost)
            allMoodsDown()
            mood[slot] = 15
        } else {
            mood[slot] = 2
        }
    }

    /// msg 211 answer; NO fires the star (msg 212).
    mutating func answerUltimatum(slot: Int, cost: Int, pay: Bool) {
        if pay {
            charge(cost)
            allMoodsDown()
            mood[slot] = 20
        } else {
            starLeaves(slot)
        }
    }

    /// After msg 37: true = jailed (headline 166, msg 168), false = wrecked (165, msg 167).
    mutating func troubleHeadline() -> Bool {
        let jailed = rng.rnd(2) == 1
        if jailed { rng.reseed() }
        return jailed
    }

    /// Bill for trouble after the show (paid automatically).
    mutating func payStarBill(slot: Int, cost: Int) {
        charge(cost)
        allMoodsDown()
        mood[slot] = 15
    }

    /// `$7565`: star gone, FAME halved.
    mutating func starLeaves(_ slot: Int) {
        gone[slot] = true
        stars -= 1
        halveFame()
    }

    // MARK: gifts (rules_events §8)

    static let giftPrices = [20_000, 10_000, 5_000, 100, 50, 1]

    /// Returns the bill (msg 167 NUM0).
    @discardableResult
    mutating func giveGifts(_ choice: Int) -> Int {
        let bill = GameState.giftPrices[choice] * stars
        for _ in 0..<(12 - choice) { allMoodsUp() }
        charge(bill)
        return bill
    }

    // MARK: publicity (rules_events §6)

    /// Call after msg 131.
    mutating func publicityStunt() -> PublicityResult {
        if rng.rnd(3) >= 2 {
            rng.reseed()
            var h: Int
            repeat { h = 132 + (rng.rnd(6) >> 1) } while h == lastHeadline
            lastHeadline = h
            let side = rng.rnd(2) + 136
            return .nobodyCares(headline: h, side: side)
        }
        rng.reseed()
        var h: Int
        repeat { h = rng.rnd(4) + 140 } while h == lastHeadline
        lastHeadline = h
        if h == 143 { badPress() }
        // INFERRED: order of the side-story and portrait draws inside $8032.
        let side = rng.rnd(3) + 132
        let victim = pickRandomLiveStar()
        currentStar = victim
        var died = false
        if h == 144 {
            gone[victim] = true
            stars -= 1
            died = true
        }
        return .bandStory(headline: h, side: side, victim: victim, died: died)
    }

    /// `$81DD`: i = rnd(stars-1), then skip forward past gone slots.
    mutating func pickRandomLiveStar() -> Int {
        var i = stars > 1 ? rng.rnd(stars - 1) : 0
        var guardCount = 0
        // INFERRED: the original walks past slot 3 into junk if needed; wrap instead.
        while gone[i % 4] && guardCount < 4 { i += 1; guardCount += 1 }
        return i % 4
    }

    /// `$7FF6`
    mutating func badPress() {
        if sponsorPatience > 0 { sponsorPatience -= 1 }
    }

    // MARK: per-turn scheduler `$6ADF` (rules_events §2)

    /// Decrement the turn counter; returns which periodic check is due.
    mutating func tickEventCounter() -> PeriodicEvent {
        eventCounter -= 1
        if eventCounter == 0 { eventCounter = 15; return .charity }
        if eventCounter == 3 { return .bootleg }
        return .none
    }

    // MARK: charity (§3)

    var charityEligible: Bool { hype >= 10 && fame >= 100 }

    /// After msg 8 + yes/no. Returns whether the charity was real (msg 11/9 vs 12/10)
    /// and the newspaper headline to show, if any (193/194).
    mutating func answerCharity(accept: Bool) -> (real: Bool, headline: Int?) {
        let real = rng.rnd(15) & 1 == 1
        switch (real, accept) {
        case (true, true): hypeUp(); fameUp(); return (true, nil)
        case (true, false): halveFame(); badPress(); return (true, 193)
        case (false, true): hypeUp(); halveFame(); badPress(); return (false, 194)
        case (false, false): return (false, nil)
        }
    }

    // MARK: sponsorship (§4)

    static let sponsorNames = ["JOKA COLA", "BULLWISER BEER", "SOMA ELECTRICS", "LIEVIE JEANS", "FRAUD CARS"]

    /// `$A3E6` when unsponsored: returns the company index 0...4 offering.
    mutating func sponsorOffer() -> Int? {
        guard sponsor == 0, fame >= 150, rng.rnd(10) == 7 else { return nil }
        let c = rng.rnd(4)
        if sponsorOffered[c] { return nil }
        sponsorOffered[c] = true
        sponsor = c + 1
        return c
    }

    mutating func answerSponsor(accept: Bool) {
        if accept {
            credit(100_000)
            sponsorPatience = 10
        } else {
            sponsor = 0
        }
    }

    /// `$A45E`: sponsor pulls out when patience hits 0 (msg 169).
    var sponsorPullOutDue: Bool { sponsor != 0 && sponsorPatience == 0 }

    mutating func sponsorPullOut() {
        charge(100_000)
        sponsor = 0
    }

    /// `$6A87`: returns the sponsor (1...5) whose scandal breaks (msg 202 + headline 202+s).
    mutating func sponsorScandalTick() -> Int? {
        guard sponsor != 0 else { return nil }
        scandalCounter &-= 1
        guard scandalCounter == 0 else { return nil }
        if !config.faithfulBugs {
            // Fixed: the original never reloads $BECE (next scandal after 256 turns).
            scandalCounter = 20
        }
        halveFame()
        return sponsor
    }

    // MARK: bootleggers (§5)

    var bootlegEligible: Bool { !bootlegDone && chartShowDue && fame >= 200 }

    mutating func startBootleg() {
        bootlegDone = true
        piracy = true
    }

    /// Menu msg 171 choice -> (message id, cost charged).
    mutating func resolveBootleg(_ choice: Int) -> (message: Int, cost: Int) {
        var msg = 173, cost = 0
        switch choice {
        case 1:
            if rng.rnd(2) == 2 { cost = (rng.rnd(3) + 1) * 100_000; msg = 174 }
            else { cost = (rng.rnd(8) + 1) * 10_000; msg = 175; piracy = false }
        case 2:
            if rng.rnd(2) == 2 { cost = (rng.rnd(8) + 1) * 10_000; msg = 177; piracy = false }
            else { cost = (rng.rnd(8) + 1) * 10_000; msg = 176 }
        case 3:
            cost = (rng.rnd(3) + 1) * 100_000; msg = 172
            // Faithful: "THAT'S STOPPED THEM" but piracy stays active.
            if !config.faithfulBugs { piracy = false }
        default: break
        }
        if cost > 0 { charge(cost) }
        return (msg, cost)
    }
}
