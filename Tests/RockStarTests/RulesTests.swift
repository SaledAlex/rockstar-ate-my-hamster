import XCTest
@testable import RockStar

/// Rule checks against the worked numbers in notes/rules_*.md.
final class RulesTests: XCTestCase {
    static let assets = try! Assets.load()
    static let data = assets.gameData
    static let stars = assets.rockStars

    func makeState(faithful: Bool = true, seed: UInt64 = 42) -> GameState {
        GameState(data: Self.data, records: Self.stars, config: GameConfig(faithfulBugs: faithful), seed: seed)
    }

    func index(of name: String) -> Int { Self.stars.firstIndex { $0.name == name }! }

    // MARK: RNG

    func testRNGTableAndCounts() {
        let t = Self.data.rngTable
        XCTAssertEqual(t, [11, 13, 8, 4, 3, 3, 14, 10, 14, 14, 5, 15, 6, 4, 0, 13, 8, 3, 1, 7, 1, 2, 10, 10, 14, 5, 7, 15, 5, 2, 6, 8,
                           4, 5, 2, 3, 10, 12, 11, 7, 13, 0, 15, 3, 8, 2, 1, 7, 5, 9, 15, 7, 3, 9, 6, 13, 12, 15, 6, 1, 13, 8, 7, 0])
        let counts = (0...15).map { v in t.filter { Int($0) == v }.count }
        XCTAssertEqual(counts, [3, 4, 4, 6, 3, 5, 4, 6, 5, 2, 4, 2, 2, 5, 4, 5])
    }

    func testRNGDistribution() {
        let rng = SpectrumRNG(table: Self.data.rngTable, seed: 1)
        // rules_gigs: A51F(2): 0=26/64, 1=20/64, 2=18/64; A51F(10)==7 is 9/64
        XCTAssertEqual(rng.probability(of: 0, n: 2), 26.0 / 64)
        XCTAssertEqual(rng.probability(of: 1, n: 2), 20.0 / 64)
        XCTAssertEqual(rng.probability(of: 2, n: 2), 18.0 / 64)
        XCTAssertEqual(rng.probability(of: 7, n: 10), 9.0 / 64)
        // rules_records: rand(1): 0 62.5 %, 1 37.5 %; rand(4) 0 17.2 %, 4 23.4 %
        XCTAssertEqual(rng.probability(of: 0, n: 1), 0.625)
        XCTAssertEqual(rng.probability(of: 1, n: 1), 0.375)
        XCTAssertEqual(rng.probability(of: 0, n: 4), 11.0 / 64)
        XCTAssertEqual(rng.probability(of: 4, n: 4), 15.0 / 64)
        // rnd(n >= 15) is the table itself; rnd(20) never exceeds 15
        XCTAssertEqual(rng.probability(of: 3, n: 20), 6.0 / 64)
    }

    func testRNGWalksTableSequentially() {
        var rng = SpectrumRNG(table: Self.data.rngTable, seed: 1)
        rng.index = 0
        XCTAssertEqual(rng.rnd(15), 11)
        XCTAssertEqual(rng.rnd(15), 13)
        XCTAssertEqual(rng.rnd(4), 4)      // skips 8, takes 4
        XCTAssertEqual(rng.index, 4)
        rng.index = 63
        XCTAssertEqual(rng.rnd(0), 0)      // index 63 = 0
        XCTAssertEqual(rng.index, 0)
        var hist = [Int](repeating: 0, count: 3)
        for _ in 0..<6400 { hist[rng.rnd(2)] += 1 }
        XCTAssertEqual(hist.reduce(0, +), 6400)
        XCTAssertTrue(hist.allSatisfy { $0 > 1000 })
    }

    // MARK: money

    func testChargeBankruptsAndCreditCaps() {
        var s = makeState()
        s.cash = 1000
        s.charge(1000)
        XCTAssertEqual(s.cash, 0); XCTAssertFalse(s.bankrupt)
        s.charge(1)
        XCTAssertTrue(s.bankrupt); XCTAssertEqual(s.cash, 0)
        s.cash = 99_999_000
        s.credit(5_000)
        XCTAssertEqual(s.cash, 99_999_999)
    }

    // MARK: calendar

    func testCalendar() {
        var s = makeState()
        s.beginHiring(count: 1); s.acceptStar(record: 10, slot: 0); s.formBand()
        s.wages = [0, 0, 0, 0]
        XCTAssertEqual(s.dateText, "MON 01 JAN")
        var outcomes: [DayOutcome] = []
        for _ in 0..<6 { outcomes.append(s.advanceDay()) }
        // FRI 5 JAN wages, SUN 7 JAN charts/royalties
        XCTAssertEqual(outcomes, [.quiet, .quiet, .quiet, .wages, .quiet, .sunday])
        XCTAssertEqual(s.dateText, "SUN 07 JAN")
        s.weeklyRoyalties()   // the first Sunday was advanced manually above
        // Run to the end of the year: 364 advances from 1 Jan reach 31 Dec (a Monday).
        for _ in 6..<364 { s.advanceDayAuto() }
        XCTAssertEqual(s.dateText, "MON 31 DEC")
        XCTAssertFalse(s.yearOver)
        XCTAssertEqual(s.week, 52)
        s.advanceDayAuto()
        XCTAssertTrue(s.yearOver)
        XCTAssertEqual(s.advanceDay(), .none)   // time has stopped
    }

    func testMonthLengthsNoLeapYear() {
        var s = makeState()
        s.beginHiring(count: 1); s.acceptStar(record: 10, slot: 0); s.formBand()
        for _ in 0..<58 { _ = s.advanceDay() }
        XCTAssertEqual(s.dateText.suffix(6), "28 FEB")
        _ = s.advanceDay()
        XCTAssertEqual(s.dateText.suffix(6), "01 MAR")
    }

    // MARK: stars, wages, band stats, gear

    func testWagesFromStatBytes() {
        XCTAssertEqual(GameState.wage(of: Self.stars[index(of: "WACKY JACKO")]), 18_000)
        XCTAssertEqual(GameState.wage(of: Self.stars[index(of: "SIDNEY SPARKLE")]), 50)
        XCTAssertEqual(GameState.wage(of: Self.stars[index(of: "BILL COLLINS")]), 30_000)
        XCTAssertEqual(GameState.wage(of: Self.stars[index(of: "HARVEY HEADBAND")]), 7_490)
        // rules_core: two wages 18,000 + 680 charged from 100,000 -> 81,320
        var s = makeState()
        s.beginHiring(count: 2)
        s.acceptStar(record: index(of: "WACKY JACKO"), slot: 0)
        s.acceptStar(record: index(of: "JANE JET"), slot: 1)
        s.formBand()
        s.cash = 100_000
        XCTAssertEqual(s.payWages(), 18_680)
        XCTAssertEqual(s.cash, 81_320)
    }

    func testWagesQuirkPaysFirstSlots() {
        for faithful in [true, false] {
            var s = makeState(faithful: faithful)
            s.beginHiring(count: 2)
            s.acceptStar(record: index(of: "WACKY JACKO"), slot: 0)
            s.acceptStar(record: index(of: "JANE JET"), slot: 1)
            s.formBand()
            s.starLeaves(1)   // Jane goes; 1 star left
            // faithful: pays slot 0 only (first $BF24 = 1 slots) -> 18,000 either way here
            XCTAssertEqual(s.wageBill, 18_000)
            s.formBand()
            s.starLeaves(0)   // Jacko goes; Jane remains in slot 1
            XCTAssertEqual(s.wageBill, faithful ? 18_000 : 680)
        }
    }

    func testBandDerivation() {
        var s = makeState()
        s.beginHiring(count: 2)
        s.acceptStar(record: index(of: "WACKY JACKO"), slot: 0)   // image 30, skill 14
        s.acceptStar(record: index(of: "ELVIN DWIGHT"), slot: 1)  // image 15, skill 14
        s.formBand()
        // SKILL = (2*14 + 14 + stale 9 + stale 7) / 4 = 14 ; FAME = (30*2+15+30+15 + 40)/4 = 40
        XCTAssertEqual(s.skill, 14)
        XCTAssertEqual(s.fame, 40)
        XCTAssertEqual(s.hype, 0)
        var f = makeState(faithful: false)
        f.beginHiring(count: 2)
        f.acceptStar(record: index(of: "WACKY JACKO"), slot: 0)
        f.acceptStar(record: index(of: "ELVIN DWIGHT"), slot: 1)
        f.formBand()
        XCTAssertEqual(f.skill, (14 * 2 + 14 + 14 + 14) / 4)

        var one = makeState()
        one.beginHiring(count: 1)
        one.acceptStar(record: index(of: "BILL COLLINS"), slot: 0)   // image 19, skill 15
        one.formBand()
        XCTAssertEqual(one.skill, 15 * 5 / 4)
        XCTAssertEqual(one.fame, 19 * 5 / 4)
        XCTAssertEqual(one.bandName, "BILL COLLINS")

        var four = makeState()
        four.beginHiring(count: 4)
        for (i, n) in ["WACKY JACKO", "BILL COLLINS", "DEREK CLAPTOUT", "KATE BUSHED"].enumerated() {
            four.acceptStar(record: index(of: n), slot: i)
        }
        four.formBand()
        XCTAssertEqual(four.skill, (14 * 2 + 15 + 15 + 10) / 4)
        XCTAssertEqual(four.fame, (30 * 2 + 19 + 27 + 7 + 80) / 4)
    }

    func testGearCosts() {
        var s = makeState()
        s.beginHiring(count: 1)
        s.acceptStar(record: index(of: "WACKY JACKO"), slot: 0)   // $1F
        s.formBand()
        XCTAssertEqual(s.gearCosts, [7000, 4900, 2100])
        var d = makeState()
        d.beginHiring(count: 1)
        d.acceptStar(record: index(of: "BILL COLLINS"), slot: 0)  // $8F
        d.formBand()
        XCTAssertEqual(d.gearCosts, [3500, 2100, 1400])
        d.cash = 3000
        d.buyEquipment(0)
        XCTAssertTrue(d.bankrupt)
    }

    // MARK: gigs

    func testTicketFormula() {
        // rules_gigs: fame 23 in a stadium; formula tickets = min(fame*10*DEMAND, seats)
        let r = (0..<5).map { GameState.ticketSales(fame: 23, venue: 4, price: $0).takings }
        // NOTE: the notes print £4140 for the £5 price, but the simulator-verified
        // formula gives 1380 tickets x £5 = £6900 (typo in the notes).
        XCTAssertEqual(r, [4140, 6900, 9200, 6900, 4600])
        // capacity caps
        XCTAssertEqual(GameState.ticketSales(fame: 100, venue: 0, price: 0).tickets, 200)
        XCTAssertEqual(GameState.ticketSales(fame: 100, venue: 0, price: 0).takings, 400)
        XCTAssertEqual(GameState.ticketSales(fame: 255, venue: 4, price: 4).takings, 2550 * 20)
        XCTAssertEqual(GameState.ticketSales(fame: 255, venue: 4, price: 0).tickets, 10_000)
        XCTAssertEqual(GameState.ticketSales(fame: 1, venue: 1, price: 4).tickets, 10)
        // full grid against the formula as written in the notes
        let seats = [200, 500, 1500, 4000, 10000], price = [2, 5, 10, 15, 20], m = [9, 6, 4, 2, 1]
        for v in 0..<5 { for p in 0..<5 { for fame in [1, 10, 23, 40, 70, 100, 150, 200, 255] {
            let t = min(fame * 10 * m[p], seats[v])
            XCTAssertEqual(GameState.ticketSales(fame: fame, venue: v, price: p).takings, t * price[p])
        } } }
    }

    func testGigNightEffects() {
        var s = makeState()
        s.beginHiring(count: 1); s.acceptStar(record: index(of: "WACKY JACKO"), slot: 0); s.formBand()
        s.skill = 65; s.fame = 50; s.cash = 10_000
        XCTAssertTrue(s.startTour(venue: 1, nights: 3))
        XCTAssertEqual(s.cash, 7_000)
        let r = s.playGig(venue: 1, price: 2)
        XCTAssertEqual(r.tickets, 500); XCTAssertEqual(r.takings, 5000)
        XCTAssertEqual(s.skill, 75); XCTAssertEqual(s.fame, 60); XCTAssertEqual(s.hype, 1)
        s.skill = 30
        _ = s.playGig(venue: 1, price: 2)
        XCTAssertEqual(s.fame, 50)   // skill 30+10 = 40 < 70: fame -10
    }

    func testPracticeAndGifts() {
        var s = makeState()
        s.beginHiring(count: 2)
        s.acceptStar(record: 0, slot: 0); s.acceptStar(record: 1, slot: 1); s.formBand()
        s.cash = 1000; s.hype = 3
        XCTAssertTrue(s.startPractice(days: 5))
        XCTAssertEqual(s.cash, 500)
        let sk = s.skill
        s.practiceDay()
        XCTAssertEqual(s.skill, sk + 10); XCTAssertEqual(s.hype, 2)
        s.mood = [40, 32, 0, 255]
        s.cash = 100_000
        XCTAssertEqual(s.giveGifts(0), 40_000)        // £20,000 x 2 stars
        XCTAssertEqual(Array(s.mood[0..<2]), [52, 44])  // +12
        XCTAssertEqual(s.mood[2], 0); XCTAssertEqual(s.mood[3], 255)
        XCTAssertEqual(s.giveGifts(5), 2)             // comics £1, +7
        XCTAssertEqual(s.mood[0], 59)
    }

    func testMoodCheckBranches() {
        var s = makeState()
        s.beginHiring(count: 2)
        s.acceptStar(record: 0, slot: 0); s.acceptStar(record: 1, slot: 1); s.formBand()
        s.mood = [20, 6, 9, 9]
        if case .demand(let slot, let cost) = s.moodCheck() {
            XCTAssertEqual(slot, 1)
            XCTAssertTrue((10_000...90_000).contains(cost) && cost % 10_000 == 0)
            s.cash = 1_000_000
            s.answerDemand(slot: slot, cost: cost, pay: true)
            XCTAssertEqual(s.mood[0], 19); XCTAssertEqual(s.mood[1], 15)
        } else { XCTFail("expected demand") }
        s.mood = [20, 2, 0, 0]
        s.discs[1] = true   // successful band: unhappy star just quits (unless trouble)
        s.firstNight = true // first night: no trouble possible
        let fame = s.fame
        XCTAssertEqual(s.moodCheck(), .quits(slot: 1))
        XCTAssertEqual(s.stars, 1)
        XCTAssertEqual(s.fame, (fame >> 1) | 1)
    }

    // MARK: contracts, royalties, discs

    func testContractTiers() {
        let expected: [(Int, Int?)] = [(39, nil), (40, 1), (69, 1), (70, 2), (109, 2), (110, 3), (159, 3), (160, 4), (249, 4), (250, 5), (255, 5)]
        for (fame, tier) in expected {
            var s = makeState()
            s.skill = 60; s.fame = fame
            XCTAssertEqual(s.contractOffer(), tier, "fame \(fame)")
        }
        var s = makeState()
        s.skill = 59; s.fame = 100
        XCTAssertNil(s.contractOffer())
        s.skill = 60
        XCTAssertEqual(s.contractOffer(), 2)
        s.answerContract(accept: false)
        XCTAssertEqual(s.label, 0)
        XCTAssertNil(s.contractOffer())       // tier 2 offered once only
        s.fame = 110
        XCTAssertEqual(s.contractOffer(), 3)
        s.cash = 0
        s.answerContract(accept: true)
        XCTAssertEqual(s.cash, 20_000); XCTAssertEqual(s.fame, 120); XCTAssertEqual(s.hype, 1)
        XCTAssertEqual(s.royaltyPercent(tier: 3), 10)
        XCTAssertEqual(s.menuKind, .withRecord)
        XCTAssertEqual((1...5).map { s.royaltyPercent(tier: $0) }, [3, 5, 10, 15, 20])
        XCTAssertEqual(GameState.contractAdvance[1...5].map { $0 }, [5_000, 10_000, 20_000, 30_000, 50_000])
    }

    func testRoyalties() {
        // £52,800 / week for an album at #1 on Mega Big (20 %)
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 1, singlePos: 0, piracy: false, percent: 20), 52_800)
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 0, singlePos: 1, piracy: false, percent: 20), 26_400)
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 1, singlePos: 0, piracy: false, percent: 3), 7_920)
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 0, singlePos: 1, piracy: false, percent: 3), 3_960)
        // traces: album #1 + single #1 at 20 % -> £79,200; album #3 with piracy at 3 % -> £3,240
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 1, singlePos: 1, piracy: false, percent: 20), 79_200)
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 3, singlePos: 0, piracy: true, percent: 3), 3_240)
        XCTAssertEqual(GameState.royaltyIncome(albumPos: 11, singlePos: 12, piracy: false, percent: 20), 0)

        var s = makeState()
        s.label = 5; s.albumPos = 1; s.cash = 0
        XCTAssertEqual(s.weeklyRoyalties(), 52_800)
        XCTAssertEqual(s.cash, 52_800)
        XCTAssertEqual(s.salesHistory[0], 12)
        XCTAssertEqual(s.week, 1)
    }

    func testGoldDiscThresholds() {
        var s = makeState()
        s.label = 1; s.albumPos = 1   // 9 points per week at #1
        var firstWeek = [Int](repeating: 0, count: 4)
        for w in 1...28 {
            s.weeklyRoyalties()
            for d in 0..<4 where s.discs[d] && firstWeek[d] == 0 { firstWeek[d] = w }
        }
        // 40 / 100 / 170 / 250 points -> weeks 5, 12, 19, 28 at #1
        XCTAssertEqual(firstWeek, [5, 12, 19, 28])
        XCTAssertTrue(s.won)
        var t = makeState()
        t.label = 1; t.albumPos = 10
        for _ in 0..<10 { t.weeklyRoyalties() }
        XCTAssertEqual(t.discPoints, 0)   // #10 pays but gives no disc points
        XCTAssertGreaterThan(t.cash, 50_000)
    }

    // MARK: charts

    func testSingleChartRank() {
        let v = Self.data.videoRankTable, f = Self.data.fameRankTable
        // Per the code at $7A89 (x == T[i] -> 10-i, x < T[i] -> 11-i). The summary
        // table in rules_records §3.2 is off by one for values between table entries.
        XCTAssertEqual([0, 1, 2, 4, 5, 6, 7, 9, 10, 11, 12, 13, 20].map { GameState.chartRank($0, v) },
                       [10, 9, 9, 8, 8, 7, 7, 5, 4, 3, 2, 1, 1])
        XCTAssertEqual([0, 39, 40, 41, 60, 61, 100, 110, 171, 200, 255].map { GameState.chartRank($0, f) },
                       [11, 11, 10, 10, 9, 9, 7, 6, 2, 1, 1])
        var s = makeState()
        s.fame = 120; s.beginSingle(track: 0)
        s.makeVideo(director: 5, location: 3, feature: 3)   // score 0
        s.launchSingle()
        XCTAssertEqual(s.singlePeak, 10)    // max(video rank 10, fame rank 5)
        XCTAssertTrue((17...20).contains(s.singlePos))
        XCTAssertTrue((5...7).contains(Int(s.climbWeeks)))
        // re-release forces video score 0
        s.beginSingle(track: 0)
        s.cash = 10_000_000
        s.makeVideo(director: 0, location: 0, feature: 0)  // 13
        XCTAssertEqual(s.videoScore, 13)
        s.launchSingle()
        XCTAssertEqual(s.videoScore, 0)
    }

    func testPlayerSingleAndAlbumMovement() {
        var s = makeState()
        s.singlePos = 18; s.singlePeak = 3; s.climbWeeks = 6; s.hype = 12
        var positions: [Int] = []
        for _ in 0..<6 { s.movePlayerSingle(); positions.append(s.singlePos) }
        XCTAssertTrue(positions.allSatisfy { $0 >= 3 })
        XCTAssertEqual(s.climbWeeks, 0x80)
        // falling: 0..3 per week, stops once out of the top ten
        s.singlePos = 9
        for _ in 0..<20 { s.movePlayerSingle() }
        XCTAssertGreaterThanOrEqual(s.singlePos, 11)
        let out = s.singlePos
        s.movePlayerSingle()
        XCTAssertEqual(s.singlePos, out)

        // album: #1 single lifts 3 places, top-8 single lifts 1, otherwise drifts down
        s.albumPos = 12; s.singlePos = 1; s.movePlayerAlbum(); XCTAssertEqual(s.albumPos, 9)
        s.singlePos = 7; s.movePlayerAlbum(); XCTAssertEqual(s.albumPos, 8)
        s.albumPos = 5; s.movePlayerAlbum(); XCTAssertEqual(s.albumPos, 6)   // top 5 needs a top-5 single
        s.singlePos = 9; s.movePlayerAlbum(); XCTAssertEqual(s.albumPos, 7)
        s.albumPos = 20; s.movePlayerAlbum(); XCTAssertEqual(s.albumPos, 20)
        s.albumPos = 2; s.singlePos = 1; s.movePlayerAlbum(); XCTAssertEqual(s.albumPos, 1)
    }

    func testSingleQuirkLandingOnZero() {
        // pos - r == 0 goes one place down (faithful) instead of to #1.
        for faithful in [true, false] {
            var s = makeState(faithful: faithful)
            s.hype = 0; s.singlePeak = 1; s.climbWeeks = 5
            // find an RNG index where rnd(2) returns 2
            s.rng.index = Self.data.rngTable.firstIndex(of: 2)!
            s.singlePos = 2
            s.movePlayerSingle()
            XCTAssertEqual(s.singlePos, faithful ? 3 : 1)
        }
    }

    func testRivalChartsAndChartShow() {
        var s = makeState()
        XCTAssertEqual(s.rivalSongTitles.filter { $0.isEmpty }.count, 0)
        XCTAssertEqual(s.rivalAlbumTitles[0].isEmpty, false)
        s.singleReleased = true; s.albumReleased = true
        s.singlePos = 3; s.singlePeak = 3; s.climbWeeks = 0x80; s.albumPos = 4
        let tables = s.runChartShow()
        XCTAssertEqual(tables.count, 2)
        for t in tables {
            XCTAssertEqual(t.rows.count, 10)
            XCTAssertEqual(Set(t.rows.compactMap { if case .rival(let r) = $0 { return r } else { return nil } }).count,
                           t.rows.filter { $0 != .player }.count)
        }
        if let i = tables[0].rows.firstIndex(of: .player) { XCTAssertEqual(i + 1, s.singlePos) }
        if let i = tables[1].rows.firstIndex(of: .player) { XCTAssertEqual(i + 1, s.albumPos) }
        // a few weeks of charts never crash and keep scores in range
        for _ in 0..<60 { _ = s.runChartShow() }
    }

    // MARK: events

    func testCharityAndSponsor() {
        var s = makeState()
        s.hype = 10; s.fame = 100
        XCTAssertTrue(s.charityEligible)
        let r = s.answerCharity(accept: true)
        if r.real { XCTAssertEqual(s.fame, 110) } else { XCTAssertEqual(s.fame, 51) }
        XCTAssertEqual(s.hype, 11)
        s.sponsor = 2; s.sponsorPatience = 1
        s.badPress()
        XCTAssertTrue(s.sponsorPullOutDue)
        s.cash = 150_000
        s.sponsorPullOut()
        XCTAssertEqual(s.cash, 50_000); XCTAssertEqual(s.sponsor, 0)
    }

    func testScandalCounterQuirk() {
        var s = makeState()
        s.sponsor = 1; s.fame = 200
        var fired = 0
        for _ in 0..<300 { if s.sponsorScandalTick() != nil { fired += 1 } }
        XCTAssertEqual(fired, 2)    // turn 20, then 256 turns later (counter wraps)
        var f = makeState(faithful: false)
        f.sponsor = 1
        var n = 0
        for _ in 0..<60 { if f.sponsorScandalTick() != nil { n += 1 } }
        XCTAssertEqual(n, 3)
    }

    func testBootlegBuyOutQuirk() {
        for faithful in [true, false] {
            var s = makeState(faithful: faithful)
            s.cash = 10_000_000
            s.startBootleg()
            let r = s.resolveBootleg(3)
            XCTAssertEqual(r.message, 172)
            XCTAssertTrue([100_000, 200_000, 300_000, 400_000].contains(r.cost))
            XCTAssertEqual(s.piracy, faithful)
        }
    }

    func testEventCounterSchedule() {
        var s = makeState()
        var charity: [Int] = [], bootleg: [Int] = []
        for turn in 1...40 {
            switch s.tickEventCounter() {
            case .charity: charity.append(turn)
            case .bootleg: bootleg.append(turn)
            case .none: break
            }
        }
        XCTAssertEqual(charity, [10, 25, 40])
        XCTAssertEqual(bootleg, [7, 22, 37])
    }

    func testRansomDigitQuirk() {
        var s = makeState()
        s.cash = 10_500_000
        XCTAssertFalse(s.producerRansomDue())   // only the 10^6 digit is tested
        s.cash = 1_200_000
        XCTAssertTrue(s.producerRansomDue())
        XCTAssertFalse(s.producerRansomDue())   // once per game
        var f = makeState(faithful: false)
        f.cash = 10_500_000
        XCTAssertTrue(f.producerRansomDue())
    }

    func testPublicityDeathRate() {
        // ~11 % of stunts kill a band member (rules_events §6).
        var deaths = 0, n = 4000
        var s = makeState(seed: 7)
        for _ in 0..<n {
            s.beginHiring(count: 4)
            s.formBand()
            if case .bandStory(_, _, _, true) = s.publicityStunt() { deaths += 1 }
        }
        let rate = Double(deaths) / Double(n)
        XCTAssertGreaterThan(rate, 0.07)
        XCTAssertLessThan(rate, 0.15)
    }

    func testRecordingFlow() {
        var s = makeState()
        s.beginHiring(count: 1); s.acceptStar(record: 0, slot: 0); s.formBand()
        s.cash = 100_000; s.skill = 100; s.hype = 5
        s.startRecording(studio: 5)
        XCTAssertEqual(s.cash, 50_000)
        XCTAssertEqual(s.daysPerTrack, 1)
        var names = Set<String>()
        while s.tracksCut < 10 {
            if s.dialAccident() { continue }
            let n = s.suggestTrackName()
            XCTAssertFalse(n.isEmpty)
            names.insert(n)
            s.nameTrack(n)
        }
        XCTAssertEqual(names.count, 10)
        XCTAssertFalse(s.suggestedNames[2] == false || s.suggestedNames[12] == false)
        s.finishRecording()
        XCTAssertTrue(s.albumInCan)
        XCTAssertEqual(s.skill, 120); XCTAssertEqual(s.hype, 3)
        XCTAssertEqual(s.menuKind, .basic)   // no label in this test
        s.label = 1
        XCTAssertEqual(s.menuKind, .withRelease)
        s.releaseAlbum(named: "TEST")
        XCTAssertTrue([11, 12].contains(s.albumPos))
        XCTAssertTrue(s.chartShowDue)
    }

    func testDisasterNeedsDiscAndMillion() {
        var s = makeState()
        s.cash = 5_000_000
        XCTAssertNil(s.disasterCheck())
        s.discs[0] = true
        s.equipment = 2
        // with disc 1 only, the equipment loss is the only possible disaster
        XCTAssertEqual(s.disasterCheck(), .equipmentLost(quality: 2))
        XCTAssertNil(s.disasterCheck())
    }

    func testSandboxNoBankruptcyAndYearRollsOver() {
        var s = makeState()
        s.config.sandbox = true
        s.stars = 1; s.gone[0] = false   // a band, so days actually pass
        s.cash = 100
        s.charge(1_000)
        XCTAssertFalse(s.bankrupt)
        XCTAssertEqual(s.cash, 0)
        for _ in 0..<370 { _ = s.advanceDay() }
        XCTAssertFalse(s.yearOver)
        XCTAssertEqual(s.month, 0)          // back in January
        XCTAssertGreaterThan(s.dayOfMonth, 1)
        var n = makeState()
        n.cash = 100
        n.charge(1_000)
        XCTAssertTrue(n.bankrupt)           // normal rules unchanged
    }

    func testSaveRoundTrip() throws {
        var s = makeState()
        s.cash = 123_456; s.fame = 77; s.bandName = "THE HAMSTERS"; s.config.sandbox = true
        _ = s.advanceDay(); _ = s.rng.rnd(9)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rs-save-test-\(getpid())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SaveStore(dir: dir)
        try store.save(SaveFile(savedAt: Date(), state: s, strings: [0: "THE HAMSTERS"]), slot: 2)
        let f = try XCTUnwrap(store.load(slot: 2))
        XCTAssertNil(store.load(slot: 1))
        XCTAssertEqual(f.state.cash, 123_456)
        XCTAssertEqual(f.state.fame, 77)
        XCTAssertEqual(f.state.dayOfMonth, s.dayOfMonth)
        XCTAssertTrue(f.state.config.sandbox)
        XCTAssertEqual(f.strings[0], "THE HAMSTERS")
        var a = s, b = f.state            // RNG continues identically after loading
        XCTAssertEqual((0..<20).map { _ in a.rng.rnd(15) }, (0..<20).map { _ in b.rng.rnd(15) })
    }

    func testDifficulty() {
        for (d, cash) in [(Difficulty.easy, 100_000), (.normal, 50_000), (.hard, 25_000)] {
            var s = makeState()
            s.config.difficulty = d
            s.newGame()
            XCTAssertEqual(s.cash, cash)
        }
        // royalties: Mega Big, album #1 = £52,800/week on normal
        var s = makeState()
        s.label = 5; s.albumPos = 1; s.cash = 0
        s.config.difficulty = .easy
        XCTAssertEqual(s.weeklyRoyalties(), 79_200)
        // easy platinum at 150 disc points
        s.discPoints = 145
        _ = s.weeklyRoyalties()               // +9
        XCTAssertTrue(s.discs[3])
        var n = makeState()
        n.label = 5; n.albumPos = 1
        XCTAssertEqual(n.weeklyRoyalties(), 52_800)
    }

    func testCustomStarRecord() {
        let r = CustomStars.record(CustomStar(name: "Alex the Axe", instrument: "guitar", fame: 25, skill: 12,
                                              mood: 40, wage: 3000, voice: 3, gear: 5, portrait: nil))
        XCTAssertEqual(r.name, "ALEX THE AXE")
        XCTAssertEqual(r.stats, [25, 3, 12, 40, 0x25, 0, 3, 0, 0, 0x55])
        XCTAssertEqual(GameState.wage(of: r), 3000)
        XCTAssertEqual(GameState.gearUnitPrices(kind: r.stats[4]), [300, 200, 100])   // guitar
        XCTAssertEqual(r.portraitBytes.count, 240)
        XCTAssertTrue(r.portraitBytes.contains { $0 != 0 })                            // initials drawn
    }

    func testCareerMode() throws {
        var s = makeState()
        s.config.career = true
        s.beginHiring(count: 2)
        s.acceptStar(record: 0, slot: 0); s.acceptStar(record: 1, slot: 1)
        s.formBand()
        var sawNewYear = false
        for _ in 0..<370 where !sawNewYear {
            if s.advanceDay() == .newYear { sawNewYear = true }
        }
        XCTAssertTrue(sawNewYear)
        XCTAssertFalse(s.yearOver)
        XCTAssertEqual(s.month, 0); XCTAssertEqual(s.dayOfMonth, 1)
        s.discs = [true, true, true, true]
        XCTAssertFalse(s.gameDecided)                      // platinum doesn't end a career
        let wage0 = s.wages[0]
        let retired = s.startNewCareerYear(roll: { _ in 0 })   // year 2: 10% chance, roll 0 -> both retire
        XCTAssertEqual(retired.count, 2)
        XCTAssertEqual(s.config.platinums, 1)
        XCTAssertEqual(s.config.careerYear, 2)
        XCTAssertEqual(s.discs, [false, false, false, false])
        XCTAssertEqual(s.wages[0], wage0 * 11 / 10)
        XCTAssertTrue(s.signNewTalent(record: 5))
        XCTAssertEqual(s.stars, 1)
        // configs saved before career mode still load
        let old = try JSONDecoder().decode(GameConfig.self, from: Data(#"{"faithfulBugs":false,"sandbox":true}"#.utf8))
        XCTAssertFalse(old.career); XCTAssertTrue(old.sandbox); XCTAssertEqual(old.difficulty, .normal)
    }
}
