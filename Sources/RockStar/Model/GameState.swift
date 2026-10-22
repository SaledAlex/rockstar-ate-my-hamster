import Foundation

/// Rule options.
struct GameConfig: Codable {
    /// Reproduce behaviour the notes flag as probable bugs in the original
    /// (see README.md for the list). Default: faithful.
    var faithfulBugs = true
    /// Sandbox (cheat menu): no bankruptcy and no end of year; the calendar
    /// rolls over into a new year instead.
    var sandbox = false
    /// Not in the original: scales starting cash, wages, royalties and the
    /// gold-disc targets. `.normal` is the original game.
    var difficulty: Difficulty = .normal
    /// Career mode (not in the original): the year rolls over instead of ending,
    /// platinum doesn't end the game, stars age and retire. Career progress is kept
    /// here so saves from before career mode still load.
    var career = false
    var careerYear = 1
    var platinums = 0
    var careerRetired = false

    init(faithfulBugs: Bool = true, sandbox: Bool = false, difficulty: Difficulty = .normal, career: Bool = false) {
        self.faithfulBugs = faithfulBugs; self.sandbox = sandbox; self.difficulty = difficulty; self.career = career
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faithfulBugs = try c.decodeIfPresent(Bool.self, forKey: .faithfulBugs) ?? true
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false
        difficulty = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .normal
        career = try c.decodeIfPresent(Bool.self, forKey: .career) ?? false
        careerYear = try c.decodeIfPresent(Int.self, forKey: .careerYear) ?? 1
        platinums = try c.decodeIfPresent(Int.self, forKey: .platinums) ?? 0
        careerRetired = try c.decodeIfPresent(Bool.self, forKey: .careerRetired) ?? false
    }
}

enum Difficulty: String, Codable, CaseIterable {
    case easy, normal, hard

    var startingCash: Int { [.easy: 100_000, .normal: 50_000, .hard: 25_000][self]! }
    /// Weekly wage bill, percent of the original.
    var wagePercent: Int { [.easy: 50, .normal: 100, .hard: 150][self]! }
    /// Royalty income, percent of the original.
    var royaltyPercent: Int { [.easy: 150, .normal: 100, .hard: 75][self]! }
    /// Album disc points for gold discs 1-3 and platinum (original `$7004`: 40/100/170/250).
    var discThresholds: [Int] {
        [.easy: [25, 60, 100, 150], .normal: [40, 100, 170, 250], .hard: [40, 100, 170, 250]][self]!
    }
    var label: String { [.easy: "EASY", .normal: "NORMAL (ORIGINAL)", .hard: "HARD"][self]! }
}

/// One rival chart entry (`$ABC8` / `$AC5E`, 5 bytes).
struct RivalEntry: Equatable, Codable {
    var b: [UInt8]   // b0 counter|bit7 climbing, b1 score, b2 peak score, b3 respawn counter, b4 after-peak counter
}

/// A chart row as built by `$7861`: rival slot 0...29 or the player (`$FE`).
enum ChartEntrant: Equatable, Codable {
    case rival(Int)
    case player
}

enum ChartMarker { case same, moved, new }   // '*' / '+' / '<' from `$A64F`

struct ChartTable {
    let albums: Bool
    /// rows[0] = number 1.
    let rows: [ChartEntrant]
    let markers: [ChartMarker]
}

/// The whole game state as a pure value. Field comments give the original RAM
/// address. All rule functions live in extensions (Rules*.swift) and never
/// touch the UI; the UI (Game.swift) sequences them like the original code.
struct GameState: Codable {
    let data: GameData
    let records: [RockStarRecord]
    var config: GameConfig
    var rng: SpectrumRNG

    // MARK: money (rules_core §1)
    static let cashCap = 99_999_999
    /// `$618D` CASH in pounds.
    var cash = 50_000
    /// `$BEE6`
    var bankrupt = false

    // MARK: calendar (§5)
    /// `$BEDD` 0 = MON ... 6 = SUN
    var dayOfWeek = 0
    /// `$C685/$C686`
    var dayOfMonth = 1
    /// `$BEDC` 0 = JAN
    var month = 0
    /// `$BEDB` chart week counter
    var week = 0
    /// `$BEDE`
    var yearOver = false
    /// `$614F` weekly sales bars
    var salesHistory = [Int](repeating: 0, count: 52)
    static let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    // MARK: band (§2.2, §4.3)
    /// `$BF28` STR0
    var bandName = ""
    /// `$BF25` number hired at start
    var hiredCount = 0
    /// `$BF24` stars still in the band
    var stars = 0
    /// `$619D` bit7: slot empty / fired / quit / dead
    var gone = [true, true, true, true]
    /// `$C558+20s` STR72+s
    var starNames = ["", "", "", ""]
    /// tape record index per slot (for portraits)
    var starRecord = [-1, -1, -1, -1]
    /// `$613F` weekly wage per slot in pounds
    var wages = [0, 0, 0, 0]
    /// `$BEF7` image, `$BEFB` image backup
    var image: [UInt8] = [0, 0, 0, 0]
    var imageBak: [UInt8] = [0, 0, 0, 0]
    /// `$BEFF` voice / part
    var voice: [UInt8] = [0, 0, 0, 0]
    /// `$BF03` ability, `$BF07` backup
    var ability: [UInt8] = [0, 0, 0, 0]
    var abilityBak: [UInt8] = [0, 0, 0, 0]
    /// `$BF0B` mood / happiness, `$BF0F` backup
    var mood: [UInt8] = [0, 0, 0, 0]
    var moodBak: [UInt8] = [0, 0, 0, 0]
    /// `$BF13` instrument class bits + gear units
    var kind: [UInt8] = [0, 0, 0, 0]
    /// `$BEF5` SKILL
    var skill = 0
    /// `$BEF6` FAME
    var fame = 0
    /// `$BF23` hype / street cred 0...15
    var hype = 0
    /// `$BEF2` first music voice; picks the suggested band name.
    var bandVoice = 0
    /// `$BEB9` 0 new, 1 second hand, 2 dodgy
    var equipment = 0
    /// `$BEBA` slot of the unhappiest star / current star
    var currentStar = 0

    // MARK: contract (§8.1)
    /// `$BEE8` 0 none, 1...5
    var label = 0
    /// `$BEE9...$BEF0` offer k already made (index 1...5)
    var offerMade = [Bool](repeating: false, count: 6)

    // MARK: recording / releases (rules_records)
    /// `$BED4`
    var albumInCan = false
    /// `$BEC4` bit7 / bit6
    var albumReleased = false
    var singleReleased = false
    /// STR1...STR10, STR11
    var trackNames = [String](repeating: "", count: 10)
    var albumName = ""
    /// `$BED1`, `$BED2`, `$BEF1`
    var tracksCut = 0
    var daysPerTrack = 0
    var skillAtRecording = 0
    /// `$BEB8` bit0
    var dialAccidentDone = false
    /// `$612F` name-string-already-suggested flags (16)
    var suggestedNames = [Bool](repeating: false, count: 16)
    /// `$6183` track released as single
    var releasedTracks = [Bool](repeating: false, count: 10)
    /// `$BECD`, `$BEE7`
    var singleTrack = 0
    var videoScore = 0

    // MARK: charts
    /// `$BEED` / `$BEEE` (0 = never released, 1...10 top ten, >10 outside)
    var singlePos = 0
    var albumPos = 0
    /// `$BEC5` best position the single can reach
    var singlePeak = 0
    /// `$BEEF` climb weeks, bit7 = falling
    var climbWeeks: UInt8 = 0
    var rivalSingles: [RivalEntry] = []
    var rivalAlbums: [RivalEntry] = []
    /// STR12+s, STR42+s
    var rivalSongTitles = [String](repeating: "", count: 30)
    var rivalAlbumTitles = [String](repeating: "", count: 30)
    /// `$C7FB`
    var respawnIndex = 3
    /// `$5FB8` / `$5FD6` last week's rows (rival index, $FE player, junk at start)
    var lastWeekSingles = [Int](repeating: 0xFF, count: 10)
    var lastWeekAlbums = [Int](repeating: 0xFF, count: 10)
    /// `$BED5` cumulative album disc points (8-bit)
    var discPoints = 0
    /// `$BED6...$BED9`; discs[3] = platinum = WIN
    var discs = [false, false, false, false]
    /// `$BED0` piracy active
    var piracy = false

    // MARK: events (rules_events)
    /// `$6B20` turn counter; NOT reset by a new game.
    var eventCounter = 10
    /// `$BEBB` 0 none, 1...5
    var sponsor = 0
    /// `$BEC7...$BECB`
    var sponsorOffered = [false, false, false, false, false]
    /// `$BECC`
    var sponsorPatience = 0
    /// `$BECE`
    var scandalCounter: UInt8 = 20
    /// `$BECF`
    var bootlegDone = false
    /// `$BEBC` b0 sued, b1 taxman, b2 equipment lost, b3 producer ransom
    var oneShot: UInt8 = 0
    /// `$BEBF`
    var lastHeadline = 0
    /// `$BEB3` "first night of the tour"
    var firstNight = false

    var won: Bool { discs[3] }
    /// Time stops (`$6F3B`) and the main loop ends once any of these is set.
    var gameDecided: Bool {
        bankrupt || stars == 0 || (won && !config.career) || yearOver || config.careerRetired
    }

    // MARK: setup

    /// Boot (`$61A8`: rival chart init `$764B`) followed by a new game (`$6274`).
    init(data: GameData, records: [RockStarRecord], config: GameConfig = GameConfig(),
         seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.data = data
        self.records = records
        self.config = config
        rng = SpectrumRNG(table: data.rngTable, seed: seed)
        respawnIndex = data.respawnStart
        // Stale star bytes before the first hire come from the loaded image;
        // only $BF05/$BF06 (9, 7) are ever read stale (2-star band quirk).
        ability = [0, 0, 9, 7]
        abilityBak = [0, 0, 9, 7]
        bootCharts()
        newGame()
    }

    /// `$6274` / `$6277` new-game init. Keeps the event counter, wage table, star
    /// stats, rival charts and hire count, like the original.
    mutating func newGame() {
        salesHistory = [Int](repeating: 0, count: 52)
        cash = config.difficulty.startingCash
        bankrupt = false
        gone = [true, true, true, true]
        // cleared $BEAB...$BEF6
        dayOfWeek = 0; dayOfMonth = 1; month = 0; week = 0; yearOver = false
        skill = 0; fame = 0; bandVoice = 0; equipment = 0; currentStar = 0
        label = 0; offerMade = [Bool](repeating: false, count: 6)
        albumInCan = false; albumReleased = false; singleReleased = false
        tracksCut = 0; daysPerTrack = 0; skillAtRecording = 0; dialAccidentDone = false
        singleTrack = 0; videoScore = 0
        singlePos = 0; albumPos = 0; singlePeak = 0; climbWeeks = 0
        discPoints = 0; discs = [false, false, false, false]; piracy = false
        sponsor = 0; sponsorOffered = [false, false, false, false, false]; sponsorPatience = 0
        bootlegDone = false; oneShot = 0; lastHeadline = 0; firstNight = false
        // INFERRED: track flags at $6183 and STR slots are outside the cleared
        // range; a fresh game starting from unreleased tracks is the sensible reading.
        releasedTracks = [Bool](repeating: false, count: 10)
        trackNames = [String](repeating: "", count: 10)
        albumName = ""
        scandalCounter = 20
        // $7699: junk "last week" lists from the RNG table
        lastWeekAlbums = data.rngTable[0x15..<0x1F].map(Int.init)
        lastWeekSingles = data.rngTable[0x1F..<0x29].map(Int.init)
        rng.reseed()
        _ = rng.rnd(20)   // $62BC tune numbers (music only, but it advances the RNG)
    }

    // MARK: money helpers

    /// `$635D` / `$636A`: credit, capped at 99,999,999.
    // INFERRED: the original drops the carry out of the 8th digit (wraps);
    // the rebuild caps instead, as the notes recommend.
    mutating func credit(_ amount: Int) {
        cash = min(cash + amount, GameState.cashCap)
    }

    /// `$63F8`: charge; overdrawing sets BANKRUPT and zeroes cash (the purchase
    /// still happens).
    mutating func charge(_ amount: Int) {
        if amount > cash {
            bankrupt = !config.sandbox
            cash = 0
        } else {
            cash -= amount
        }
    }

    // MARK: clamped adjusters (§6.2)
    mutating func fameUp() { fame = min(fame + 10, 255) }          // $6856
    mutating func fameDown() { fame = max(fame - 10, 1) }          // $6866
    mutating func halveFame() { fame = (fame >> 1) | 1 }           // $6AB1
    mutating func skillUp() { skill = min(skill + 10, 255) }       // $6876
    mutating func hypeUp() { hype = min(hype + 1, 15) }            // $6896
    mutating func hypeDown() { hype = max(hype - 1, 0) }           // $68A1
}
