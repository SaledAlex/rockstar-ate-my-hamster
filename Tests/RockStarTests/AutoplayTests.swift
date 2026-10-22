import XCTest
@testable import RockStar

/// Plays whole games through the model with a simple manager policy, in the
/// same call order Game.swift uses. Checks invariants and that games end.
final class AutoplayTests: XCTestCase {
    static let assets = try! Assets.load()

    struct Policy {
        var s: GameState
        var log: [String] = []

        mutating func day() {
            let o = s.advanceDay()
            switch o {
            case .wages: s.payWages()
            case .sunday:
                if s.chartShowDue { _ = s.runChartShow(); day() }
                s.weeklyRoyalties()
            default: break
            }
        }

        mutating func disaster(_ d: Disaster?) {
            if case .equipmentLost = d { s.buyEquipment(2) }
        }

        mutating func turn() {
            if let tier = s.contractOffer() { s.answerContract(accept: true); log.append("signed tier \(tier)") }
            let minMood = (0..<4).filter { !s.gone[$0] }.map { Int(s.mood[$0]) }.min() ?? 99
            if minMood < 12 {
                s.giveGifts(5); day()
            } else if s.skill < 70 {
                if s.startPractice(days: 5) {
                    for _ in 0..<5 {
                        s.practiceDay(); disaster(s.disasterCheck())
                        if s.bankrupt { break }
                        day(); if s.gameDecided { break }
                    }
                }
            } else if s.label != 0 && !s.albumInCan && !s.albumReleased && s.cash > 60_000 {
                s.startRecording(studio: 5)
                day()
                if !(s.bankrupt || s.yearOver) {
                    while s.tracksCut < 10 {
                        for _ in 0..<s.daysPerTrack { day() }
                        if s.bankrupt || s.yearOver { break }
                        if s.dialAccident() { continue }
                        s.nameTrack(s.suggestTrackName())
                    }
                    if s.tracksCut == 10 {
                        s.finishRecording()
                        if s.producerRansomDue() { s.answerRansom(pay: s.cash > 2_000_000) }
                        log.append("recorded album")
                    }
                }
            } else if s.albumInCan && !s.albumReleased {
                s.releaseAlbum(named: "GREATEST HITS"); day(); log.append("album out")
            } else if s.albumReleased && (!s.singleReleased || (s.climbWeeks & 0x80 != 0 && s.singlePos > 6)) && s.cash > 100_000 && s.hype >= 10 {
                let t = (0..<10).first { !s.releasedTracks[$0] } ?? 0
                s.beginSingle(track: t)
                s.makeVideo(director: 2, location: 2, feature: 0)
                s.launchSingle(); day()
                log.append("single \(t)")
            } else {
                // best affordable gig: max takings per night minus hire
                var best = (v: 0, p: 0, net: Int.min)
                for v in 0..<5 { for p in 0..<5 {
                    let net = GameState.ticketSales(fame: s.fame, venue: v, price: p).takings - GameState.venueHire[v]
                    if net > best.net && GameState.venueHire[v] * 3 < s.cash { best = (v, p, net) }
                } }
                if s.startTour(venue: best.v, nights: 3) {
                    for _ in 0..<3 {
                        day(); if s.gameDecided { break }
                        switch s.moodCheck() {
                        case .content(let d): disaster(d)
                        case .demand(let i, let c): s.answerDemand(slot: i, cost: c, pay: c < s.cash / 4)
                        case .ultimatum(let i, let c): s.answerUltimatum(slot: i, cost: c, pay: c < s.cash / 2)
                        case .trouble(let i, let c): _ = s.troubleHeadline(); s.payStarBill(slot: i, cost: c)
                        case .quits: break
                        }
                        if s.stars == 0 || s.bankrupt { break }
                        _ = s.playGig(venue: best.v, price: best.p)
                    }
                }
            }
            // $6ADF
            if s.gameDecided { return }
            if s.sponsor == 0 {
                if s.sponsorOffer() != nil { s.answerSponsor(accept: true); day() }
            } else if s.sponsorPullOutDue { s.sponsorPullOut(); day() }
            switch s.tickEventCounter() {
            case .charity: if s.charityEligible { _ = s.answerCharity(accept: true); day() }
            case .bootleg: if s.bootlegEligible { s.startBootleg(); _ = s.resolveBootleg(2); day() }
            case .none: break
            }
            _ = s.sponsorScandalTick()
        }
    }

    func playGame(seed: UInt64, faithful: Bool) -> Policy {
        var st = GameState(data: Self.assets.gameData, records: Self.assets.rockStars,
                           config: GameConfig(faithfulBugs: faithful), seed: seed)
        let names = ["FRANK ZIPPER", "STRING", "TITCHY BLACKHEAD", "ANNIE SMALLPOX"]
        st.beginHiring(count: 4)
        for (i, n) in names.enumerated() {
            st.acceptStar(record: Self.assets.rockStars.firstIndex { $0.name == n }!, slot: i)
        }
        var p = Policy(s: st)
        p.day()
        p.s.formBand()
        p.s.buyEquipment(0)
        var turns = 0
        while !p.s.gameDecided && turns < 2000 {
            p.turn()
            turns += 1
            XCTAssertTrue((0...GameState.cashCap).contains(p.s.cash))
            XCTAssertTrue((0...255).contains(p.s.fame) && (0...255).contains(p.s.skill))
            XCTAssertTrue((0...15).contains(p.s.hype))
            XCTAssertTrue((0...4).contains(p.s.stars))
        }
        XCTAssertTrue(p.s.gameDecided, "seed \(seed) did not finish")
        return p
    }

    func testWholeGamesFinish() {
        var outcomes: [String: Int] = [:]
        var bestDisc = 0, signed = 0, albums = 0
        for seed in 1...30 as ClosedRange<UInt64> {
            for faithful in [true, false] {
                let p = playGame(seed: seed, faithful: faithful)
                let end = p.s.won ? "won" : p.s.bankrupt ? "bankrupt" : p.s.yearOver ? "time" : "no stars"
                outcomes[end, default: 0] += 1
                bestDisc = max(bestDisc, p.s.discPoints)
                if p.log.contains(where: { $0.hasPrefix("signed") }) { signed += 1 }
                if p.log.contains("album out") { albums += 1 }
            }
        }
        print("autoplay outcomes:", outcomes, "signed:", signed, "albums:", albums, "best disc points:", bestDisc)
        XCTAssertEqual(outcomes.values.reduce(0, +), 60)
    }
}
