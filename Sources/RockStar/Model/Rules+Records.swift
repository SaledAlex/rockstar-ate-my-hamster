import Foundation

extension GameState {
    // MARK: recording `$7198` (rules_records §2)

    static let studioCost = [2_000, 5_000, 10_000, 16_000, 20_000, 50_000]

    /// Pay for studio `s` (0...5). The caller then advances one day and, unless
    /// bankrupt / year over, records 10 tracks of `daysPerTrack` days each.
    mutating func startRecording(studio s: Int) {
        suggestedNames = [Bool](repeating: false, count: 16)
        suggestedNames[2] = true    // $6131: string 3 never suggested
        suggestedNames[12] = true   // $613B: string 13 never suggested
        skillAtRecording = skill
        daysPerTrack = data.studioDays[s]
        tracksCut = 0
        charge(GameState.studioCost[s])
    }

    /// `$7112`: "what's this little dial for?" (once per game). True = last track wiped.
    mutating func dialAccident() -> Bool {
        // INFERRED: evaluation order of the three conditions.
        guard !dialAccidentDone, tracksCut != 0, rng.rnd(6) == 5 else { return false }
        dialAccidentDone = true
        return true
    }

    /// `$7131`: suggest a name for the track just cut (msg 125 / 124).
    mutating func suggestTrackName() -> String {
        rng.reseed()
        var c: Int
        repeat { c = rng.rnd(15) } while suggestedNames[c]
        suggestedNames[c] = true
        return rng.expand(data.nameStrings[c + 1])
    }

    mutating func nameTrack(_ name: String) {
        trackNames[tracksCut] = name
        tracksCut += 1
    }

    /// After the 10th track: hype -2, SKILL +20, album in the can.
    mutating func finishRecording() {
        hypeDown(); hypeDown()
        skillUp(); skillUp()
        albumInCan = true
    }

    /// `$745E`: producer ransom check (once per game). True = ask msg 112.
    mutating func producerRansomDue() -> Bool {
        let rich = config.faithfulBugs
            ? (cash / 1_000_000) % 10 != 0   // only the 10^6 digit is tested
            : cash >= 1_000_000
        guard rich, oneShot & 8 == 0 else { return false }
        oneShot |= 8
        return true
    }

    mutating func answerRansom(pay: Bool) {
        if pay { charge(1_000_000) } else { albumInCan = false }
    }

    // MARK: releases `$732C` (§3)

    mutating func releaseAlbum(named name: String) {
        albumName = name
        albumReleased = true
        albumPos = 11 + rng.rnd(1)
    }

    static let directorCost = [3_000_000, 1_000_000, 50_000, 10_000, 5_000, 5]
    static let directorScore = [5, 4, 3, 2, 1, 0]
    static let locationCost = [50_000, 20_000, 10_000, 50]
    static let locationScore = [5, 3, 2, 0]
    static let featureScore = [3, 1, 2, 0, 2, 1]

    /// `$7369` start: pick the track; video score reset.
    mutating func beginSingle(track t: Int) {
        singleTrack = t
        videoScore = 0
    }

    /// No video: hype -2.
    mutating func skipVideo() { hypeDown(); hypeDown() }

    /// `$73A9`: returns the total cost (msg 79 NUM0), charged.
    @discardableResult
    mutating func makeVideo(director d: Int, location l: Int, feature f: Int) -> Int {
        videoScore += GameState.directorScore[d] + GameState.locationScore[l] + GameState.featureScore[f]
        let cost = GameState.directorCost[d] + GameState.locationCost[l]
        charge(cost)
        return cost
    }

    /// rank(x, T) from `$7A63`.
    static func chartRank(_ x: Int, _ table: [Int]) -> Int {
        for i in 0..<10 {
            if x == table[i] { return 10 - i }
            if x < table[i] { return 11 - i }
        }
        return 1
    }

    /// `$743F` / `$7A63`: put the single on the chart.
    mutating func launchSingle() {
        if releasedTracks[singleTrack] { videoScore = 0 } else { releasedTracks[singleTrack] = true }
        let vid = GameState.chartRank(videoScore, data.videoRankTable)
        let fam = GameState.chartRank(fame, data.fameRankTable)
        singlePeak = max(vid, fam)
        singlePos = 17 + rng.rnd(3)
        climbWeeks = UInt8(5 + rng.rnd(2))
        singleReleased = true
    }

    // MARK: rival charts (§4)

    /// `$764B` (once per boot): rival titles and an initial shuffle of the singles.
    mutating func bootCharts() {
        rivalSingles = data.rivals.map { RivalEntry(b: $0.single) }
        rivalAlbums = data.rivals.map { RivalEntry(b: $0.album) }
        for s in 0..<30 {
            let k = rng.rnd(2)
            rivalSongTitles[s] = rng.expand(data.nameStrings[data.rivals[s].songChoices[k]])
        }
        rng.reseed()
        for s in 0..<30 {
            rivalAlbumTitles[s] = rng.expand(data.nameStrings[data.rivals[s].albumTitle])
            rng.reseed()
        }
        let n = (rng.index & 7) | 1
        for _ in 0..<n { tickRivals(albums: false) }
    }

    /// `$7741`: one week of rival movement.
    mutating func tickRivals(albums: Bool) {
        var table = albums ? rivalAlbums : rivalSingles
        for s in 0..<30 {
            var e = table[s].b
            if e[0] & 0x80 != 0 {
                let r = 1 + rng.rnd(3)
                if Int(e[1]) - r <= 0 {
                    e[1] = e[2]
                    e[0] = e[4]
                    table[s].b = e
                    continue
                }
                e[1] -= UInt8(r)
            } else {
                e[1] &+= UInt8(rng.rnd(4))
            }
            e[0] &-= 1
            if e[0] == 0 {
                // $779E respawn
                e[0] = e[3]
                respawnIndex = (respawnIndex + 1) % 6
                e[1] = data.respawnScores[respawnIndex]
                if !albums {
                    // $77C8: new tune and a new title for the band's next single
                    let k = rng.rnd(2)
                    rivalSongTitles[s] = rng.expand(data.nameStrings[data.rivals[s].songChoices[k]])
                }
            } else if e[0] & 0x3F == 0 {
                e[0] = e[4]
            }
            table[s].b = e
        }
        if albums { rivalAlbums = table } else { rivalSingles = table }
    }

    /// `$78D2`: rivals sorted by score (stable; a tie goes below the earlier entry).
    func rivalTopTen(albums: Bool) -> [ChartEntrant] {
        let table = albums ? rivalAlbums : rivalSingles
        var rows: [(score: Int, slot: Int)] = []
        for s in 0..<30 {
            let score = Int(table[s].b[1])
            if score == 0xFF { continue }
            if let at = rows.firstIndex(where: { score < $0.score }) {
                rows.insert((score, s), at: at)
            } else {
                rows.append((score, s))
            }
            if rows.count > 10 { rows.removeLast() }
        }
        return rows.map { .rival($0.slot) }
    }

    /// `$7B22` (singles): weekly movement of the player's single.
    mutating func movePlayerSingle() {
        if climbWeeks & 0x80 == 0 {
            let r = rng.rnd(hype < 5 ? 2 : hype < 10 ? 4 : 6)
            let d = singlePos - r
            if d > 0 {
                singlePos = max(singlePeak, d)
            } else if d == 0 {
                // Faithful quirk: B was incremented, so landing on 0 goes one place DOWN.
                singlePos = config.faithfulBugs ? max(singlePeak, singlePos + 1) : max(singlePeak, 1)
            } else {
                singlePos = singlePeak
            }
            climbWeeks &-= 1
            if climbWeeks == 0 { climbWeeks = 0x80 }
        } else {
            if singlePos >= 11 { return }
            singlePos += rng.rnd(3)
        }
    }

    /// `$7AC2` (albums): weekly movement of the album, driven by the single.
    mutating func movePlayerAlbum() {
        let s = singlePos
        var a = albumPos
        var climb = s >= 1 && s <= 8
        if climb && a >= 1 && a <= 5 && !(s >= 1 && s <= 5) { climb = false }
        if climb {
            let steps = ((9 - s) | 4) >> 2
            for _ in 0..<steps {
                if a == 1 { break }
                a -= 1
            }
        } else if a != 20 {
            a += 1
        }
        albumPos = a
    }

    private func markers(_ rows: [ChartEntrant], last: [Int]) -> [ChartMarker] {
        rows.enumerated().map { i, e in
            let code: Int
            switch e { case .rival(let s): code = s; case .player: code = 0xFE }
            if i < last.count && last[i] == code { return .same }
            return last.contains(code) ? .moved : .new
        }
    }

    private static func codes(_ rows: [ChartEntrant]) -> [Int] {
        var c = rows.map { e -> Int in
            switch e { case .rival(let s): return s; case .player: return 0xFE }
        }
        while c.count < 10 { c.append(0xFF) }
        return c
    }

    /// `$7861` with `$BEC3` = 0.
    mutating func runSinglesChart() -> ChartTable {
        tickRivals(albums: false)
        var rows = rivalTopTen(albums: false)
        movePlayerSingle()
        if singlePos >= 1 && singlePos < 11 {
            rows.insert(.player, at: min(singlePos - 1, rows.count))
            if rows.count > 10 { rows.removeLast() }
        }
        let table = ChartTable(albums: false, rows: rows, markers: markers(rows, last: lastWeekSingles))
        // $7A26: a climbing rival at #1 starts to fall.
        if case .rival(let s)? = rows.first, rivalSingles[s].b[0] & 0x80 != 0 {
            rivalSingles[s].b[0] = UInt8(4 + rng.rnd(4))
        }
        lastWeekSingles = GameState.codes(rows)
        return table
    }

    /// `$785C` (`$BEC3` = 1).
    mutating func runAlbumsChart() -> ChartTable {
        tickRivals(albums: true)
        var rows = rivalTopTen(albums: true)
        movePlayerAlbum()
        if albumPos >= 1 && albumPos < 11 {
            rows.insert(.player, at: min(albumPos - 1, rows.count))
            if rows.count > 10 { rows.removeLast() }
        }
        let table = ChartTable(albums: true, rows: rows, markers: markers(rows, last: lastWeekAlbums))
        lastWeekAlbums = GameState.codes(rows)
        return table
    }

    /// `$781A` chart computation (display is up to the caller; the original then
    /// advances one more day before `$7004`).
    mutating func runChartShow() -> [ChartTable] {
        var out: [ChartTable] = []
        if singleReleased { out.append(runSinglesChart()) }
        if albumReleased { out.append(runAlbumsChart()) }
        return out
    }

    // MARK: royalties and discs `$7004` (§5)

    /// Weekly income for given positions (used by the model and tests).
    static func royaltyIncome(albumPos: Int, singlePos: Int, piracy: Bool, percent: Int) -> Int {
        let ua = (1...10).contains(albumPos) ? 12 - albumPos : 0
        let us = (1...10).contains(singlePos) ? 12 - singlePos : 0
        let units = (piracy ? ua : 2 * ua) + us
        return 120 * units * percent
    }

    /// Sunday: sales bar, royalties, gold discs. Returns the income credited.
    @discardableResult
    mutating func weeklyRoyalties() -> Int {
        let ua = (1...10).contains(albumPos) ? 12 - albumPos : 0
        let us = (1...10).contains(singlePos) ? 12 - singlePos : 0
        if week < salesHistory.count { salesHistory[week] = ua + us + 1 }
        week += 1
        let income = GameState.royaltyIncome(albumPos: albumPos, singlePos: singlePos,
                                             piracy: piracy, percent: royaltyPercent(tier: label))
            * config.difficulty.royaltyPercent / 100
        if income > 0 { credit(income) }
        if (1...9).contains(albumPos) {
            discPoints = (discPoints + 10 - albumPos) & 0xFF
            let t = config.difficulty.discThresholds
            if discPoints >= t[3] { discs[3] = true }
            else if discPoints >= t[2] { discs[2] = true }
            else if discPoints >= t[1] { discs[1] = true }
            else if discPoints >= t[0] { discs[0] = true }
        }
        return income
    }
}
