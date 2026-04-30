import SwiftUI

extension Color {
    init(rgbHex hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

struct CellStyle {
    let fg: Color
    let bg: Color
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

private func lerpRGB(_ low: (Double, Double, Double), _ high: (Double, Double, Double), _ t: Double) -> Color {
    let tt = max(0, min(1, t))
    return Color(red: lerp(low.0, high.0, tt) / 255.0,
                 green: lerp(low.1, high.1, tt) / 255.0,
                 blue: lerp(low.2, high.2, tt) / 255.0)
}

func beaufortStyleKn(_ kn: Double) -> CellStyle {
    if kn < 7 {
        return CellStyle(
            fg: Color(rgbHex: 0x1d1d1d),
            bg: lerpRGB((244, 244, 242), (208, 212, 208), kn / 7.0))
    }
    if kn < 11 {
        return CellStyle(
            fg: Color(rgbHex: 0x0b1f0f),
            bg: lerpRGB((204, 232, 204), (96, 168, 110), (kn - 7) / 4.0))
    }
    if kn < 17 {
        return CellStyle(
            fg: Color(rgbHex: 0x2a2206),
            bg: lerpRGB((247, 232, 152), (208, 168, 50), (kn - 11) / 6.0))
    }
    if kn < 22 {
        return CellStyle(
            fg: Color(rgbHex: 0x2a1400),
            bg: lerpRGB((247, 196, 130), (208, 116, 38), (kn - 17) / 5.0))
    }
    return CellStyle(
        fg: Color(rgbHex: 0xfff5f5),
        bg: lerpRGB((230, 132, 132), (132, 24, 24), min(1.0, (kn - 22) / 28.0)))
}

func tempStyleC(_ t: Double) -> CellStyle {
    let x = max(0.0, min(1.0, (t + 5.0) / 35.0))
    let r = lerp(255, 230, x) / 255.0
    let g = lerp(240, 120, x) / 255.0
    let b = lerp(180, 40, x) / 255.0
    let fg = t < 12 ? Color(rgbHex: 0x201005) : Color(rgbHex: 0x1a0a05)
    return CellStyle(fg: fg, bg: Color(red: r, green: g, blue: b))
}

func directionArrow(degFrom: Double?) -> String {
    guard let d = degFrom else { return "·" }
    let from = (d.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let to = (from + 180).truncatingRemainder(dividingBy: 360)
    let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
    let idx = Int((to + 22.5) / 45.0) % 8
    return arrows[idx]
}

func msToKn(_ ms: Double?) -> Double? {
    guard let ms else { return nil }
    return ms * WeatherConstants.msToKn
}
