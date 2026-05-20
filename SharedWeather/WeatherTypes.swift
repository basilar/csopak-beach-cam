import Foundation

enum WeatherConstants {
    static let targetNames = ["Balatonfüred", "Balatonalmádi"]
    static let baseURL = "https://odp.met.hu/climate/observations_hungary"
    static let metaFiles = ["station_meta_auto.csv", "station_meta_auto_wind.csv"]
    static let windguruMicro = "https://micro.windguru.cz/"
    static let windguruModel = "aromehu"
    static let windguruModelLabel = "AROME-HU 2.5 km"
    static let msToKn = 1.9438444924384
    static let timeZone = TimeZone(identifier: "Europe/Budapest") ?? TimeZone(secondsFromGMT: 3600)!

    /// Windguru spots paired with each MET observation station. Keys match `targetNames`.
    static let windguruSpots: [String: WindguruSpot] = [
        "Balatonfüred": WindguruSpot(stationName: "Balatonfüred", id: 1239621, label: "Palóznaki Öböl", isCustom: true),
        "Balatonalmádi": WindguruSpot(stationName: "Balatonalmádi", id: 88366, label: "Zagykazetta", isCustom: false),
    ]
}

struct WindguruSpot: Hashable {
    let stationName: String
    let id: Int
    let label: String
    /// Custom (user-created) spots require a Windguru PRO account for AROME-HU.
    let isCustom: Bool
}

struct WeatherStation: Hashable {
    let name: String
    let id: Int
    let lat: Double
    let lon: Double
}

struct ObsRow {
    let timeUTC: String
    let fsMs: Double?
    let fxMs: Double?
    let fsdDeg: Double?
    let fxdDeg: Double?
    let taC: Double?
}

struct ObsSeries {
    var station: WeatherStation
    var rows: [ObsRow] = []
    var hasTemp: Bool = false
    var lastTime: String?
}

struct ForecastSeries {
    var hourLabels: [String] = []
    var windKn: [Double] = []
    var gustKn: [Double] = []
    var dirDeg: [Double?] = []
    var modelInfo: String = ""
    var spotLabel: String = ""
    var error: String = ""
}

struct WeatherSnapshot {
    var stations: [ObsSeries] = []
    var forecasts: [String: ForecastSeries] = [:]
    var lastUpdated: Date = .distantPast
    var error: String = ""
}
