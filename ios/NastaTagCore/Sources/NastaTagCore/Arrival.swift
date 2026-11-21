import Foundation

// Framme vid hållplatsen. En station är stor och GPS:en är osäker inne och under jord, så framme
// räknas generöst. När du är framme låser appen avgången du står och väntar på, i stället för att
// räkna om resan från perrongen och byta till ett annat tåg. Går tåget medan du står där
// räknar appen med att du åkte med.

/// Så här nära hållplatsen räknas du som framme, eller närmare om GPS:en säger att den är osäkrare än så.
public let atStopMeters = 75.0
/// Går du så här långt från hållplatsen innan avgången släpps låset och appen börjar om.
public let leftStopMeters = 250.0

/// Du är framme vid hållplatsen. `accuracy` är hur osäker positionen är, i meter.
public func isAtStop(_ position: Coordinate, _ stop: Stop, accuracy: Double = 0) -> Bool {
    distanceMeters(position, stop.coordinate) <= max(atStopMeters, min(accuracy, 100))
}

/// Gångvägen som är kvar. SL:s gångväg räknades från där resan hämtades, så den skalas med
/// fågelvägen nu, och siffran krymper medan du går i stället för att stå still mellan hämtningarna.
public func walkLeft(position: Coordinate, stop: Stop, walkMeters: Double, fetchedFrom: Coordinate?) -> Double {
    let straight = distanceMeters(position, stop.coordinate)
    guard walkMeters > 0, let fetchedFrom else { return straight }
    let then = distanceMeters(fetchedFrom, stop.coordinate)
    guard then > 1 else { return straight }
    return straight * min(2, max(1, walkMeters / then))
}

/// Resan när du står vid hållplatsen: ingen gångväg kvar, och tiden räknas till avgången.
/// Läget är lugnt ända till tåget går, du behöver ju inte springa någonstans.
public func arrivedTrip(_ trip: Trip, now: Date) -> Trip {
    var trip = trip
    trip.leaveAt = trip.time
    trip.walkMinutes = 0
    trip.walkMeters = 0
    trip.slackMinutes = trip.time.timeIntervalSince(now) / 60
    trip.status = trip.slackMinutes < 0 ? .missed : .calm
    return trip
}

/// Avgången att vänta på när du kommer fram: bland dem som går härifrån och inte har gått än,
/// den som är framme först.
/// `place` är platsen du står vid, om du är vid en av dina. Bor du granne med en busshållplats är du
/// hemma, inte framme vid bussen: då räknas du som framme först när du är tydligt närmare hållplatsen
/// än platsen. Annars låstes bussen utanför porten och Snooze försvann medan du var kvar inne.
public func tripAtStop(_ trips: [Trip], position: Coordinate, accuracy: Double = 0, now: Date, place: Coordinate? = nil) -> Trip? {
    pickTrips(trips.filter { trip in
        trip.time > now && isAtStop(position, trip.stop, accuracy: accuracy)
            && !isStillAt(place, position: position, stop: trip.stop)
    }.map { arrivedTrip($0, now: now) }).next
}

/// Så mycket närmare hållplatsen än platsen du måste vara, så att GPS:en inte hoppar fram och tillbaka.
public let leftPlaceMarginMeters = 30.0

/// Du är kvar vid platsen och inte vid hållplatsen intill.
public func isStillAt(_ place: Coordinate?, position: Coordinate, stop: Stop) -> Bool {
    guard let place else { return false }
    return distanceMeters(position, stop.coordinate) + leftPlaceMarginMeters >= distanceMeters(position, place)
}

/// Vad som händer med en låst avgång: den står kvar, du åkte med, eller du gick därifrån.
public enum StopOutcome: Equatable { case waiting, boarded, left }

public func stopOutcome(_ trip: Trip, position: Coordinate?, now: Date) -> StopOutcome {
    let away = position.map { distanceMeters($0, trip.stop.coordinate) > leftStopMeters } ?? false
    if now >= trip.time { return .boarded }
    // Långt bort strax före avgången: tåget gick lite tidigt, med dig.
    if away { return trip.time.timeIntervalSince(now) < 60 ? .boarded : .left }
    return .waiting
}

extension Voice {
    /// Rubriken när du står vid hållplatsen. Kortet under säger redan att du är där.
    public static let arrivedHeadlines = ["Snyggt, du hann.", "Framme i tid.", "Där satt den.", "Bara att vänta."]
    /// Raden under minuterna, som slutar där avgångens namn tar vid.
    public static let arrivedCaptions = ["kvar till", "att vänta på", "tills det är dags för"]
    /// När tåget har gått med dig.
    public static let boardedHeadlines = ["Trevlig resa.", "Luta dig tillbaka.", "Bra jobbat. Trevlig resa."]
}

/// Hela minuter tills avgången när du väntar, räknade uppåt. Noll under sista minuten.
public func minutesToDeparture(_ slackMinutes: Double) -> Int { slackMinutes < 1 ? 0 : Int(slackMinutes.rounded(.up)) }

/// Orden medan du väntar vid hållplatsen. Sista minuten står det "Strax går", aldrig 0 min.
public func arrivedMessage(minutes: Int, trainTime: Date) -> DepartureMessage {
    let headline = Voice.pick(Voice.arrivedHeadlines, seed: trainTime, salt: 20)
    let wait = minutes < 1 ? "Strax" : "\(minutes) min"
    let caption = minutes < 1 ? "går" : Voice.pick(Voice.arrivedCaptions, seed: trainTime, salt: 21, avoiding: headline)
    return DepartureMessage(headline: headline, wait: wait, caption: caption)
}

public func boardedHeadline(trainTime: Date, label: String? = nil) -> String {
    Voice.pick(withMoment(Voice.boardedHeadlines, Voice.momentBoarded(label: label, trainTime: trainTime)), seed: trainTime, salt: 22)
}

/// Orden ombord: trevlig resa, och när du är framme.
public func boardedMessage(trainTime: Date, arrival: Date?, label: String? = nil) -> DepartureMessage {
    DepartureMessage(headline: boardedHeadline(trainTime: trainTime, label: label),
                     wait: stockholmClock(arrival ?? trainTime), caption: "är du framme")
}
