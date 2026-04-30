import Foundation
import SwiftUI

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var snapshot = WeatherSnapshot()
    @Published var visible: Bool = true
    @Published var isLoading: Bool = false

    private let fetcher = WeatherFetcher()
    private var pollTask: Task<Void, Never>?
    private var stations: [WeatherStation] = []

    func start(intervalSeconds: Double = 90) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        var snap = WeatherSnapshot()
        snap.phase = "loading meta…"
        self.snapshot = snap
        NSLog("[Weather] refresh start")
        do {
            if stations.isEmpty {
                stations = try await fetcher.loadStations()
                NSLog("[Weather] meta loaded, stations=\(stations.count)")
            }
            if stations.isEmpty {
                snap.error = "No stations resolved from MET.hu meta CSV"
                self.snapshot = snap
                return
            }
            for station in stations {
                snap.phase = "obs \(station.name)…"
                self.snapshot = snap
                do {
                    let obs = try await fetcher.fetchObservations(for: station)
                    NSLog("[Weather] obs \(station.name) rows=\(obs.rows.count) hasTemp=\(obs.hasTemp)")
                    snap.stations.append(obs)
                } catch {
                    NSLog("[Weather] obs \(station.name) FAILED: \(error)")
                    var empty = ObsSeries(station: station)
                    empty.lastTime = nil
                    snap.stations.append(empty)
                    if snap.error.isEmpty {
                        snap.error = "Obs \(station.name): \(error)"
                    }
                }
                snap.phase = "forecast \(station.name)…"
                self.snapshot = snap
                let fc = await fetcher.fetchForecast(lat: station.lat, lon: station.lon)
                NSLog("[Weather] forecast \(station.name) hours=\(fc.windKn.count) err=\(fc.error)")
                snap.forecasts[station.name] = fc
            }
            snap.lastUpdated = Date()
            snap.phase = ""
        } catch {
            NSLog("[Weather] refresh FAILED: \(error)")
            snap.error = "\(error)"
        }
        self.snapshot = snap
    }
}
