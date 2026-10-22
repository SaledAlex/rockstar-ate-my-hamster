import AppKit

/// Draws the Spectrum screen (original or enhanced), the enhanced side panel,
/// and forwards keys and mouse input to the console.
@MainActor
final class ScreenView: NSView {
    var console: Console?
    weak var game: Game?
    private var flash = false
    /// G toggles; remembered between launches. Default on.
    var enhanced: Bool = UserDefaults.standard.object(forKey: "enhancedGraphics") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enhanced, forKey: "enhancedGraphics")
            fitWindow()
            needsDisplay = true
        }
    }
    private var timer: Timer?
    /// Where the 256x192 picture is drawn (view coordinates, flipped).
    private var gameRect = CGRect.zero
    /// Side panel width as a fraction of the picture height.
    nonisolated static let panelRatio: CGFloat = 0.5

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    func start() {
        // Spectrum FLASH toggles every 16 frames (0.32 s).
        timer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flash.toggle()
                self?.needsDisplay = true
            }
        }
    }

    /// Window shape: 4:3, plus the side panel in enhanced mode.
    var aspect: CGFloat { 4.0 / 3.0 + (enhanced ? ScreenView.panelRatio : 0) }

    func fitWindow() {
        guard let w = window else { return }
        w.contentAspectRatio = NSSize(width: aspect * 300, height: 300)
        let h = w.contentLayoutRect.height
        var f = w.frame
        let newW = h * aspect + (f.width - w.contentLayoutRect.width)
        f.origin.x -= (newW - f.width) / 2
        f.size.width = newW
        w.setFrame(f, display: true, animate: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.08, green: 0.086, blue: 0.11, alpha: 1).setFill()
        bounds.fill()
        guard let console,
              let img = enhanced ? Enhanced.render(console.screen, flashPhase: flash)
                                 : console.screen.makeImage(flashPhase: flash),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let h0 = min(bounds.height, bounds.width / aspect)
        let scale = enhanced ? h0 / 192 : max(floor(h0 / 192 * 4) / 4, 0.25)
        let w = 256 * scale, h = 192 * scale
        let total = w + (enhanced ? h * ScreenView.panelRatio : 0)
        let rect = CGRect(x: (bounds.width - total) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        gameRect = rect
        ctx.interpolationQuality = enhanced ? .high : .none
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.maxY + rect.minY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: rect)
        ctx.restoreGState()
        if enhanced, let game {
            SidePanel.draw(game.state, in: CGRect(x: rect.maxX, y: rect.minY, width: h * ScreenView.panelRatio, height: h))
        }
    }

    // MARK: mouse: hover selects a menu option, click picks it; a click elsewhere = fire

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// Option under the mouse in `area` (character cells), if any.
    private func option(_ event: NSEvent, _ m: (top: Int, left: Int, right: Int, count: Int)?) -> Int? {
        guard let m, gameRect.width > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let col = Int((p.x - gameRect.minX) / gameRect.width * 32)
        let row = Int((p.y - gameRect.minY) / gameRect.height * 24)
        guard col >= m.left, col <= m.right, row >= m.top, row < m.top + m.count else { return nil }
        return row - m.top
    }

    /// Menu option under the mouse, if any.
    private func menuOption(_ event: NSEvent) -> Int? { option(event, console?.menuArea) }

    override func mouseMoved(with event: NSEvent) {
        if let cheats = game?.cheatMenu, cheats.open {      // overlays get the mouse first
            if let i = option(event, cheats.itemArea) { cheats.hover(i) }
            return
        }
        if game?.stats?.open == true { return }
        guard let console, let target = menuOption(event) else { return }
        var guardCount = 10
        while console.menuSel != target, console.menuArea != nil, guardCount > 0 {
            console.keyPressed(target > console.menuSel ? .down : .up)
            guardCount -= 1
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let console else { return }
        if let cheats = game?.cheatMenu, cheats.open {
            if let i = option(event, cheats.itemArea) { cheats.click(i) }
            return
        }
        if game?.stats?.open == true { console.keyPressed(.fire); return }   // any key closes it
        if console.menuArea != nil {
            guard let target = menuOption(event) else { return }   // click outside an open menu: ignore
            mouseMoved(with: event)
            if console.menuSel == target { console.keyPressed(.fire) }
        } else if gameRect.contains(convert(event.locationInWindow, from: nil)) {
            console.keyPressed(.fire)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let console, console.menuArea != nil || game?.cheatMenu?.open == true,
              game?.stats?.open != true, abs(event.scrollingDeltaY) > 2 else { return }
        console.keyPressed(event.scrollingDeltaY > 0 ? .up : .down)
    }

    override func keyDown(with event: NSEvent) {
        guard let console else { return }
        switch event.keyCode {
        case 126: console.keyPressed(.up)
        case 125: console.keyPressed(.down)
        case 36, 76: console.keyPressed(.fire)  // return, enter
        case 49: console.keyPressed(.other(" "))  // space: fire in menus, a space when typing
        case 51, 117: console.keyPressed(.delete)
        case 48: console.keyPressed(.other("\t"))       // tab: cheat menu
        case 53: console.keyPressed(.other("\u{1B}"))   // escape
        default:
            if let c = event.charactersIgnoringModifiers?.uppercased().first {
                console.keyPressed(.other(c))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let assets: Assets
        do { assets = try Assets.load() } catch {
            let alert = NSAlert()
            alert.messageText = "Game data missing"
            alert.informativeText = "Extract it from your own tapes first:\ntools/setup_assets.sh side-A.tzx side-B.tzx\n\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let view = ScreenView(frame: NSRect(x: 0, y: 0, width: 256 * 3, height: 192 * 3))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rock Star Ate My Hamster"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        MainActor.assumeIsolated {
            let console = Console(assets: assets)
            console.onChange = { view.needsDisplay = true }
            console.live = true
            view.console = console
            view.start()
            let config = GameConfig(faithfulBugs: !CommandLine.arguments.contains("--fixbugs"),
                                    sandbox: CommandLine.arguments.contains("--sandbox"),
                                    difficulty: difficultyArg(), career: CommandLine.arguments.contains("--career"))
            let args = CommandLine.arguments
            var mode: MusicMode?
            if let i = args.firstIndex(of: "--music"), i + 1 < args.count { mode = MusicMode(rawValue: args[i + 1].lowercased()) }
            let sound = SoundPlayer(mode: mode)
            console.onMute = { sound.toggleMute() }
            console.onToggleGraphics = { view.enhanced.toggle() }
            console.onToggleMusic = { sound.toggleMusic() }
            let game = Game(console: console, config: config)
            game.sound = sound
            game.cheatMenu = CheatMenu(game: game)
            game.stats = StatsScreen(game: game)
            view.game = game
            view.fitWindow()
            window.center()
            Task { @MainActor in await game.run() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

/// Headless `--enhanced`: the enhanced picture with the side panel, as the window shows it.
func enhancedWithPanel(_ screen: Screen, _ state: GameState) -> CGImage? {
    guard let pic = Enhanced.render(screen, flashPhase: false) else { return nil }
    let h: CGFloat = 768, w: CGFloat = 1024, pw = h * ScreenView.panelRatio
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w + pw), pixelsHigh: Int(h),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: h); cg.scaleBy(x: 1, y: -1)        // flipped, like the view
    NSColor(srgbRed: 0.08, green: 0.086, blue: 0.11, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: w + pw, height: h).fill()
    cg.saveGState(); cg.translateBy(x: 0, y: h); cg.scaleBy(x: 1, y: -1)
    cg.draw(pic, in: CGRect(x: 0, y: 0, width: w, height: h)); cg.restoreGState()
    SidePanel.draw(state, in: CGRect(x: w, y: 0, width: pw, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage
}

/// `--difficulty easy|normal|hard` (default normal; the windowed app also asks on a new game).
func difficultyArg() -> Difficulty {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "--difficulty"), i + 1 < a.count, let d = Difficulty(rawValue: a[i + 1].lowercased()) {
        return d
    }
    return .normal
}

/// Headless test mode: `RockStar --script "FFDU1" --png out.png [--seed N] [--fixbugs]`
/// Feeds keys to the game, then writes the final screen as a PNG and exits.
/// Script: F = fire, U = up, D = down, _ = space, < = delete, \X = literal X,
/// | = write an intermediate PNG (out-1.png, out-2.png, ...),
/// M = press fire until a menu is open (max 300 presses), anything else = that key.
func runHeadless(script: String, png: String, seed: UInt64?, config: GameConfig) {
    MainActor.assumeIsolated {
        let console: Console
        do { console = Console(assets: try Assets.load()) } catch { print("assets: \(error)"); exit(1) }
        let game = Game(console: console, config: config, seed: seed ?? 1)
        game.cheat = CommandLine.arguments.contains("--cheat")
        game.cheatMenu = CheatMenu(game: game)
        game.stats = StatsScreen(game: game)
        if ProcessInfo.processInfo.environment["RS_SAVE_DIR"] == nil {
            // headless runs never touch the player's real saves
            game.saves = SaveStore(dir: FileManager.default.temporaryDirectory
                .appendingPathComponent("rockstar-headless-\(getpid())"))
        }
        Task { @MainActor in await game.run() }
        @MainActor func write(_ path: String) {
            guard let img = CommandLine.arguments.contains("--enhanced") ? enhancedWithPanel(console.screen, game.state) : console.screen.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                             "public.png" as CFString, 1, nil)
            else { exit(1) }
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
            print("wrote \(path)  \(game.state.dateText)  cash £\(game.state.cash)  skill \(game.state.skill)  fame \(game.state.fame)  hype \(game.state.hype)  stars \(game.state.stars)")
        }
        Task { @MainActor in
            var literal = false, shot = 0
            for ch in script {
                for _ in 0..<20 { await Task.yield() }
                if literal { console.keyPressed(.other(ch)); literal = false; continue }
                switch ch {
                case "^": console.keyPressed(.other("\t"))   // cheat menu
                case "F": console.keyPressed(.fire)
                case "U": console.keyPressed(.up)
                case "D": console.keyPressed(.down)
                case "_": console.keyPressed(.other(" "))
                case "<": console.keyPressed(.delete)
                case "\\": literal = true
                case "M":
                    var n = 0
                    while !console.inMenu && n < 300 {
                        console.keyPressed(.fire); n += 1
                        for _ in 0..<20 { await Task.yield() }
                    }
                case "|":
                    shot += 1
                    write(png.replacingOccurrences(of: ".png", with: "-\(shot).png"))
                default: console.keyPressed(.other(ch))
                }
            }
            for _ in 0..<20 { await Task.yield() }
            write(png)
            exit(0)
        }
    }
    RunLoop.main.run()
}

let args = CommandLine.arguments
if let s = args.firstIndex(of: "--script"), let p = args.firstIndex(of: "--png"), s + 1 < args.count, p + 1 < args.count {
    var seed: UInt64?
    if let i = args.firstIndex(of: "--seed"), i + 1 < args.count { seed = UInt64(args[i + 1]) }
    runHeadless(script: args[s + 1], png: args[p + 1], seed: seed,
                config: GameConfig(faithfulBugs: !args.contains("--fixbugs"), sandbox: args.contains("--sandbox"), difficulty: difficultyArg(), career: CommandLine.arguments.contains("--career")))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
