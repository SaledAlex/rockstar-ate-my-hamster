import Foundation

/// The original's random number generator (rules_core.md §9).
///
/// `$A51F rnd(n)`: walk the fixed 64-byte table at `$BE59` from index `$BE57`
/// (wrapping at 64) and return the first value `<= n`, so the range is 0...n
/// inclusive and the odds follow the table, not a uniform distribution.
/// `$A53F reseed()`: index = R register & 63. The Z80 refresh register is
/// effectively random, so the rebuild draws 0...63 from its own generator.
struct SpectrumRNG: Codable {
    let table: [UInt8]
    /// `$BE57`
    var index: Int = 0
    private var seedState: UInt64

    init(table: [UInt8], seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        precondition(table.count == 64 && table.contains(0))
        self.table = table
        seedState = seed
        index = Int(nextSeed() & 63)
    }

    /// Stand-in for reading the R register.
    mutating func nextSeed() -> UInt64 {
        // SplitMix64
        seedState &+= 0x9E37_79B9_7F4A_7C15
        var z = seedState
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `$A53F`
    mutating func reseed() { index = Int(nextSeed() & 63) }

    /// `$A51F`: 0...n inclusive, table-weighted.
    mutating func rnd(_ n: Int) -> Int {
        while true {
            let v = Int(table[index])
            index = (index + 1) & 63
            if v <= n { return v }
        }
    }

    /// Exact probability of `rnd(n) == v` when the start index is uniform
    /// (used by tests and documentation).
    func probability(of v: Int, n: Int) -> Double {
        var hits = 0
        for start in 0..<64 {
            var i = start
            while Int(table[i]) > n { i = (i + 1) & 63 }
            if Int(table[i]) == v { hits += 1 }
        }
        return Double(hits) / 64
    }
}
