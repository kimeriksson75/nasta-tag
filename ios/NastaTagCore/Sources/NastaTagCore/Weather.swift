import Foundation

// MARK: Kläder efter väder

/// Vädret när det är värt att nämna. Högst ett åt gången, i den här ordningen: det som är farligast först.
public enum Weather: String, Codable, Hashable, Sendable, CaseIterable {
    case ice, thunder, snow, rain, cold, wind, heat, sun

    public var emoji: String {
        switch self {
        case .ice: "🧊"
        case .thunder: "⛈️"
        case .snow: "🌨️"
        case .rain: "🌧️"
        case .cold: "🥶"
        case .wind: "💨"
        case .heat: "🥵"
        case .sun: "😎"
        }
    }

    /// Vad emojin betyder, för VoiceOver.
    public var label: String {
        switch self {
        case .ice: "Halt ute"
        case .thunder: "Åska"
        case .snow: "Snö"
        case .rain: "Regn"
        case .cold: "Sträng kyla"
        case .wind: "Hård vind"
        case .heat: "Varmt"
        case .sun: "Sol"
        }
    }
}

/// Gångtiden räknas så här mycket längre när det är halt, så att du inte behöver stressa på isen.
public let iceWalkFactor = 1.25

extension Voice {
    /// Rubriken när det är dags att klä på sig. Ersätter de vanliga orden när det är Snart.
    public static let weatherHeadlines: [Weather: [String]] = [
        .ice: ["Broddar på skorna.", "Halt ute, ta det lugnt.", "Skynda långsamt, det är halt."],
        .thunder: ["Paraplyet med, det åskar.", "Åskväder på gång."],
        .snow: ["Mössa och vantar på.", "Kängorna på, det snöar.", "Höga stövlar idag."],
        .rain: ["Paraplyet under armen.", "Regnjackan på.", "Glöm inte paraplyet."],
        .cold: ["Långkalsongerna på.", "Mössa, vantar, halsduk.", "Bylsa på dig ordentligt."],
        .wind: ["Håll i mössan.", "Dra upp dragkedjan."],
        .heat: ["Lätt klädd idag.", "Vattenflaskan med."],
        .sun: ["Mörka shades idag.", "Solglasögonen på."],
    ]
    /// När det är bråttom brådskar det mer än vädret. Bara halkan är värd att säga.
    public static let weatherRushHeadlines: [Weather: [String]] = [
        .ice: ["Försiktigt, det är halt!"],
    ]
}

// MARK: SMHI

/// En timme i SMHI:s prognos. Nederbörden och symbolen gäller timmen fram till `time`.
public struct WeatherHour: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var windSpeed: Double
    public var gust: Double
    public var thunderProbability: Double
    /// SMHI:s vädersymbol, 1–27.
    public var symbol: Int

    public init(time: Date, temperature: Double, windSpeed: Double = 0, gust: Double = 0,
                thunderProbability: Double = 0, symbol: Int) {
        self.time = time
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.gust = gust
        self.thunderProbability = thunderProbability
        self.symbol = symbol
    }

    var thunder: Bool { [11, 21].contains(symbol) || thunderProbability >= 30 }
    /// Snö eller snöblandat regn.
    var snowing: Bool { (12...17).contains(symbol) || (22...27).contains(symbol) }
    var raining: Bool { (8...10).contains(symbol) || (18...20).contains(symbol) }
    var clear: Bool { symbol == 1 || symbol == 2 }
}

/// SMHI:s öppna prognos för en punkt (snow1g). Ingen nyckel behövs.
public func smhiURL(_ point: Coordinate) -> URL {
    // Tre decimaler räcker, ungefär hundra meter. Mer än så behöver SMHI inte veta.
    let lat = String(format: "%.3f", point.lat), lon = String(format: "%.3f", point.lon)
    return URL(string: "https://opendata-download-metfcst.smhi.se/api/category/snow1g/version/1/geotype/point/lon/\(lon)/lat/\(lat)/data.json")!
}

public func parseSMHI(_ data: Data) throws -> [WeatherHour] {
    struct Response: Decodable {
        struct Entry: Decodable {
            let time: String
            let data: [String: Double]
        }
        let timeSeries: [Entry]
    }
    let formatter = ISO8601DateFormatter()
    return try JSONDecoder().decode(Response.self, from: data).timeSeries.compactMap { entry in
        guard let time = formatter.date(from: entry.time), let temperature = entry.data["air_temperature"],
              let symbol = entry.data["symbol_code"], temperature != 9999, symbol != 9999 else { return nil }
        func value(_ key: String) -> Double { entry.data[key].flatMap { $0 == 9999 ? nil : $0 } ?? 0 }
        return WeatherHour(time: time, temperature: temperature, windSpeed: value("wind_speed"),
                           gust: value("wind_speed_of_gust"), thunderProbability: value("thunderstorm_probability"),
                           symbol: Int(symbol))
    }
}

/// Vädret värt att nämna när du går, eller nil när det är som vanligt.
/// Halka: kring nollan och nederbörd inom ett par timmar, så att det hinner frysa på.
public func weather(at date: Date, hours: [WeatherHour], at point: Coordinate) -> Weather? {
    guard let hour = hours.first(where: { $0.time >= date }) ?? hours.last,
          abs(hour.time.timeIntervalSince(date)) < 3 * 3600 else { return nil }
    let around = hours.filter { abs($0.time.timeIntervalSince(date)) <= 3 * 3600 }
    let wet = around.contains { $0.snowing || $0.raining }
    if (-3...1.5).contains(hour.temperature) && wet { return .ice }
    if hour.thunder { return .thunder }
    if hour.snowing { return .snow }
    if hour.raining { return .rain }
    if hour.temperature < -10 { return .cold }
    if hour.windSpeed >= 10 || hour.gust >= 17 { return .wind }
    if hour.temperature >= 25 { return .heat }
    if hour.clear && sunElevation(at: date, point) > 10 { return .sun }
    return nil
}

/// Solens höjd över horisonten i grader, ungefär. Räcker för att veta om solen bländar.
public func sunElevation(at date: Date, _ point: Coordinate) -> Double {
    let days = date.timeIntervalSince1970 / 86400 - 10957.5 // dagar sedan 2000-01-01 12:00 UTC
    let meanLongitude = (280.46 + 0.9856474 * days).truncatingRemainder(dividingBy: 360)
    let anomaly = ((357.528 + 0.9856003 * days).truncatingRemainder(dividingBy: 360)) * .pi / 180
    let longitude = (meanLongitude + 1.915 * sin(anomaly) + 0.02 * sin(2 * anomaly)) * .pi / 180
    let obliquity = (23.439 - 0.0000004 * days) * .pi / 180
    let declination = asin(sin(obliquity) * sin(longitude))
    let rightAscension = atan2(cos(obliquity) * sin(longitude), cos(longitude))
    let sidereal = (280.46061837 + 360.98564736629 * days + point.lon).truncatingRemainder(dividingBy: 360) * .pi / 180
    let hourAngle = sidereal - rightAscension
    let lat = point.lat * .pi / 180
    let elevation = asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle))
    return elevation * 180 / .pi
}
