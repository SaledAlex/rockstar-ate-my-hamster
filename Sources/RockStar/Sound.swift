import AVFoundation
import Foundation

/// Which rendering of the original's sound to use (`--music 48k|128k|off`).
/// 48k = the beeper routines ($EDC6-$EDCC), 128k = the AY driver from the headerless
/// tape block, off = no jingles or tunes (sound effects still play).
enum MusicMode: String { case beeper = "48k", ay = "128k", off }

/// Plays the WAVs that tools/make_audio.py renders from the original code
/// (Resources/audio). Only the windowed app creates one, so headless runs are silent.
@MainActor
final class SoundPlayer {
    private let dir: URL?
    let mode: MusicMode
    private(set) var muted = false
    /// M: music and jingles off, sound effects stay on.
    private(set) var musicMuted = false
    private var music: AVAudioPlayer?
    private var effect: AVAudioPlayer?
    /// Representative practice-tune renders (see make_audio.py SEEDS / SKILLS).
    static let seeds = [0, 5, 10, 15, 16, 21, 26, 31]
    static let skills = [0, 50, 100, 200]

    init(mode requested: MusicMode?) {
        dir = Bundle.module.url(forResource: "Resources/audio", withExtension: nil)
        let hasAY = dir.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("ay_jingle0.wav").path) } ?? false
        mode = requested ?? (hasAY ? .ay : .beeper)
    }

    private var prefix: String { mode == .ay ? "ay" : "beeper" }

    private func url(_ name: String) -> URL? {
        guard let dir else { return nil }
        for p in [prefix, "beeper", "ay"] {
            let u = dir.appendingPathComponent("\(p)_\(name).wav")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    private func start(_ name: String) -> AVAudioPlayer? {
        guard !muted, let u = url(name), let p = try? AVAudioPlayer(contentsOf: u) else { return nil }
        p.play()
        return p
    }

    /// `$812A` jingle n (0 title, 1 good news, 2 bad news, 3 newspaper, 4 game over,
    /// 5 platinum, 6 stage intro, 7 bad end).
    func jingle(_ n: Int) {
        guard mode != .off, !musicMuted else { return }
        music?.stop()
        music = start("jingle\(n)")
    }

    /// `$8145` sfx n (0 phone picked up, 1 event alert).
    func sfx(_ n: Int) {
        effect?.stop()
        effect = start("sfx\(n)")
    }

    /// `$80EE` practice/chart tune: the nearest pre-rendered seed and skill.
    func tune(seed: Int, skill: Int) {
        guard mode != .off, !musicMuted else { return }
        let s = SoundPlayer.seeds[seed % SoundPlayer.seeds.count]
        let k = SoundPlayer.skills.min { abs($0 - skill) < abs($1 - skill) } ?? 100
        music?.stop()
        music = start("practice_\(s)_\(k)")
    }

    func stopMusic() { music?.stop(); music = nil }

    func toggleMusic() {
        musicMuted.toggle()
        if musicMuted { stopMusic() }
    }

    func toggleMute() {
        muted.toggle()
        if muted { music?.stop(); effect?.stop(); music = nil; effect = nil }
    }
}
