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

    func fetchForecast(lat: Double, lon: Double, maxHours: Int = 48) async -> ForecastSeries {
        var components = URLComponents(string: WeatherConstants.openMeteoForecast)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "timezone", value: "Europe/Budapest"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "forecast_days", value: "4"),
        ]
        guard let url = components.url else {
            return ForecastSeries(error: "bad url")
        }
        do {
            let data = try await get(url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hourly = obj["hourly"] as? [String: Any],
                  let times = hourly["time"] as? [String],
                  let winds = hourly["wind_speed_10m"] as? [Any] else {
                return ForecastSeries(error: "bad json")
            }
            let gusts = (hourly["wind_gusts_10m"] as? [Any]) ?? []

            let start = nextFullHourLocal()
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime]
            let local = DateFormatter()
            local.timeZone = WeatherConstants.timeZone
            local.dateFormat = "yyyy-MM-dd'T'HH:mm"

            var labels: [String] = []
            var ws: [Double] = []
            var gs: [Double] = []

            for (i, t) in times.enumerated() {
                guard i < winds.count else { break }
                guard let dt = local.date(from: t) ?? parser.date(from: t) else { continue }
                if dt < start { continue }
                let w = (winds[i] as? Double) ?? Double((winds[i] as? Int) ?? 0)
                let g: Double
                if i < gusts.count, let gv = gusts[i] as? Double {
                    g = gv
                } else if i < gusts.count, let gv = gusts[i] as? Int {
                    g = Double(gv)
                } else {
                    g = w
                }
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = WeatherConstants.timeZone
                let hr = cal.component(.hour, from: dt)
                labels.append(String(format: "%02dh", hr))
                ws.append(w)
                gs.append(g)
                if ws.count >= maxHours { break }
            }
            if ws.isEmpty {
                return ForecastSeries(error: "no hourly steps")
            }
            return ForecastSeries(hourLabels: labels, windKn: ws, gustKn: gs)
        } catch {
            return ForecastSeries(error: "\(error)")
        }
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

    private func nextFullHourLocal() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WeatherConstants.timeZone
        let now = Date()
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        let floored = cal.date(from: comps) ?? now
        return cal.date(byAdding: .hour, value: 1, to: floored) ?? floored
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
