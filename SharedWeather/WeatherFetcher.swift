import Foundation

enum WeatherFetcherError: Error {
    case noNowZip(stationId: Int)
    case badResponse
}

actor WeatherFetcher {
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.httpAdditionalHeaders = [
            "User-Agent": "CsopakBeachCamMac/1.0",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
        ]
        cfg.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: cfg)
    }

    func loadStations() async throws -> [WeatherStation] {
        let wanted = Set(WeatherConstants.targetNames)
        var best: [String: (id: Int, lat: Double, lon: Double, end: Int, start: Int)] = [:]

        for fname in WeatherConstants.metaFiles {
            let url = bustURL("\(WeatherConstants.baseURL)/meta/\(fname)")
            let data = try await get(url)
            guard let text = String(data: stripBOM(data), encoding: .utf8) else { continue }
            let lines = text.split(whereSeparator: { $0.isNewline })
            var headerSeen = false
            for line in lines {
                if !headerSeen { headerSeen = true; continue }
                let cols = splitCSVLine(String(line), delimiter: ";")
                guard cols.count >= 7,
                      let num = Int(cols[0].trimmingCharacters(in: .whitespaces)),
                      let lat = Double(cols[3].trimmingCharacters(in: .whitespaces)),
                      let lon = Double(cols[4].trimmingCharacters(in: .whitespaces))
                else { continue }
                let name = cols[6].trimmingCharacters(in: .whitespaces)
                guard wanted.contains(name) else { continue }
                let endK = parseMetaDate(cols[2])
                let startK = parseMetaDate(cols[1])
                if let cur = best[name] {
                    if (endK, startK) > (cur.end, cur.start) {
                        best[name] = (num, lat, lon, endK, startK)
                    }
                } else {
                    best[name] = (num, lat, lon, endK, startK)
                }
            }
        }

        return WeatherConstants.targetNames.compactMap { name in
            guard let v = best[name] else { return nil }
            return WeatherStation(name: name, id: v.id, lat: v.lat, lon: v.lon)
        }
    }

    func fetchObservations(for station: WeatherStation) async throws -> ObsSeries {
        guard let (sub, fname) = try await resolveNowZip(stationId: station.id) else {
            throw WeatherFetcherError.noNowZip(stationId: station.id)
        }
        let url = bustURL("\(WeatherConstants.baseURL)/\(sub)/\(fname)")
        let zipData = try await get(url)
        let csvBytes = try MiniZip.extractFirstEntry(from: zipData)
        guard let csv = String(data: csvBytes, encoding: .utf8) else {
            throw WeatherFetcherError.badResponse
        }
        let (header, rows) = parseHabpCSV(csv)
        let hasTemp = header.contains("ta")
        let idx: [String: Int] = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })

        var obs = ObsSeries(station: station)
        obs.hasTemp = hasTemp
        for cols in rows {
            func cell(_ key: String) -> String { idx[key].flatMap { $0 < cols.count ? cols[$0] : nil } ?? "" }
            obs.rows.append(ObsRow(
                timeUTC: cell("Time"),
                fsMs: floatCell(cell("fs")),
                fxMs: floatCell(cell("fx")),
                fsdDeg: floatCell(cell("fsd")),
                fxdDeg: floatCell(cell("fxd")),
                taC: hasTemp ? floatCell(cell("ta")) : nil
            ))
        }
        obs.lastTime = obs.rows.last?.timeUTC
        return obs
    }

    func fetchForecast(spot: WindguruSpot,
                       credentials: (user: String, password: String)?,
                       maxHours: Int = 48) async -> ForecastSeries {
        var components = URLComponents(string: WeatherConstants.windguruMicro)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "s", value: String(spot.id)),
            URLQueryItem(name: "m", value: WeatherConstants.windguruModel),
        ]
        if let creds = credentials {
            items.append(URLQueryItem(name: "u", value: creds.user))
            items.append(URLQueryItem(name: "p", value: creds.password))
        }
        components.queryItems = items
        guard let url = components.url else {
            return ForecastSeries(spotLabel: spot.label, error: "bad url")
        }
        do {
            let data = try await get(bustURL(url.absoluteString))
            guard let body = String(data: data, encoding: .utf8) else {
                return ForecastSeries(spotLabel: spot.label, error: "bad encoding")
            }
            return parseWindguruMicro(body, spot: spot, maxHours: maxHours)
        } catch {
            return ForecastSeries(spotLabel: spot.label, error: "\(error)")
        }
    }

    private func parseWindguruMicro(_ body: String, spot: WindguruSpot, maxHours: Int) -> ForecastSeries {
        let preStart = body.range(of: "<pre>")
        let preEnd = body.range(of: "</pre>")
        let pre: String
        if let s = preStart, let e = preEnd, s.upperBound < e.lowerBound {
            pre = String(body[s.upperBound..<e.lowerBound])
        } else {
            pre = body
        }

        var modelInfo = ""
        if let r = pre.range(of: #"AROME-HU[^\n]*"#, options: .regularExpression) {
            modelInfo = String(pre[r]).trimmingCharacters(in: .whitespaces)
        }

        if pre.contains("Wrong password") {
            return ForecastSeries(modelInfo: modelInfo, spotLabel: spot.label,
                                  error: "Windguru: wrong username or password")
        }
        if pre.contains("only available to Windguru PRO") {
            return ForecastSeries(modelInfo: modelInfo, spotLabel: spot.label,
                                  error: "AROME-HU on this spot needs Windguru PRO")
        }

        var labels: [String] = []
        var dates: [Date] = []
        var ws: [Double] = []
        var gs: [Double] = []
        var ds: [Double?] = []

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WeatherConstants.timeZone
        let anchor = anchorComponents(modelInfo: modelInfo, calendar: cal)
        var year = anchor.year
        var month = anchor.month
        var lastDay: Int? = nil
        let now = Date()
        let topOfHour = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: now)) ?? now
        let cutoff = cal.date(byAdding: .hour, value: -WeatherConstants.forecastPastHours, to: topOfHour) ?? topOfHour

        for raw in pre.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 5 else { continue }
            // Forecast row shape: "<weekday> <day>. <HH>h <wspd> <gust> <wdirN> <wdeg> ..."
            guard tokens[1].hasSuffix("."),
                  tokens[2].hasSuffix("h"),
                  let day = Int(tokens[1].dropLast()),
                  let hour = Int(tokens[2].dropLast()),
                  let wspd = Double(tokens[3]),
                  let gust = parseKnots(tokens[4], fallback: wspd)
            else { continue }

            if let prev = lastDay, day < prev {
                month += 1
                if month > 12 { month = 1; year += 1 }
            }
            lastDay = day

            var dc = DateComponents()
            dc.year = year
            dc.month = month
            dc.day = day
            dc.hour = hour
            dc.timeZone = WeatherConstants.timeZone
            guard let rowDate = cal.date(from: dc), rowDate >= cutoff else { continue }

            labels.append(String(format: "%02dh", hour))
            dates.append(rowDate)
            ws.append(wspd)
            gs.append(gust)
            ds.append(tokens.count >= 7 ? Double(tokens[6]) : nil)
            if ws.count >= maxHours { break }
        }

        if ws.isEmpty {
            return ForecastSeries(modelInfo: modelInfo, spotLabel: spot.label,
                                  error: "no forecast rows")
        }
        return ForecastSeries(hourLabels: labels, hourDates: dates, windKn: ws, gustKn: gs, dirDeg: ds,
                              modelInfo: modelInfo, spotLabel: spot.label)
    }

    private func anchorComponents(modelInfo: String, calendar: Calendar) -> (year: Int, month: Int) {
        if let r = modelInfo.range(of: #"init:\s*(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2})\s*UTC"#,
                                   options: .regularExpression) {
            let match = String(modelInfo[r])
            let scanner = Scanner(string: match)
            scanner.charactersToBeSkipped = CharacterSet(charactersIn: "init: -UTC\t")
            if let y = scanner.scanInt(), let m = scanner.scanInt(), let d = scanner.scanInt(), let h = scanner.scanInt() {
                var utcCal = Calendar(identifier: .gregorian)
                utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
                var dc = DateComponents()
                dc.year = y; dc.month = m; dc.day = d; dc.hour = h
                if let initUTC = utcCal.date(from: dc) {
                    let local = calendar.dateComponents([.year, .month], from: initUTC)
                    if let ly = local.year, let lm = local.month {
                        return (ly, lm)
                    }
                }
            }
        }
        let now = calendar.dateComponents([.year, .month], from: Date())
        return (now.year ?? 1970, now.month ?? 1)
    }

    private func parseKnots(_ token: String, fallback: Double) -> Double? {
        if token == "-" { return fallback }
        return Double(token)
    }

    // MARK: - helpers

    private func resolveNowZip(stationId: Int) async throws -> (String, String)? {
        let candidates = [
            ("10_minutes/now", "HABP_10M_\(stationId)_now.zip"),
            ("10_minutes_wind/now", "HABP_10MWIND_\(stationId)_now.zip"),
        ]
        for (sub, fname) in candidates {
            let url = bustURL("\(WeatherConstants.baseURL)/\(sub)/\(fname)")
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            do {
                let (_, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return (sub, fname)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw WeatherFetcherError.badResponse
        }
        return data
    }

    private func bustURL(_ s: String) -> URL {
        let bust = Int(Date().timeIntervalSince1970)
        let sep = s.contains("?") ? "&" : "?"
        return URL(string: "\(s)\(sep)_=\(bust)")!
    }

    private func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == bom {
            return data.subdata(in: 3..<data.count)
        }
        return data
    }

    private func parseMetaDate(_ s: String) -> Int {
        let digits = s.filter { $0.isNumber }
        if digits.count >= 8 {
            return Int(digits.prefix(8)) ?? 0
        }
        return 0
    }

    private func splitCSVLine(_ line: String, delimiter: Character) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        cur.append("\"")
                        i = line.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    cur.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == delimiter {
                    out.append(cur)
                    cur.removeAll(keepingCapacity: true)
                } else {
                    cur.append(c)
                }
            }
            i = line.index(after: i)
        }
        out.append(cur)
        return out
    }

    private func parseHabpCSV(_ text: String) -> (header: [String], rows: [[String]]) {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        var headerIdx: Int?
        var i = 0
        for ln in lines {
            if ln.hasPrefix("StationNumber;") {
                headerIdx = i
                break
            }
            i += 1
        }
        guard let h = headerIdx else { return ([], []) }
        let header = splitCSVLine(String(lines[h]), delimiter: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var rows: [[String]] = []
        for j in (h + 1)..<lines.count {
            let raw = String(lines[j])
            if raw.isEmpty || raw.hasPrefix("#") { continue }
            let parts = splitCSVLine(raw, delimiter: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count < 2 { continue }
            rows.append(parts)
        }
        return (header, rows)
    }

    private func floatCell(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "-999" { return nil }
        return Double(s)
    }
}
