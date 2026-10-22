# Rock Star Ate My Hamster: native macOS rebuild

A from-scratch native macOS reimplementation of **Rock Star Ate My Hamster**, the
music-management comedy published by Codemasters in 1988 for the ZX Spectrum.

The game rules were reverse-engineered from the original Z80 machine code and rebuilt
in Swift. Formulas, odds and tables match the Spectrum version, including its
random-number generator and (optionally) its bugs. It runs natively on Apple Silicon and
Intel Macs, with crisp pixel scaling at any window size.

> **No game data is included.** This repository contains only new code. The text,
> graphics, portraits and tables are extracted at build time from **your own copy**
> of the original Spectrum tapes, the same approach used by ScummVM and similar
> projects. Please don't commit or redistribute the extracted files or a built app.

## Requirements

- macOS 13 or later
- Xcode or the Swift 5.9+ command-line tools (`xcode-select --install`)
- Python 3 (ships with the command-line tools)
- The original ZX Spectrum tapes as `.tzx` files: **side A** (game) and **side B**
  (the rock star data tape)

## Getting started

```sh
git clone <this repo>
cd rockstar-ate-my-hamster

# 1. Extract the game data from your tapes (installs SkoolKit into a local .venv)
tools/setup_assets.sh "path/to/Side A.tzx" "path/to/Side B.tzx"

# 2. Play
swift run -c release RockStar

# Optional: build a double-clickable app in dist/
tools/package_app.sh
```

`setup_assets.sh` loads side A in [SkoolKit](https://skoolkit.ca)'s tape simulator, so
the game's memory matches a real Spectrum after loading, then pulls out what the rebuild
needs. Nothing leaves your machine.

## Controls
| action | keys |
|---|---|
| menu up / down | Up / Down arrows, or the original's `9 7 P` / `8 6 L` |
| fire / confirm | Return, Enter, Space or `0` |
| menu shortcut | `1`...`n` picks option n |
| hire a rock star | Fire accepts. Any other key (or waiting 6 s) rejects. Up goes back one record. |
| typing names | letters, Space, Delete, then Return (at least 2 characters) |
| title screen | Fire or `K` (the Kempston option, accepted but meaningless here) |
| mute / unmute sound | `S` (not while typing a name) |

Command-line options: `--fixbugs` turns `faithfulBugs` off (see below).
`--music 48k|128k|off` picks the beeper or AY renderings (default `128k` when the AY files
were rendered, else `48k`); `off` silences jingles and tunes but keeps the sound effects.

## How to play

You're Cecil Pitt, a failed theatrical agent with £50,000 from Aunt Mabel. Hire up to
four rock stars from 50 parodies of real musicians, buy their gear, and spend one year
practising, touring, pulling publicity stunts and keeping your stars happy enough not to
quit. Sign a record deal, record an album, shoot videos and climb the charts against 30
rival bands.

**You win by earning four gold discs before 31 December.** You lose if you go bankrupt,
run out of time, or lose every member of the band. It's hard, just like the original.

## Faithful to the original

- All 214 messages, including the random word swaps ("FAR OUT/GROOVY/OUTASIGHT, CHIEF!").
- The original font, scene graphics (office, limo, screening room, studio), portraits,
  status panel, newspaper and chart show.
- The original random-number generator: it walks the same fixed 64-byte table, so the
  odds of every event match the Spectrum.
- Every rule: wages, ticket sales, contracts, chart movement, royalties, gold discs,
  charity gigs, sponsors, bootleggers, publicity deaths, star demands and quitting.

### Original bugs

These are kept by default so the game plays like the original. Start with `--fixbugs`
to correct them:

| Original behaviour | With `--fixbugs` |
|---|---|
| A 2-star band's skill uses stale bytes from the previous game | Uses the two stars' skill |
| Wages are paid for the first slots, not the stars still in the band | Pays the current band |
| A single that should reach #1 can drop a place instead | Moves up correctly |
| "Buy the pirates out" doesn't stop the piracy | Stops it |
| The sponsor scandal counter never reloads | Reloads |
| The £1M producer ransom is skipped when cash is £10M–£19.99M, etc. | Checks cash ≥ £1M |

## Beyond the original

Everything below is optional; with the defaults switched off (`G` for the original graphics, Normal difficulty, `--classic-events`) the game plays like the 1988 original.

### Enhanced graphics
The game starts in **enhanced** mode: a softer colour palette, the pixel art smoothed
with Scale4x (rounded diagonals, no blur), and all text redrawn in a crisp modern font at
full resolution. Press **G** to switch between enhanced and the original Spectrum look;
the choice is remembered. Enhanced mode also adds a **side panel** next to the picture
(cash, fame/skill/street-cred bars, record deal, chart positions, gold discs and progress,
each star's mood and wage) and **mouse support**: hover a menu option to select it, click
to pick it, click anywhere else to continue (scroll wheel moves through menus too).
**M** turns the music off and on while keeping the sound effects; **S** mutes everything.
Headless screenshots use the enhanced renderer (with the panel) via `--enhanced`.

### Difficulty and stats
A new game asks for a difficulty (or pass `--difficulty easy|normal|hard`):

| | Easy | Normal (original) | Hard |
|---|---|---|---|
| Starting cash | £100,000 | £50,000 | £25,000 |
| Wages | 50% | 100% | 150% |
| Royalties | 150% | 100% | 75% |
| Disc points for discs 1/2/3/platinum | 25/60/100/150 | 40/100/170/250 | 40/100/170/250 |

Press **I** at any prompt for the **band stats** screen: cash, fame, skill, street cred,
record deal, chart positions, disc points and the next target, each star's mood
(happy / demanding / about to quit) and wage, and the weekly wage bill. Any key closes it.
The difficulty is stored in save games.

### Career mode
After choosing the difficulty, pick **Classic** (the original single year) or **Career**
(or start with `--career`). In a career the game doesn't end on 31 December or at
platinum. Every New Year Clive reviews the year (discs, fame, cash), then a fresh year of
records starts: gold discs and disc points reset and a new album is needed, but your
record label, fame and skill carry over. Wages rise 10% a year, and stars get older: from
year 2 each one has a growing chance to retire (10% a year, up to 50%). New talent is
offered for the empty places. Each New Year you choose to carry on or retire; going
bankrupt or losing the whole band also ends the career. The final screen counts years
and platinum albums. The side panel and stats screen show the career year and platinums.

### Custom rock stars
Add your own musicians with the **Star creator** on the title screen (after pressing
fire): pick *+ New star*, type a name, then set what they play (vocals, guitar, keyboards,
drums), fame, skill, mood, weekly wage, style (which suggested band name/music they bring),
how much gear they need, and a picture (any image file; it is cropped to 40x48 and
dithered into black-and-white Spectrum pixels, or the star gets their initials). FIRE
cycles through the values; the portrait preview updates as you go. Existing stars can be
edited or deleted. Custom stars are offered first when hiring, before the 50 tape stars.

Behind the scenes they live in
`~/Library/Application Support/RockStarAteMyHamster/custom-stars/stars.json` (plus the
pictures), which you can also edit by hand; see the `README.txt` there. Tests and headless
scripts ignore them unless `RS_CUSTOM_DIR` points at a folder.

### New events
Sixteen new random events (not in the original) can happen after a turn: a festival
headline slot, a live TV appearance, a dressing-room feud, the hamster scandal, a tax
rebate, a stolen tour van, a celebrity cookbook, an awards night, a world tour, a solo
yodelling album, a tell-all autobiography, a charity single, a rival band slagging you
off, a rival manager poaching a star, a trashed hotel and the fan club. They affect
cash, fame, skill, street cred and the stars' moods (and a poached star can leave).
Each happens once per game until all allowed ones have been seen.

In the **Tab** cheat menu, **New events...** lets you switch each event on or off and set
how often they happen (1 in 2, 3, 5 or 10 turns, or never); ALL ON / ALL OFF included.
The settings are remembered. `--classic-events` turns them all off for one session.
(Test aid: `RS_FORCE_EVENT=n` runs event n after every turn, also in headless mode.)

### Saving and loading
The game **autosaves at the start of every turn** (when the "what shall we do now"
menu appears). For manual saves, open the **Tab** menu and choose *Save to slot 1-3*.
At the main menu that saves the game exactly as it is; in the middle of an action
(a tour, recording...) it saves the start of the current turn, because games always
resume at the main menu. When saves exist, the title screen shows a **Load game**
list after you press fire: pick *New game*, the autosave or a slot.
Saves live in `~/Library/Application Support/RockStarAteMyHamster/` (override with
`RS_SAVE_DIR`); headless runs use a temporary folder.

### Cheat menu and sandbox mode
Press **Tab** at any prompt (except while typing a name) to open the cheat menu:
cash +£100,000 / +£1,000,000, fame +50, skill +50, street cred max, make the band
happy, gold disc +1 (the 4th is platinum = win at the end of the turn), and a
**sandbox** toggle. Sandbox means no bankruptcy (cash just stops at £0) and no end of
year (the calendar rolls over into a new January). Tab or Esc returns to the game.
Start in sandbox mode with `--sandbox`. Headless scripts open the menu with `^`.

### Sound and music
`tools/setup_assets.sh` records every sound by running the original game's own sound code in
SkoolKit's tracer (nothing is hand-made). **S** mutes everything, **M** turns the music off but
keeps the effects, and `--music 48k|128k|off` picks the beeper or AY versions (default 128k).

| file (`Resources/audio/`) | original code | plays when |
|---|---|---|
| `*_jingle0` | `$812A` A=0 (48K `$EDC9`, 128K `$C003`) | title screen (`$61C1`) |
| `*_jingle1` | A=1 | publicity story (`$7FEF`), charity: real+yes / fake+no (`$6339`, `$6320`) |
| `*_jingle2` | A=2 | publicity "nobody cares" (`$7F8C`, `$7F99`), charity: real+no / fake+yes |
| `*_jingle3` | A=3 | THE STUN newspaper (`$7F7E`, `$8073`, `$6AA4`) |
| `*_jingle4` | A=4 | game over, after Cecil's reply (`$6A31`) |
| `*_jingle5` | A=5 | platinum disc win (`$6A7D`) |
| `*_jingle6` | A=6 | stage-intro poster (`$82B3`) |
| `*_jingle7` | A=7 | bankrupt / out of time / no stars (`$6A24`) |
| `*_sfx0` | `$8145` A=0 (`$EDCC` / `$C006`) | phone picked up (`$7E83`) |
| `*_sfx1` | `$8145` A=1 | phone/event alert: contract, charity, sponsor offer and pull-out, bootleggers, sued/taxman, producer ransom |
| `*_practice_<seed>_<skill>` | `$80EE` (P. Hiley composer `$F067`; 128K: `$C000` with `$C009-$C011`) | each practice day (`$68F4`); one per chart page |

`beeper_*` come from the 48K snapshot, `ay_*` from the 6,328-byte headerless block in RAM
bank 1 of a 128K tape load of side A. The practice tune depends on a seed (0-31), three
voice bytes from the stars and SKILL (wrong/missing notes); 8 seeds x skills 0/50/100/200 are
pre-rendered and the nearest skill is played. INFERRED: the voice bytes per seed, the tune
seed (host RNG, so the rules' RNG is untouched), one tune per chart page instead of one per
entry, and sfx 0 on every phone pick-up. Headless mode never creates the player, so it is silent.

## Not yet included

- The chart show appears a page at a time with one tune per page; the original scrolls each entry in with its own tune.
- A few screen layouts are close approximations; choices the original code didn't settle are marked `// INFERRED:` in the source.

## For developers

```sh
swift test                                    # 38 tests: rules, assets, saves, 60 autoplayed games
swift run RockStar --script "FFDD" --png out.png --seed 1   # headless run + screenshot
```

Headless script keys: `F` fire, `U` up, `D` down, `M` press fire until a menu opens,
`|` save an intermediate screenshot, `_` space, `<` delete, `\X` literal X. Other
options: `--seed N`, `--fixbugs`, `--cheat` (start rich and famous, for testing),
`RS_TRACE=1` (log every message and menu).

### Layout

| Path | What |
|---|---|
| `Sources/RockStar/Model/` | The rules as pure Swift, no UI. RAM addresses of the original routines are in comments. |
| `Sources/RockStar/Game.swift` | Game flow: drives the model with the original messages, menus and screens. |
| `Sources/RockStar/Console.swift` | Message assembly, speech bubble, menus, text entry. |
| `Sources/RockStar/Graphics.swift`, `Screen.swift` | Spectrum-style 256×192 display and the original sprite/attribute lists. |
| `tools/setup_assets.sh` | Extracts the game data from your tapes. |
| `tools/make_assets.py`, `tzx_dump.py`, `snap_ram.py` | The extraction steps. |
| `tools/package_app.sh` | Builds `dist/Rock Star Ate My Hamster.app`. |

## Credits

The original *Rock Star Ate My Hamster* was written and programmed by Colin Jones, with
graphics by Chris Graham, published by Codemasters (1988). All rights to the original
game, its text and artwork belong to their respective owners. This is an unofficial
fan project, not affiliated with or endorsed by Codemasters.

Tape loading uses [SkoolKit](https://skoolkit.ca) by Richard Dymond.
