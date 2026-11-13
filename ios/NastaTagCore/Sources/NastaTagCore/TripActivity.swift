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
        public var journey: Int?
        /// Hela minuter tills du ska gå. Appen uppdaterar dem varje minut medan du följer tåget.
        public var minutes: Int
        public init(status: Status, leaveBy: Date, trainTime: Date, line: String, towards: String, station: String,
                    journey: Int?, minutes: Int) {
            self.status = status
            self.leaveBy = leaveBy
            self.trainTime = trainTime
            self.line = line
            self.towards = towards
            self.station = station
            self.journey = journey
            self.minutes = minutes
        }
    }

    public var label: String
    public init(label: String) { self.label = label }
}
#endif
