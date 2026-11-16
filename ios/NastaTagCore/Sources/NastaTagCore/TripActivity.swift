#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Det Live Activity visar på låsskärmen och i Dynamic Island.
public struct TripAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: Status
        public var leaveBy: Date
        public var trainTime: Date
        public var line: String
        public var towards: String
        public var station: String
        /// Avgången som följs: fordonet och dess planerade tid.
        public var key: String
        /// Trafikslaget, så att låsskärmen kan säga bussen, tåget eller båten.
        public var mode: Int
        /// Hela minuter tills du ska gå. Appen uppdaterar dem varje minut medan du följer tåget.
        public var minutes: Int
        /// Hur mycket senare nästa avgång går, för Snooze-knappen. Nil när det inte finns någon.
        public var snoozeMinutes: Int?
        /// Om resan är en snoozad avgång, så att knappen kan ångra.
        public var snoozed: Bool?
        /// Avgången är missad: knappen struntar i resan, till exempel "Fuck it.".
        public var offerSkip: Bool?
        /// Låsskärmen frågar "Dra en rövare?" och väntar på Ja! eller Nej 🙁.
        public var askingSkip: Bool?
        /// Du har struntat i resan. Låsskärmen säger det en stund innan den försvinner.
        public var skipped: Bool?
        /// Vädret när du ska gå, om det är värt att nämna.
        public var weather: Weather?
        /// Du står vid hållplatsen och väntar: minuterna räknas till avgången.
        public var arrived: Bool?
        /// Avgången har gått med dig. Låsskärmen önskar trevlig resa innan den försvinner.
        public var boarded: Bool?
        public init(status: Status, leaveBy: Date, trainTime: Date, line: String, towards: String, station: String,
                    key: String, mode: Int, minutes: Int, snoozeMinutes: Int? = nil, snoozed: Bool = false,
                    offerSkip: Bool = false, askingSkip: Bool = false, skipped: Bool = false,
                    weather: Weather? = nil, arrived: Bool = false, boarded: Bool = false) {
            self.status = status
            self.leaveBy = leaveBy
            self.trainTime = trainTime
            self.line = line
            self.towards = towards
            self.station = station
            self.key = key
            self.mode = mode
            self.minutes = minutes
            self.snoozeMinutes = snoozeMinutes
            self.snoozed = snoozed
            self.offerSkip = offerSkip
            self.askingSkip = askingSkip
            self.skipped = skipped
            self.weather = weather
            self.arrived = arrived
            self.boarded = boarded
        }
    }

    public var label: String
    public init(label: String) { self.label = label }
}
#endif
