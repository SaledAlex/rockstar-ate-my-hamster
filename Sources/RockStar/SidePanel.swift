import AppKit

/// Enhanced-mode side panel next to the game picture (not in the original):
/// the band's numbers at a glance, drawn natively at full resolution.
enum SidePanel {
    private static let bg = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    private static let dim = NSColor(srgbRed: 0.6, green: 0.62, blue: 0.7, alpha: 1)
    private static let text = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.92, alpha: 1)
    private static let gold = NSColor(srgbRed: 0.96, green: 0.8, blue: 0.3, alpha: 1)
    private static let cyan = NSColor(srgbRed: 0.35, green: 0.85, blue: 0.92, alpha: 1)

    static func draw(_ st: GameState, in r: CGRect) {
        bg.setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: r.width * 0.04, dy: r.width * 0.04),
                     xRadius: r.width * 0.04, yRadius: r.width * 0.04).fill()
        let pad = r.width * 0.1, u = r.height / 40          // u: one "line unit"
        var y = r.minY + pad * 0.8
        let x = r.minX + pad, w = r.width - 2 * pad

        func label(_ s: String, size: CGFloat = 1, color: NSColor = text, bold: Bool = false) {
            let f = NSFont.systemFont(ofSize: u * size, weight: bold ? .bold : .medium)
            let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
            a.draw(in: CGRect(x: x, y: y, width: w, height: u * size * 1.4))
            y += u * size * 1.35
        }
        func bar(_ name: String, _ v: Int, _ max: Int, _ color: NSColor) {
            label("\(name)  \(v)", size: 0.9, color: dim)
            let track = CGRect(x: x, y: y, width: w, height: u * 0.55)
            NSColor(white: 1, alpha: 0.1).setFill()
            NSBezierPath(roundedRect: track, xRadius: u * 0.27, yRadius: u * 0.27).fill()
            color.setFill()
            var fill = track
            fill.size.width = w * CGFloat(min(v, max)) / CGFloat(max)
            NSBezierPath(roundedRect: fill, xRadius: u * 0.27, yRadius: u * 0.27).fill()
            y += u * 1.1
        }

        label(st.bandName.isEmpty ? "No band yet" : st.bandName.capitalized, size: 1.6, bold: true)
        label("\(GameState.dayNames[st.dayOfWeek].capitalized) \(st.dayOfMonth) "
              + "\(GameState.monthNames[min(st.month, 11)].capitalized) · "
              + st.config.difficulty.rawValue.capitalized + (st.config.sandbox ? " · Sandbox" : "")
              + (st.config.career ? " · Year \(st.config.careerYear)" : ""),
              size: 0.9, color: dim)
        y += u * 0.4
        label("£\(st.cash.formatted())", size: 2.2, color: st.cash < 10_000 ? NSColor.systemRed : gold, bold: true)
        y += u * 0.3
        bar("Fame", st.fame, 255, cyan)
        bar("Skill", st.skill, 255, NSColor.systemGreen)
        bar("Street cred", st.hype, 15, NSColor.systemPink)

        y += u * 0.3
        let deal = st.label == 0 ? "No record deal"
            : "\(StatsScreen.labels[min(st.label, 5)].capitalized) · \(st.royaltyPercent(tier: st.label))%"
        label(deal, size: 1, color: text)
        func pos(_ p: Int) -> String { p == 0 ? "–" : (p <= 10 ? "#\(p)" : "out") }
        label("Single \(pos(st.singlePos))   Album \(pos(st.albumPos))", size: 1, color: text)

        // gold discs: four circles + progress to the next one
        y += u * 0.4
        let t = st.config.difficulty.discThresholds
        let got = st.discs.filter { $0 }.count
        let d = u * 1.6
        for i in 0..<4 {
            let c = CGRect(x: x + CGFloat(i) * (d + u * 0.5), y: y, width: d, height: d)
            (st.discs[i] ? (i == 3 ? NSColor.white : gold) : NSColor(white: 1, alpha: 0.12)).setFill()
            NSBezierPath(ovalIn: c).fill()
            bg.setFill()
            NSBezierPath(ovalIn: c.insetBy(dx: d * 0.38, dy: d * 0.38)).fill()
        }
        y += d + u * 0.3
        if got < 4 { bar("Disc points", st.discPoints, t[got], gold) }
        if st.config.career {
            label("Career: year \(st.config.careerYear) · \(st.config.platinums) platinum", size: 0.9, color: dim)
        }

        y += u * 0.3
        label("The band", size: 1, color: dim, bold: true)
        for i in 0..<4 where !st.gone[i] {
            let m = st.mood[i]
            let colour: NSColor = m >= 9 ? .systemGreen : (m >= 4 ? .systemYellow : .systemRed)
            colour.setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: y + u * 0.35, width: u * 0.6, height: u * 0.6)).fill()
            let wage = st.wages[i] * st.config.difficulty.wagePercent / 100
            let a = NSAttributedString(string: "\(st.starNames[i].capitalized)  £\(wage)/wk",
                                       attributes: [.font: NSFont.systemFont(ofSize: u * 0.9, weight: .medium),
                                                    .foregroundColor: text])
            a.draw(in: CGRect(x: x + u, y: y, width: w - u, height: u * 1.3))
            y += u * 1.3
        }

        // key help at the bottom
        y = r.maxY - pad * 0.8 - u * 0.9 * 1.35 * 3
        label("I stats · Tab cheats · G graphics", size: 0.8, color: dim)
        label("S sound · M music · mouse works", size: 0.8, color: dim)
    }
}
