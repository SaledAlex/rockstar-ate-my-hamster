import Foundation

/// Career mode rules (not in the original).
extension GameState {
    /// Chance (percent) that a star retires at the end of career year `year`.
    static func retireChance(year: Int) -> Int { min(10 * (year - 1), 50) }

    /// 1 January in career mode: count a platinum year, start a fresh year of
    /// records (same label), wages rise 10% and some stars may retire.
    /// Returns the slots of the stars who retired.
    mutating func startNewCareerYear(roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> [Int] {
        if discs[3] { config.platinums += 1 }
        config.careerYear += 1
        discs = [false, false, false, false]; discPoints = 0
        albumInCan = false; albumReleased = false; singleReleased = false
        tracksCut = 0; dialAccidentDone = false; singleTrack = 0; videoScore = 0
        releasedTracks = [Bool](repeating: false, count: 10)
        trackNames = [String](repeating: "", count: 10); albumName = ""
        singlePos = 0; albumPos = 0; singlePeak = 0; climbWeeks = 0
        piracy = false; bootlegDone = false
        var retired: [Int] = []
        for i in 0..<4 where !gone[i] {
            wages[i] = wages[i] * 11 / 10
            if roll(100) < GameState.retireChance(year: config.careerYear) {
                gone[i] = true; stars -= 1; retired.append(i)
            }
        }
        return retired
    }

    /// New talent fills an empty slot mid-career (the band keeps its fame/skill).
    mutating func signNewTalent(record r: Int) -> Bool {
        guard let slot = (0..<4).first(where: { gone[$0] }) else { return false }
        acceptStar(record: r, slot: slot)
        gone[slot] = false
        stars += 1
        return true
    }
}
