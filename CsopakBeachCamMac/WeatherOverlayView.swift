import SwiftUI

private let baseFontSize: CGFloat = 10
private let cellW: CGFloat = 22
private let cellH: CGFloat = 14
private let labelW: CGFloat = 78
private let timeColW: CGFloat = 28

private func monoFont(weight: Font.Weight = .bold) -> Font {
    .system(size: baseFontSize, weight: weight, design: .monospaced)
}

struct WeatherOverlayView: View {
    @ObservedObject var viewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if !viewModel.snapshot.error.isEmpty {
                Text(viewModel.snapshot.error)
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(WeatherConstants.targetNames, id: \.self) { name in
                        StationObsBlock(series: seriesFor(name: name), isLoading: viewModel.isLoading)
                    }
                }
                ForEach(WeatherConstants.targetNames, id: \.self) { name in
                    ForecastBlock(name: name,
                                  fc: viewModel.snapshot.forecasts[name],
                                  isLoading: viewModel.isLoading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.black)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView().controlSize(.small).colorScheme(.dark)
            }
            Text(statusText)
                .font(monoFont(weight: .regular))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.85))
            Button {
                viewModel.visible.toggle()
            } label: {
                Image(systemName: "eye.slash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.85))
        }
    }

    private var statusText: String {
        if !viewModel.snapshot.phase.isEmpty {
            return viewModel.snapshot.phase
        }
        if viewModel.snapshot.lastUpdated == .distantPast {
            return viewModel.isLoading ? "loading…" : ""
        }
        let f = DateFormatter()
        f.timeZone = WeatherConstants.timeZone
        f.dateFormat = "HH:mm"
        let stCount = viewModel.snapshot.stations.count
        let fcCount = viewModel.snapshot.forecasts.count
        return "updated \(f.string(from: viewModel.snapshot.lastUpdated)) · st=\(stCount) fc=\(fcCount)"
    }

    private func seriesFor(name: String) -> ObsSeries? {
        viewModel.snapshot.stations.first(where: { $0.station.name == name })
    }
}

private struct StationObsBlock: View {
    let series: ObsSeries?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(series?.station.name ?? "—")
                .font(monoFont())
                .foregroundColor(.white)

            if let series, !series.rows.isEmpty {
                content(series: series)
            } else {
                Text(isLoading ? "Loading…" : "No data")
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(height: cellH * 5)
            }
        }
    }

    @ViewBuilder
    private func content(series: ObsSeries) -> some View {
                let slotKeys = obsSlotKeys(rows: series.rows, count: 18)
                let rowBySlot = obsRowBySlot(rows: series.rows)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        timeHeaderRow(slotKeys: slotKeys)
                        kRow(label: "Wind (kn)", slotKeys: slotKeys) { sk in
                            let r = rowBySlot[sk].flatMap { series.rows[safe: $0] }
                            return msToKn(r?.fsMs)
                        }
                        kRow(label: "Gust (kn)", slotKeys: slotKeys) { sk in
                            let r = rowBySlot[sk].flatMap { series.rows[safe: $0] }
                            return msToKn(r?.fxMs)
                        }
                        dirRow(label: "Dir mean", slotKeys: slotKeys) { sk in
                            rowBySlot[sk].flatMap { series.rows[safe: $0] }?.fsdDeg
                        }
                        dirRow(label: "Dir gust", slotKeys: slotKeys) { sk in
                            rowBySlot[sk].flatMap { series.rows[safe: $0] }?.fxdDeg
                        }
                        if series.hasTemp {
                            tempRow(label: "Temp (°C)", slotKeys: slotKeys) { sk in
                                rowBySlot[sk].flatMap { series.rows[safe: $0] }?.taC
                            }
                        }
                    }
                }
    }

    @ViewBuilder
    private func timeHeaderRow(slotKeys: [String]) -> some View {
        HStack(spacing: 0) {
            Text(" ")
                .font(monoFont())
                .frame(width: labelW, height: cellH, alignment: .leading)
            ForEach(slotKeys, id: \.self) { sk in
                Text(formatHM(sk))
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: timeColW, height: cellH)
            }
        }
    }

    @ViewBuilder
    private func kRow(label: String, slotKeys: [String], value: @escaping (String) -> Double?) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            ForEach(slotKeys, id: \.self) { sk in
                if let kn = value(sk) {
                    let style = beaufortStyleKn(kn)
                    Text("\(Int(round(kn)))")
                        .font(monoFont())
                        .foregroundColor(style.fg)
                        .frame(width: timeColW, height: cellH)
                        .background(style.bg)
                } else {
                    Text("—")
                        .font(monoFont(weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: timeColW, height: cellH)
                }
            }
        }
    }

    @ViewBuilder
    private func dirRow(label: String, slotKeys: [String], value: @escaping (String) -> Double?) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            ForEach(slotKeys, id: \.self) { sk in
                let arrow = directionArrow(degFrom: value(sk))
                Text(arrow)
                    .font(monoFont())
                    .foregroundColor(Color(rgbHex: 0xf2f6fa))
                    .frame(width: timeColW, height: cellH)
                    .background(Color(rgbHex: 0x2a3238))
            }
        }
    }

    @ViewBuilder
    private func tempRow(label: String, slotKeys: [String], value: @escaping (String) -> Double?) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            ForEach(slotKeys, id: \.self) { sk in
                if let t = value(sk), t > -900 {
                    let style = tempStyleC(t)
                    Text("\(Int(round(t)))")
                        .font(monoFont())
                        .foregroundColor(style.fg)
                        .frame(width: timeColW, height: cellH)
                        .background(style.bg)
                } else {
                    Text("—")
                        .font(monoFont(weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: timeColW, height: cellH)
                }
            }
        }
    }
}

private struct ForecastBlock: View {
    let name: String
    let fc: ForecastSeries?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(name) — hourly")
                .font(monoFont())
                .foregroundColor(.white)
            if let fc, !fc.error.isEmpty {
                Text(fc.error)
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.red)
                    .frame(height: cellH * 5)
            } else if fc == nil || (fc?.windKn.isEmpty ?? true) {
                Text(isLoading ? "Loading…" : "No forecast")
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(height: cellH * 5)
            } else if let fc {
                let limit = min(24, min(fc.windKn.count, fc.gustKn.count))
                let hours = Array(fc.hourLabels.prefix(limit))
                let winds = Array(fc.windKn.prefix(limit))
                let gusts = Array(fc.gustKn.prefix(limit))
                let vmax = max(winds.max() ?? 1, gusts.max() ?? 1, 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        BarRow(label: "Wind", values: winds, vmax: vmax)
                        BarRow(label: "Gust", values: gusts, vmax: vmax)
                        HStack(spacing: 0) {
                            Text(" ")
                                .font(monoFont())
                                .frame(width: 36, height: cellH, alignment: .leading)
                            ForEach(hours.indices, id: \.self) { idx in
                                let s = hours[idx].filter { $0.isNumber }.suffix(2)
                                Text(String(s))
                                    .font(monoFont(weight: .regular))
                                    .foregroundColor(.white.opacity(0.65))
                                    .frame(width: timeColW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct BarRow: View {
    let label: String
    let values: [Double]
    let vmax: Double
    private let height: Int = 5

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: 36, height: CGFloat(height) * cellH, alignment: .topLeading)
            ForEach(values.indices, id: \.self) { i in
                BarColumn(value: values[i], vmax: vmax, height: height)
            }
        }
    }
}

private struct BarColumn: View {
    let value: Double
    let vmax: Double
    let height: Int

    var body: some View {
        let style = beaufortStyleKn(value)
        let filled = filledRows()
        let topRow = height - filled
        VStack(spacing: 0) {
            ForEach(0..<height, id: \.self) { r in
                if r < topRow {
                    Color.clear.frame(width: timeColW, height: cellH)
                } else if r == topRow {
                    Text("\(Int(round(value)))")
                        .font(monoFont())
                        .foregroundColor(style.fg)
                        .frame(width: timeColW, height: cellH)
                        .background(style.bg)
                } else {
                    Color.clear
                        .frame(width: timeColW, height: cellH)
                        .background(style.bg)
                }
            }
        }
    }

    private func filledRows() -> Int {
        if value <= 0 || vmax <= 0 { return 0 }
        let n = Int(round((value / vmax) * Double(height)))
        return max(1, min(height, n))
    }
}

// MARK: - slot helpers

private func obsSlotKeys(rows: [ObsRow], count: Int) -> [String] {
    let cal = calendarBudapest()
    let now = Date()
    let endSlot: Date = {
        if let last = rows.last,
           let dt = parseRowTimeUTC(last.timeUTC) {
            return floorTo10Min(dt, cal: cal)
        }
        return floorTo10Min(now, cal: cal)
    }()

    var out: [String] = []
    var cur = endSlot
    let fmt = DateFormatter()
    fmt.timeZone = WeatherConstants.timeZone
    fmt.dateFormat = "yyyyMMddHHmm"
    for _ in 0..<count {
        out.append(fmt.string(from: cur))
        cur = cal.date(byAdding: .minute, value: -10, to: cur) ?? cur
    }
    return out.reversed()
}

private func obsRowBySlot(rows: [ObsRow]) -> [String: Int] {
    var result: [String: Int] = [:]
    let cal = calendarBudapest()
    let fmt = DateFormatter()
    fmt.timeZone = WeatherConstants.timeZone
    fmt.dateFormat = "yyyyMMddHHmm"
    for (i, row) in rows.enumerated() {
        guard let dt = parseRowTimeUTC(row.timeUTC) else { continue }
        let floored = floorTo10Min(dt, cal: cal)
        result[fmt.string(from: floored)] = i
    }
    return result
}

private func parseRowTimeUTC(_ s: String) -> Date? {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 12 else { return nil }
    let head = String(trimmed.prefix(12))
    let fmt = DateFormatter()
    fmt.timeZone = TimeZone(secondsFromGMT: 0)
    fmt.dateFormat = "yyyyMMddHHmm"
    return fmt.date(from: head)
}

private func floorTo10Min(_ date: Date, cal: Calendar) -> Date {
    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    var c = comps
    c.minute = ((comps.minute ?? 0) / 10) * 10
    c.second = 0
    return cal.date(from: c) ?? date
}

private func calendarBudapest() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = WeatherConstants.timeZone
    return cal
}

private func formatHM(_ slotKey: String) -> String {
    guard slotKey.count >= 12 else { return slotKey }
    let hh = slotKey.dropFirst(8).prefix(2)
    let mm = slotKey.dropFirst(10).prefix(2)
    return "\(hh):\(mm)"
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
