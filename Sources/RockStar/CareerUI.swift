import Foundation

/// Career mode screens (not in the original).
extension Game {
    /// Mid-year platinum: celebrate once, but the career goes on.
    func careerPlatinumCheck() async {
        guard state.config.career, state.won, celebratedYear != state.config.careerYear else { return }
        celebratedYear = state.config.careerYear
        sound?.jingle(5)
        await cliveSays("PLATINUM, BOSS! \(state.bandName) HAVE GONE PLATINUM IN YEAR \(state.config.careerYear)! "
            + "BUT THIS IS A CAREER, NOT A ONE-HIT WONDER. ON WE GO!")
    }

    /// 1 January in career mode: review, retirements, new talent, carry on or retire.
    func yearEnd() async {
        let year = state.config.careerYear
        let discs = state.discs.filter { $0 }.count
        setScene(1)
        sound?.jingle(discs == 4 ? 5 : 1)
        await cliveSays("HAPPY NEW YEAR, BOSS! THAT WAS YEAR \(year): \(discs) GOLD DISC\(discs == 1 ? "" : "S")"
            + "\(discs == 4 ? " AND PLATINUM" : ""), FAME \(state.fame) AND £\(state.cash) IN THE BANK. "
            + "TIME FOR A NEW ALBUM!")
        let names = state.starNames
        let retired = state.startNewCareerYear()
        for slot in retired {
            await cliveSays("SAD NEWS. \(names[slot]) IS RETIRING TO GROW TOMATOES IN THE COUNTRYSIDE. "
                + "THANKS FOR THE MEMORIES!")
        }
        if !state.gone.allSatisfy({ !$0 }) && state.stars < max(state.hiredCount, 1) {
            await newTalent(max(state.hiredCount, 1) - state.stars)
        }
        if state.stars > 0 {
            await cliveSays("WAGES ARE UP 10% FOR THE NEW YEAR. THE BAND SAY IT'S INFLATION. I SAY IT'S GREED.")
            let c = await cliveAsks("SO BOSS... ANOTHER YEAR IN THE ROCK BUSINESS, OR RETIRE WHILE WE'RE AHEAD?",
                                    ["CARRY ON", "RETIRE"])
            if c == 1 { state.config.careerRetired = true }
        }
        needsRedraw = true
        drawPanel()
    }

    /// Offer up to `slots` fresh stars from those not already in the band.
    private func newTalent(_ slots: Int) async {
        var left = slots
        let inBand = Set((0..<4).filter { !state.gone[$0] }.map { state.starRecord[$0] })
        var candidates = state.records.indices.filter { !inBand.contains($0) }.shuffled()
        setScene(3)
        while left > 0, let r = candidates.popLast() {
            tvPortrait = r
            needsRedraw = true
            let rec = state.records[r]
            let c = await cliveAsks("NEW TALENT, BOSS! \(rec.name) WANTS TO JOIN \(state.bandName) "
                + "FOR £\(GameState.wage(of: rec)) A WEEK. SIGN THEM UP?", ["YES", "NO"])
            if c == 0, state.signNewTalent(record: r) { left -= 1; continue }
            if await cliveAsks("SHALL WE KEEP LOOKING FOR NEW TALENT?", ["YES", "NO"]) == 1 { break }
        }
        tvPortrait = nil
        setScene(1)
        needsRedraw = true
        drawPanel()
    }

    /// The end of a career: bankrupt, no band left, or retired.
    func careerEnding() async {
        let years = state.config.careerYear, plats = state.config.platinums + (state.discs[3] ? 1 : 0)
        let why = state.bankrupt ? "WE'RE BANKRUPT" : state.stars == 0 ? "THE BAND HAS GONE" : "WE'VE RETIRED"
        sound?.jingle(plats > 0 ? 5 : 7)
        await cliveSays("WELL BOSS, \(why). WHAT A CAREER: \(years) YEAR\(years == 1 ? "" : "S"), "
            + "\(plats) PLATINUM ALBUM\(plats == 1 ? "" : "S") AND £\(state.cash) TO SHOW FOR IT. "
            + (plats >= 3 ? "LEGENDS!" : plats > 0 ? "NOT BAD AT ALL!" : "THERE'S ALWAYS THE THEATRE..."))
    }
}
