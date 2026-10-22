import AppKit

/// In-game editor for custom rock stars (title screen > STAR CREATOR).
/// Edits the same stars.json as CustomStars; changes apply to the next game.
@MainActor
struct StarCreator {
    let game: Game
    private var ui: Console { game.ui }

    static let instruments = ["vocals", "guitar", "keyboards", "drums"]
    static let fames = [5, 10, 15, 20, 25, 30, 50, 80, 120]
    static let skills = [0, 3, 6, 9, 12, 15, 25, 40, 60]
    static let moods = [10, 20, 35, 50, 70, 90]
    static let wages = [50, 100, 500, 1_000, 2_000, 5_000, 10_000, 18_000, 30_000]

    /// Next value in `list` after `v` (wrapping), so FIRE cycles through presets.
    static func next(_ v: Int, in list: [Int]) -> Int { list.first { $0 > v } ?? list[0] }

    func run() async {
        var list = CustomStars.entries()
        var sel = 0
        while true {
            background(nil)
            let items = list.map { "\($0.name.uppercased().prefix(18)) £\($0.wage ?? 2_000)" }
                + ["+ NEW STAR", "BACK"]
            sel = await game.pickList(title: "STAR CREATOR", items: items, initial: min(sel, items.count - 1))
            if sel == items.count - 1 { return }
            let isNew = sel == list.count
            var star = isNew ? CustomStar(name: "NEW STAR", instrument: "vocals", fame: 15, skill: 6, mood: 35,
                                          wage: 1_000, voice: Int.random(in: 0...7), gear: 4, portrait: nil)
                             : list[sel]
            if isNew {
                background(star)
                star.name = await askName(current: nil) ?? star.name
            }
            switch await edit(&star, canDelete: !isNew) {
            case .save:
                if isNew { list.append(star) } else { list[sel] = star }
            case .delete:
                list.remove(at: sel)
            case .cancel:
                continue
            }
            do { try CustomStars.save(list) } catch { NSSound.beep() }
        }
    }

    private enum Outcome { case save, delete, cancel }

    private func edit(_ star: inout CustomStar, canDelete: Bool) async -> Outcome {
        var sel = 0
        while true {
            background(star)
            let items = [
                "NAME: " + star.name.uppercased(),
                "PLAYS: " + (star.instrument ?? "vocals").uppercased(),
                "FAME: \(star.fame ?? 15)",
                "SKILL: \(star.skill ?? 7)",
                "MOOD: \(star.mood ?? 35)",
                "WAGE: £\(star.wage ?? 2_000) A WEEK",
                "STYLE: \(star.voice ?? 0)",
                "GEAR: \(star.gear ?? 4)",
                "PICTURE: " + (star.portrait == nil ? "INITIALS" : "FROM FILE"),
                "SAVE", canDelete ? "DELETE" : "CANCEL", canDelete ? "CANCEL" : "",
            ].filter { !$0.isEmpty }
            sel = await game.pickList(title: "EDIT STAR", items: items, initial: sel)
            switch sel {
            case 0: star.name = await askName(current: star.name) ?? star.name
            case 1:
                let i = StarCreator.instruments.firstIndex(of: star.instrument ?? "vocals") ?? 0
                star.instrument = StarCreator.instruments[(i + 1) % 4]
            case 2: star.fame = StarCreator.next(star.fame ?? 15, in: StarCreator.fames)
            case 3: star.skill = StarCreator.next(star.skill ?? 7, in: StarCreator.skills)
            case 4: star.mood = StarCreator.next(star.mood ?? 35, in: StarCreator.moods)
            case 5: star.wage = StarCreator.next(star.wage ?? 2_000, in: StarCreator.wages)
            case 6: star.voice = ((star.voice ?? 0) + 1) % 8     // suggested band name / music style
            case 7: star.gear = ((star.gear ?? 4) + 1) % 8
            case 8: star.portrait = star.portrait == nil ? pickPicture(for: star) : nil
            case 9: return .save
            case 10: return canDelete ? .delete : .cancel
            default: return .cancel
            }
        }
    }

    /// Black screen with the star's portrait preview at the top.
    private func background(_ star: CustomStar?) {
        var s = Screen()
        s.clear(attr: 0x07)
        if let star {
            let r = CustomStars.record(star)
            s.fillAttr(col: 13, row: 0, width: 5, height: 6, attr: 0x78)
            s.blit(r.portraitBytes, bytesWide: 5, x: 13 * 8, y: 0)
            let n = String(r.name.prefix(12))
            s.drawText(n, col: max(0, 12 - n.count), row: 2, font: ui.assets.font)
        }
        ui.screen = s
        ui.onChange()
    }

    private func askName(current: String?) async -> String? {
        let t = await ui.readLine(maxLength: 20)
        return t.isEmpty ? current : t
    }

    /// File picker; copies the chosen picture into the custom-stars folder.
    /// Returns nil (back to initials) when cancelled.
    private func pickPicture(for star: CustomStar) -> String? {
        let p = NSOpenPanel()
        p.title = "Choose a picture for \(star.name)"
        p.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic, .bmp]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let src = p.url else { return nil }
        let slug = star.name.lowercased().filter { $0.isLetter || $0.isNumber }
        let name = (slug.isEmpty ? "star" : slug) + "." + src.pathExtension.lowercased()
        let dst = CustomStars.dir.appendingPathComponent(name)
        CustomStars.writeHelpFiles()
        try? FileManager.default.removeItem(at: dst)
        do { try FileManager.default.copyItem(at: src, to: dst) } catch { return nil }
        return name
    }
}
