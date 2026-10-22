import AppKit

/// "Enhanced" graphics (not in the original; G toggles it):
/// a softer palette, the pixel art smoothed with Scale4x (Scale2x twice, which
/// rounds diagonals without blurring), and all game text redrawn with a crisp
/// modern font at full resolution.
enum Enhanced {
    /// Softer Spectrum palette (normal, bright), RGB.
    static let palette: [[UInt32]] = [
        [0x14161C, 0x2B3C9E, 0xB8333A, 0xA03A9C, 0x3C9E4A, 0x2F9AA8, 0xC2A83A, 0xC8C8C4],
        [0x14161C, 0x4766E0, 0xF0505A, 0xE25ADC, 0x5CDA6A, 0x52DCEA, 0xF4DC5A, 0xFAFAF4],
    ]
    static let scale = 4

    static func render(_ s: Screen, flashPhase: Bool) -> CGImage? {
        let w = Screen.width, h = Screen.height
        // 1. base image; text cells keep only their paper colour
        var px = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let cell = (y >> 3) * Screen.cols + (x >> 3)
                let (ink, paper) = colours(s.attrs[cell], flashPhase)
                let on = s.textCells[cell] == nil && s.pixels[y * w + x]
                px[y * w + x] = on ? ink : paper
            }
        }
        // 2. Scale4x
        var (img, iw, ih) = scale2x(px, w, h)
        (img, iw, ih) = scale2x(img, iw, ih)
        // 3. into a bitmap context, then draw the text on top
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: iw, height: ih, bitsPerComponent: 8, bytesPerRow: iw * 4,
                                  space: cs, bitmapInfo: info) else { return nil }
        img.withUnsafeMutableBytes { buf in
            if let dst = ctx.data { dst.copyMemory(from: buf.baseAddress!, byteCount: buf.count) }
        }
        let cellPx = CGFloat(8 * scale)
        let font = NSFont(name: "Menlo-Bold", size: cellPx * 0.95)
            ?? NSFont.monospacedSystemFont(ofSize: cellPx * 0.95, weight: .bold)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        for r in 0..<Screen.rows {
            for c in 0..<Screen.cols {
                guard let ch = s.textCells[r * Screen.cols + c] else { continue }
                let (ink, _) = colours(s.attrs[r * Screen.cols + c], flashPhase)
                let str = NSAttributedString(string: ch == "`" ? "£" : String(ch), attributes: [
                    .font: font, .foregroundColor: nsColor(ink),
                ])
                let size = str.size()
                let x = CGFloat(c) * cellPx + (cellPx - size.width) / 2
                // CG origin is bottom-left; row 0 is the top of the screen
                let y = CGFloat(Screen.rows - 1 - r) * cellPx + (cellPx - size.height) / 2
                str.draw(at: CGPoint(x: x, y: y))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private static func colours(_ a: UInt8, _ flash: Bool) -> (UInt32, UInt32) {
        let bright = Int((a >> 6) & 1)
        var ink = Int(a & 7), paper = Int((a >> 3) & 7)
        if a & 0x80 != 0 && flash { swap(&ink, &paper) }
        return (0xFF00_0000 | palette[bright][ink], 0xFF00_0000 | palette[bright][paper])
    }

    private static func nsColor(_ argb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: 1)
    }

    /// Scale2x / EPX: each pixel becomes 2x2, corners take a neighbour's colour
    /// where two neighbours agree, which smooths diagonals in pixel art.
    static func scale2x(_ src: [UInt32], _ w: Int, _ h: Int) -> ([UInt32], Int, Int) {
        let ow = w * 2
        var out = [UInt32](repeating: 0, count: ow * h * 2)
        for y in 0..<h {
            for x in 0..<w {
                let p = src[y * w + x]
                let a = y > 0 ? src[(y - 1) * w + x] : p
                let b = x < w - 1 ? src[y * w + x + 1] : p
                let c = x > 0 ? src[y * w + x - 1] : p
                let d = y < h - 1 ? src[(y + 1) * w + x] : p
                var e0 = p, e1 = p, e2 = p, e3 = p
                if c == a && c != d && a != b { e0 = a }
                if a == b && a != c && b != d { e1 = b }
                if d == c && d != b && c != a { e2 = c }
                if b == d && b != a && d != c { e3 = d }
                let o = (y * 2) * ow + x * 2
                out[o] = e0; out[o + 1] = e1; out[o + ow] = e2; out[o + ow + 1] = e3
            }
        }
        return (out, ow, h * 2)
    }
}
