import Foundation

enum WeatherConstants {
    static let targetNames = ["Balatonfüred", "Balatonalmádi"]
    static let baseURL = "https://odp.met.hu/climate/observations_hungary"
    static let metaFiles = ["station_meta_auto.csv", "station_meta_auto_wind.csv"]
    static let openMeteoForecast = "https://api.open-meteo.com/v1/forecast"
    static let msToKn = 1.9438444924384
    static let timeZone = TimeZone(identifier: "Europe/Budapest") ?? TimeZone(secondsFromGMT: 3600)!
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
    var error: String = ""
}

struct WeatherSnapshot {
    var stations: [ObsSeries] = []
    var forecasts: [String: ForecastSeries] = [:]
    var lastUpdated: Date = .distantPast
    var error: String = ""
    var phase: String = ""
}
