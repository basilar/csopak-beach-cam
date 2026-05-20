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
                        StationObsBlock(series: seriesFor(name: name),
                                        isLoading: viewModel.isLoading,
                                        lastUpdated: viewModel.snapshot.lastUpdated)
                    }
                }
                #if os(tvOS)
                Spacer(minLength: 24)
                #endif
                ForEach(WeatherConstants.targetNames, id: \.self) { name in
                    ForecastBlock(name: name,
                                  fc: viewModel.snapshot.forecasts[name],
                                  isLoading: viewModel.isLoading,
                                  lastUpdated: viewModel.snapshot.lastUpdated)
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
            #if !os(tvOS)
            if viewModel.isLoading {
                ProgressView().controlSize(.small).colorScheme(.dark)
            }
            #endif
            Text(statusText)
                .font(monoFont(weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            #if os(macOS)
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
            #endif
        }
    }

    private var statusText: String {
        if !viewModel.phase.isEmpty {
            return viewModel.phase
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
    let lastUpdated: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let series, !series.rows.isEmpty {
                content(series: series)
            } else {
                Text(series?.station.name ?? "—")
                    .font(monoFont())
                    .foregroundColor(.white)
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

        HStack(alignment: .top, spacing: 0) {
            labelColumn(name: series.station.name, hasTemp: series.hasTemp)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        hourValuesRow(slotKeys: slotKeys)
                        minuteValuesRow(slotKeys: slotKeys)
                        kValuesRow(slotKeys: slotKeys) { sk in
                            let r = rowBySlot[sk].flatMap { series.rows[safe: $0] }
                            return msToKn(r?.fsMs)
                        }
                        kValuesRow(slotKeys: slotKeys) { sk in
                            let r = rowBySlot[sk].flatMap { series.rows[safe: $0] }
                            return msToKn(r?.fxMs)
                        }
                        dirValuesRow(slotKeys: slotKeys) { sk in
                            rowBySlot[sk].flatMap { series.rows[safe: $0] }?.fsdDeg
                        }
                        dirValuesRow(slotKeys: slotKeys) { sk in
                            rowBySlot[sk].flatMap { series.rows[safe: $0] }?.fxdDeg
                        }
                        if series.hasTemp {
                            tempValuesRow(slotKeys: slotKeys) { sk in
                                rowBySlot[sk].flatMap { series.rows[safe: $0] }?.taC
                            }
                        }
                    }
                }
                .onAppear { scrollToEnd(proxy: proxy, count: slotKeys.count) }
                .onChange(of: slotKeys) { _, newKeys in
                    scrollToEnd(proxy: proxy, count: newKeys.count)
                }
                .onChange(of: lastUpdated) { _, _ in
                    scrollToEnd(proxy: proxy, count: slotKeys.count)
                }
            }
        }
    }

    @ViewBuilder
    private func labelColumn(name: String, hasTemp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            Color.clear
                .frame(width: labelW, height: cellH)
            Text("Wind (kn)")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            Text("Gust (kn)")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            Text("Dir mean")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            Text("Dir gust")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelW, height: cellH, alignment: .leading)
            if hasTemp {
                Text("Temp (°C)")
                    .font(monoFont())
                    .foregroundColor(.white)
                    .frame(width: labelW, height: cellH, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func hourValuesRow(slotKeys: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(slotKeys.indices, id: \.self) { i in
                let cur = hourComponent(slotKeys[i])
                let prev = i > 0 ? hourComponent(slotKeys[i - 1]) : nil
                Text(cur != prev ? cur : "")
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: timeColW, height: cellH, alignment: .leading)
                    .id("col-\(i)")
            }
        }
    }

    @ViewBuilder
    private func minuteValuesRow(slotKeys: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(slotKeys, id: \.self) { sk in
                Text(minuteComponent(sk))
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: timeColW, height: cellH)
            }
        }
    }

    @ViewBuilder
    private func kValuesRow(slotKeys: [String], value: @escaping (String) -> Double?) -> some View {
        HStack(spacing: 0) {
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
    private func dirValuesRow(slotKeys: [String], value: @escaping (String) -> Double?) -> some View {
        HStack(spacing: 0) {
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
    private func tempValuesRow(slotKeys: [String], value: @escaping (String) -> Double?) -> some View {
        HStack(spacing: 0) {
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

    private func scrollToEnd(proxy: ScrollViewProxy, count: Int) {
        guard count > 0 else { return }
        let lastIdx = count - 1
        DispatchQueue.main.async {
            proxy.scrollTo("col-\(lastIdx)", anchor: .trailing)
        }
    }
}

private struct ForecastBlock: View {
    let name: String
    let fc: ForecastSeries?
    let isLoading: Bool
    let lastUpdated: Date

    private let barHeight: Int = 5
    private let labelColumnWidth: CGFloat = 36

    private var headerLabel: String {
        let spot = fc?.spotLabel.isEmpty == false ? fc!.spotLabel : name
        return "\(spot) — AROME-HU"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headerLabel)
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
                let dirs = Array(fc.dirDeg.prefix(limit))
                let vmax = max(winds.max() ?? 1, gusts.max() ?? 1, 1)

                HStack(alignment: .top, spacing: 0) {
                    labelColumn
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 1) {
                                valueRow(values: winds, vmax: vmax)
                                valueRow(values: gusts, vmax: vmax)
                                dirRow(dirs: dirs, count: hours.count)
                                hourRow(hours: hours)
                            }
                        }
                        .onAppear { scrollToStart(proxy: proxy, count: hours.count) }
                        .onChange(of: hours) { _, newHours in
                            scrollToStart(proxy: proxy, count: newHours.count)
                        }
                        .onChange(of: lastUpdated) { _, _ in
                            scrollToStart(proxy: proxy, count: hours.count)
                        }
                    }
                }
            }
        }
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Wind")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelColumnWidth, height: CGFloat(barHeight) * cellH, alignment: .topLeading)
            Text("Gust")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelColumnWidth, height: CGFloat(barHeight) * cellH, alignment: .topLeading)
            Text("Dir")
                .font(monoFont())
                .foregroundColor(.white)
                .frame(width: labelColumnWidth, height: cellH, alignment: .leading)
            Color.clear
                .frame(width: labelColumnWidth, height: cellH)
        }
    }

    @ViewBuilder
    private func valueRow(values: [Double], vmax: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(values.indices, id: \.self) { i in
                BarColumn(value: values[i], vmax: vmax, height: barHeight)
                    .id("col-\(i)")
            }
        }
    }

    @ViewBuilder
    private func dirRow(dirs: [Double?], count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let deg = i < dirs.count ? dirs[i] : nil
                Text(directionArrow(degFrom: deg))
                    .font(monoFont())
                    .foregroundColor(Color(rgbHex: 0xf2f6fa))
                    .frame(width: timeColW, height: cellH)
                    .background(Color(rgbHex: 0x2a3238))
            }
        }
    }

    @ViewBuilder
    private func hourRow(hours: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(hours.indices, id: \.self) { idx in
                let s = hours[idx].filter { $0.isNumber }.suffix(2)
                Text(String(s))
                    .font(monoFont(weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: timeColW, height: cellH)
            }
        }
    }

    private func scrollToStart(proxy: ScrollViewProxy, count: Int) {
        guard count > 0 else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("col-0", anchor: .leading)
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

private func hourComponent(_ slotKey: String) -> String {
    guard slotKey.count >= 12 else { return "" }
    return String(slotKey.dropFirst(8).prefix(2))
}

private func minuteComponent(_ slotKey: String) -> String {
    guard slotKey.count >= 12 else { return "" }
    return String(slotKey.dropFirst(10).prefix(2))
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
