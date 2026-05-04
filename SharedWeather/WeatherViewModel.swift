import Foundation
import SwiftUI

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var snapshot = WeatherSnapshot()
    @Published var visible: Bool = true
    @Published var isLoading: Bool = false
    @Published var phase: String = ""

    private let fetcher = WeatherFetcher()
    private let credentials = WindguruCredentialsStore.shared
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
        phase = snapshot.lastUpdated == .distantPast ? "loading meta…" : ""
        defer {
            isLoading = false
            phase = ""
        }
        NSLog("[Weather] refresh start")

        let previous = snapshot
        var next = WeatherSnapshot()
        next.lastUpdated = previous.lastUpdated

        do {
            if stations.isEmpty {
                stations = try await fetcher.loadStations()
                NSLog("[Weather] meta loaded, stations=\(stations.count)")
            }
            if stations.isEmpty {
                var failed = previous
                failed.error = "No stations resolved from MET.hu meta CSV"
                self.snapshot = failed
                return
            }
            let creds = credentials.currentCredentials()
            for station in stations {
                phase = "obs \(station.name)…"
                do {
                    let obs = try await fetcher.fetchObservations(for: station)
                    NSLog("[Weather] obs \(station.name) rows=\(obs.rows.count) hasTemp=\(obs.hasTemp)")
                    next.stations.append(obs)
                } catch {
                    NSLog("[Weather] obs \(station.name) FAILED: \(error)")
                    if let prev = previous.stations.first(where: { $0.station.name == station.name }),
                       !prev.rows.isEmpty {
                        next.stations.append(prev)
                    } else {
                        var empty = ObsSeries(station: station)
                        empty.lastTime = nil
                        next.stations.append(empty)
                    }
                    if next.error.isEmpty {
                        next.error = "Obs \(station.name): \(error)"
                    }
                }
                if let spot = WeatherConstants.windguruSpots[station.name] {
                    phase = "forecast \(spot.label)…"
                    let fc = await fetcher.fetchForecast(spot: spot, credentials: creds)
                    NSLog("[Weather] forecast \(spot.label) hours=\(fc.windKn.count) err=\(fc.error)")
                    if !fc.windKn.isEmpty {
                        next.forecasts[station.name] = fc
                    } else if let prev = previous.forecasts[station.name], !prev.windKn.isEmpty {
                        next.forecasts[station.name] = prev
                    } else {
                        next.forecasts[station.name] = fc
                    }
                }
            }
            next.lastUpdated = Date()
            self.snapshot = next
        } catch {
            NSLog("[Weather] refresh FAILED: \(error)")
            var failed = previous
            failed.error = "\(error)"
            self.snapshot = failed
        }
    }
}
