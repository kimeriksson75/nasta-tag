import Foundation
@testable import NastaTagCore
import Testing

private let stockholm = Coordinate(lat: 59.33, lon: 18.06)
private let times = (0..<480).map { Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 180) }
private func hour(_ iso: String, _ temp: Double, symbol: Int, wind: Double = 3, thunder: Double = 0) -> WeatherHour {
    WeatherHour(time: ISO8601DateFormatter().date(from: iso)!, temperature: temp, windSpeed: wind, gust: wind * 1.5,
                thunderProbability: thunder, symbol: symbol)
}

@Test func readsSmhi() throws {
    let json = """
    {"timeSeries":[{"time":"2026-11-16T07:00:00Z","data":{"air_temperature":0.4,"wind_speed":4.1,"wind_speed_of_gust":8.0,
    "thunderstorm_probability":1,"symbol_code":22}},{"time":"2026-11-16T08:00:00Z","data":{"air_temperature":9999,"symbol_code":3}}]}
    """
    let hours = try parseSMHI(Data(json.utf8))
    #expect(hours.count == 1)
    #expect(hours[0].temperature == 0.4 && hours[0].symbol == 22 && hours[0].windSpeed == 4.1)
}

@Test func onlyWeatherWorthMentioning() {
    let at = ISO8601DateFormatter().date(from: "2026-11-16T06:40:00Z")!
    func w(_ hours: WeatherHour...) -> Weather? { weather(at: at, hours: hours, at: stockholm) }
    #expect(w(hour("2026-11-16T07:00:00Z", 6, symbol: 5)) == nil, "mulet och sex grader är inget att säga")
    #expect(w(hour("2026-11-16T07:00:00Z", 6, symbol: 19)) == .rain)
    #expect(w(hour("2026-11-16T07:00:00Z", 0.5, symbol: 19)) == .ice, "regn kring nollan blir halt")
    #expect(w(hour("2026-11-16T07:00:00Z", -1, symbol: 5), hour("2026-11-16T08:00:00Z", -1, symbol: 25)) == .ice)
    #expect(w(hour("2026-11-16T07:00:00Z", -6, symbol: 26)) == .snow)
    #expect(w(hour("2026-11-16T07:00:00Z", 14, symbol: 11)) == .thunder)
    #expect(w(hour("2026-11-16T07:00:00Z", -14, symbol: 1)) == .cold)
    #expect(w(hour("2026-11-16T07:00:00Z", 8, symbol: 3, wind: 12)) == .wind)
    #expect(w(hour("2026-11-16T07:00:00Z", 6, symbol: 1)) == nil, "07:40 i november är solen inte uppe")
    #expect(weather(at: at, hours: [], at: stockholm) == nil)
    #expect(w(hour("2026-11-16T15:00:00Z", 6, symbol: 19)) == nil, "för gammal eller för långt bort")
}

@Test func sunOnlyInDaylight() {
    let summerNoon = ISO8601DateFormatter().date(from: "2026-06-21T10:00:00Z")!
    let winterNight = ISO8601DateFormatter().date(from: "2026-12-21T22:00:00Z")!
    #expect(sunElevation(at: summerNoon, stockholm) > 50)
    #expect(sunElevation(at: winterNight, stockholm) < 0)
    #expect(weather(at: summerNoon, hours: [WeatherHour(time: summerNoon, temperature: 20, symbol: 1)], at: stockholm) == .sun)
}

@Test func weatherDressesYouWhenItIsSoon() {
    for time in times {
        for kind in Weather.allCases {
            let hurry = departureMessage(status: .hurry, minutes: 3, trainTime: time, weather: kind)
            #expect(Voice.weatherHeadlines[kind]!.contains(hurry.headline))
            #expect(hurry.title.hasPrefix(kind.emoji + " "))
            #expect(!Voice.sharesWord(hurry.headline, hurry.caption), "\(hurry.headline) / \(hurry.caption)")
            let calm = departureMessage(status: .calm, minutes: 9, trainTime: time, weather: kind)
            #expect(calm.headline == departureMessage(status: .calm, minutes: 9, trainTime: time).headline, "lugnt får bara emojin")
            #expect(calm.weather == kind)
            let rush = departureMessage(status: .rush, minutes: 0, trainTime: time, weather: kind)
            if kind == .ice { #expect(rush.headline == "Försiktigt, det är halt!") }
            else { #expect(Voice.headlines[.rush]!.contains(rush.headline)) }
            #expect(!Voice.words(rush.title).contains("gå"))
            #expect(departureMessage(status: .missed, minutes: 0, trainTime: time, weather: kind).weather == nil)
        }
    }
}

@Test func weatherWordsAreShortSentences() {
    for (kind, list) in Voice.weatherHeadlines.merging(Voice.weatherRushHeadlines, uniquingKeysWith: +) {
        #expect(!list.isEmpty, "\(kind)")
        for headline in list {
            #expect(headline.first?.isUppercase == true && (headline.hasSuffix(".") || headline.hasSuffix("!")), "\(headline)")
            #expect(headline.count <= 29, "ryms på låsskärmen: \(headline)")
            #expect(!headline.contains("i dag"), "\(headline)")
        }
    }
    #expect(Set(Weather.allCases.map(\.emoji)).count == Weather.allCases.count)
}

@Test func iceMakesTheWalkLonger() throws {
    let url = Bundle.module.url(forResource: "trips", withExtension: "json")!
    let all = try JSONDecoder().decode(JourneysResponse.self, from: Data(contentsOf: url)).journeys ?? []
    let now = try #require(parseJourney(all[0])).leaveAt.addingTimeInterval(-6 * 60)
    let normal = buildTrips(all, now: now)
    let icy = buildTrips(all, now: now, walkFactor: iceWalkFactor)
    for (a, b) in zip(normal, icy) {
        #expect(a.key == b.key && a.time == b.time, "samma avgång")
        #expect(abs(a.leaveAt.timeIntervalSince(b.leaveAt) - a.walkMinutes * (iceWalkFactor - 1) * 60) < 1, "gå tidigare")
        #expect(b.slackMinutes < a.slackMinutes)
    }
}
