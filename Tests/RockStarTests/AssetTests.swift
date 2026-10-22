import XCTest
@testable import RockStar

@MainActor
final class AssetTests: XCTestCase {
    func testAssetsLoad() throws {
        let a = try Assets.load()
        XCTAssertEqual(a.messages.count, 214)
        XCTAssertEqual(a.rockStars.count, 50)
        XCTAssertEqual(a.rockStars[0].name, "WACKY JACKO")
        XCTAssertEqual(a.rockStars[0].portraitBytes.count, 240)
        XCTAssertEqual(a.font.data.count, 96 * 6)
    }

    func testMessageResolution() throws {
        let c = Console(assets: try Assets.load())
        XCTAssertEqual(c.resolve(0), "ONE DAY AT THE OFFICE OF THE CECIL PITT THEATRICAL AGENCY...")
        c.strings[0] = "THE HAMSTERS"
        c.numbers = [0: 5000, 1: 2500, 2: 500]
        XCTAssertEqual(c.resolve(15),
            "NOW WE'D BETTER BUY THE HAMSTERS SOME EQUIPMENT. IT'LL COST £5000 NEW, £2500 SECOND HAND OR £500 OFF THE BACK OF A LORRY!")
    }

    func testGameDataAndGraphics() throws {
        let a = try Assets.load()
        XCTAssertEqual(a.gameData.rivals.count, 30)
        XCTAssertEqual(a.gameData.rivals[0].single, [0x84, 0x22, 0x02, 0x85, 0x07])
        XCTAssertEqual(a.gameData.rivals[29].album, [0x82, 0x16, 0x02, 0x83, 0x06])
        XCTAssertEqual(a.gameData.rivals[1].songChoices, [27, 24, 24])
        XCTAssertEqual(a.gameData.nameStrings.count, 58)
        XCTAssertEqual(a.gameData.bandNames.count, 8)
        XCTAssertEqual(a.gameData.respawnScores, [25, 45, 33, 21, 19, 36])
        XCTAssertEqual(a.gameData.studioDays, [6, 5, 4, 3, 2, 1])
        XCTAssertEqual(a.graphics.spriteLists.count, 23)
        XCTAssertEqual(a.graphics.attrLists.count, 19)
        XCTAssertEqual(hexBytes(a.graphics.loadingScreen).count, 6912)
        XCTAssertEqual(hexBytes(a.graphics.bigFont).count, 28 * 59)
    }

    func testRuntimePatchedMessages() throws {
        let c = Console(assets: try Assets.load())
        c.pick = { _ in 0 }
        c.strings[0] = "THE POTATOES"
        // msg 13 suggests the band name (ref $C0 00 = STR0, decoded like the printer at $A8F5)
        XCTAssertTrue(c.resolve(13).contains("I SUGGEST THE POTATOES!"))
        c.numbers = [0: 200, 1: 10]
        XCTAssertTrue(c.resolve(34, patches: [4: "PUB "]).hasPrefix("OK BOSS, A PUB SEATS 200 AND COSTS £10"))
        XCTAssertTrue(c.resolve(126, patches: [17: "S "]).contains("ROCK STARS?"))
        XCTAssertTrue(c.resolve(126, patches: [17: " "]).contains("ROCK STAR?"))
        XCTAssertEqual(c.options(fromMessage: 18, box: 4), ["PRACTICE", "GIG", "PUBLICITY", "GIFTS"])
        XCTAssertEqual(c.options(fromMessage: 47, box: 10).count, 7)
        XCTAssertEqual(c.options(fromMessage: 171, box: 71).count, 4)
    }
}
