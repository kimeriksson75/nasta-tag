import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { addressSuggestions, bearingDegrees, buildTrips, classify, departureMessage, destinationChoices, distanceText, isAvailable, lineText, nearestStations, nextDestination, parseJourney, pickTrips, placeAt, routeBearing, routeText, tripName, walkSteps, reminderStep, reminderText, tripPhrase, watchDestination, watchSummary } from '../src/logic.js';

const { stations } = JSON.parse(await readFile(new URL('../data/metro.json', import.meta.url)));
const now = new Date('2026-11-04T10:00:00');

// Resor i samma form som SL:s reseplanerare skickar dem, med bara de fält appen läser.
const walk = (from, to, distance = 300) => ({
  distance, transportation: { product: { class: 100 } },
  origin: { departureTimePlanned: from }, destination: { arrivalTimePlanned: to },
});
const ride = (mode, line, towards, stop, from, to, extra = {}) => ({
  transportation: { id: `linje-${line}`, disassembledName: line, product: { class: mode }, destination: { name: towards } },
  origin: { parent: { disassembledName: stop, coord: [59.2633, 18.0821] }, departureTimePlanned: from },
  destination: { arrivalTimePlanned: to },
  ...extra,
});
const journey = (...legs) => ({ legs });
const at = (time) => `2026-11-04T${time}:00Z`;

test('marginalen ger färgklass', () => {
  assert.equal(classify(-0.1), 'missed');
  assert.equal(classify(0), 'rush');
  assert.equal(classify(1.9), 'rush');
  assert.equal(classify(2), 'hurry');
  assert.equal(classify(4.9), 'hurry');
  assert.equal(classify(5), 'calm');
});

test('resa: gå när första delen börjar, första fordonet visas', () => {
  const trip = parseJourney(journey(
    walk(at('09:58'), at('10:03'), 290),
    walk(at('10:03'), at('10:05'), 40),
    ride(2, '18', 'Alvik', 'Gubbängen', at('10:05'), at('10:19')),
    walk(at('10:19'), at('10:21')),
    ride(5, '442', 'Boo backe', 'Slussen (Stadsgården)', at('10:25'), at('10:35')),
    walk(at('10:35'), at('10:40')),
  ));
  assert.equal(trip.leaveAt.toISOString(), '2026-11-04T09:58:00.000Z');
  assert.equal(trip.walkMinutes, 7);
  assert.equal(trip.walkMeters, 330);
  assert.equal(trip.stop.name, 'Gubbängen');
  assert.deepEqual(trip.transfers, ['Slussen (Stadsgården)']);
  assert.equal(lineText(trip), 'Linje 18 mot Alvik');
  assert.equal(routeText(trip, 'Jobbet'), '7 min gång → Gubbängen → byte Slussen (Stadsgården) → Jobbet');
});

test('resa: uppdaterad tid går före tidtabellen, inställda och bara promenad räknas inte', () => {
  const late = ride(5, '143', 'Älvsjö', 'Lingvägen', at('10:05'), at('10:15'));
  late.origin.departureTimeEstimated = at('10:08');
  assert.equal(parseJourney(journey(late)).time.toISOString(), '2026-11-04T10:08:00.000Z');
  const gone = ride(5, '143', 'Älvsjö', 'Lingvägen', at('10:05'), at('10:15'), { realtimeStatus: ['TRIP_CANCELLED'] });
  assert.equal(parseJourney(journey(walk(at('10:00'), at('10:05')), gone)), null);
  assert.equal(parseJourney(journey(walk(at('10:00'), at('10:20')))), null);
});

test('trafikslag i text', () => {
  const trip = (mode, line) => parseJourney(journey(ride(mode, line, 'Ändhållplatsen', 'Hållplatsen', at('10:05'), at('10:15'))));
  assert.equal(lineText(trip(5, '143')), 'Buss 143 mot Ändhållplatsen');
  assert.equal(lineText(trip(0, '41')), 'Pendeltåg 41 mot Ändhållplatsen');
  assert.equal(lineText(trip(4, '7')), 'Spårvagn 7 mot Ändhållplatsen');
  assert.equal(lineText(trip(7, '901')), 'Linje 901 mot Ändhållplatsen', 'okänt trafikslag');
  assert.equal(tripName(trip(5, '143'), 'Hem'), '11:05-bussen hem');
  assert.equal(tripName(trip(2, '18'), 'Jobbet'), '11:05-tåget till jobbet');
});

test('snabbast fram vinner bland resorna du hinner med', () => {
  const now = new Date(at('10:00'));
  const trips = buildTrips([
    journey(walk(at('09:58'), at('10:02')), ride(2, '18', 'Alvik', 'Gubbängen', at('10:02'), at('10:30'))),
    journey(walk(at('10:03'), at('10:06')), ride(5, '143', 'Älvsjö', 'Lingvägen', at('10:06'), at('10:40'))),
    journey(walk(at('10:08'), at('10:12')), ride(2, '18', 'Alvik', 'Gubbängen', at('10:12'), at('10:35'))),
    journey(walk(at('10:08'), at('10:12')), ride(2, '18', 'Alvik', 'Gubbängen', at('10:12'), at('10:35'))),
  ], now);
  assert.equal(trips.length, 3, 'samma avgång räknas en gång');
  assert.deepEqual(trips.map((trip) => trip.status), ['missed', 'hurry', 'calm']);
  const { next, later } = pickTrips(trips);
  assert.equal(next.line, '18', 'bussen går först men kommer fram senare');
  assert.equal(next.slackMinutes, 8);
  assert.deepEqual(later.map((trip) => trip.line), ['143']);
});

test('framme: närmaste destination inom några hundra meter', () => {
  const places = [{ id: 'h', lat: 59.2645, lon: 18.079 }, { id: 'j', lat: 59.342, lon: 18.023 }, { id: 'gammal', station: 'Odenplan' }];
  assert.equal(placeAt(places, { lat: 59.2650, lon: 18.0800 }), 'h');
  assert.equal(placeAt(places, { lat: 59.30, lon: 18.05 }), null);
});

test('närmaste station', () => {
  assert.equal(nearestStations(stations, { lat: 59.3429, lon: 18.0491 })[0].name, 'Odenplan');
});

test('adressförslag: bästa träff först, sedan närmast stan', () => {
  const location = (disassembledName, city, coord, matchQuality) => (
    { disassembledName, parent: { name: city }, coord, matchQuality }
  );
  const places = addressSuggestions([
    location('Sveavägen 20', 'Botkyrka', [59.195585, 17.818165], 1000),
    location('Sveavägen 2', 'Stockholm', [59.33, 18.06], 900),
    location('Sveavägen 20', 'Stockholm', [59.33477, 18.064698], 1000),
  ]);
  assert.deepEqual(places.map((place) => place.address), [
    'Sveavägen 20, Stockholm', 'Sveavägen 20, Botkyrka', 'Sveavägen 2, Stockholm',
  ]);
  assert.deepEqual(places[0], { address: 'Sveavägen 20, Stockholm', lat: 59.33477, lon: 18.064698 });
});

test('klocksvar: besked, tid, gå senast och rutt', () => {
  const now = new Date(at('10:00'));
  const trips = buildTrips([
    journey(walk(at('09:58'), at('10:02')), ride(2, '18', 'Alvik', 'Gubbängen', at('10:02'), at('10:30'))),
    journey(walk(at('10:09'), at('10:12')), ride(2, '18', 'Alvik', 'Gubbängen', at('10:12'), at('10:40'))),
  ], now);
  assert.equal(watchSummary({ place: { label: 'Jobbet' }, atPlace: false, trips }), [
    '🟢 Gott om tid',
    '11:12 Linje 18 mot Alvik från Gubbängen',
    'Gå senast 11:09, 3 min gång',
    '3 min gång → Gubbängen → Jobbet',
  ].join('\n'));
});

test('klocksvar: redan hemma och ingen resa', () => {
  assert.equal(watchSummary({ place: { label: 'Hem' }, atPlace: true, trips: [] }), '🏠 Du är redan vid Hem');
  assert.match(watchSummary({ place: { label: 'Jobbet' }, atPlace: false, trips: [] }), /^Hittar ingen resa/);
});

test('destination: byter när du är framme, annars ligger valet kvar', () => {
  const hem = { id: 'h' };
  const jobbet = { id: 'j' };
  const gymmet = { id: 'g' };
  const places = [hem, jobbet, gymmet];
  assert.equal(nextDestination(places, 'h', 'h', now), jobbet);
  assert.equal(nextDestination(places, 'j', 'j', now), gymmet);
  assert.equal(nextDestination(places, 'j', null, now), jobbet, 'mitt under resan');
  assert.equal(nextDestination([hem], 'h', 'h', now), hem, 'bara en destination');
  assert.equal(nextDestination(places, 'borta', null, now), hem, 'okänt val');
});

test('klockan: hem och jobb utan minne', () => {
  const home = { lat: 59.2645, lon: 18.079 };
  const work = { lat: 59.3429, lon: 18.0491 };
  const city = { lat: 59.3195, lon: 18.0722 };
  const go = (date, position, hasWork = true) => watchDestination({
    home, work: hasWork ? work : null, position, now: new Date(date),
  }).place.label;
  const morning = '2026-11-04T08:00:00';
  const evening = '2026-11-04T17:00:00';
  const saturday = '2026-11-07T09:00:00';
  assert.equal(go(morning, home), 'Jobbet');
  assert.equal(go(evening, home), 'Jobbet', 'hemma går resan alltid till jobbet på vardagar');
  assert.equal(go(morning, work), 'Hem');
  assert.equal(go(morning, city), 'Jobbet', 'på väg till jobbet');
  assert.equal(go(evening, city), 'Hem', 'på väg hem');
  assert.equal(go(saturday, home), 'Hem', 'lördag hemma');
  assert.equal(go(saturday, city), 'Hem', 'lördag på stan');
  assert.equal(go(morning, city, false), 'Hem', 'äldre genväg utan jobb');
  assert.equal(watchDestination({ home, work, position: home, now: new Date(morning) }).hereId, 'home');
});

test('besked: minuter kvar rundas nedåt, bråttom blir nu', () => {
  const time = new Date('2026-11-04T21:51:00');
  assert.equal(departureMessage({ status: 'hurry', slackMinutes: 4.9, time }).wait, '4 min');
  assert.equal(departureMessage({ status: 'calm', slackMinutes: 12.2, time }).wait, '12 min');
  assert.equal(departureMessage({ status: 'rush', slackMinutes: 1.5, time }).wait, 'nu');
  assert.match(departureMessage({ status: 'hurry', slackMinutes: 3, time }).lead, /gå om$/i);
  assert.match(departureMessage({ status: 'rush', slackMinutes: 1, time }).lead, /gå$/i);
});

test('besked: orden ligger still för samma avgång och varierar mellan avgångar', () => {
  const at = (minute) => departureMessage({
    status: 'calm', slackMinutes: 9, time: new Date(2026, 10, 4, 21, minute),
  }).lead;
  assert.equal(at(51), at(51));
  assert.ok(new Set([50, 51, 52, 53].map(at)).size > 1);
});

test('resans mål i löpande text', () => {
  assert.equal(tripPhrase('Hem'), 'hem');
  assert.equal(tripPhrase('Jobbet'), 'till jobbet');
  assert.equal(tripPhrase('Gymmet'), 'till Gymmet');
});

test('påminnelse: notis när läget skärps, klar när det är dags att gå', () => {
  const time = new Date('2026-11-04T21:50:00');
  const train = (status, slackMinutes) => ({ key: 'k7', mode: 2, status, slackMinutes, time });
  const reminder = (status) => ({ key: 'k7', status, label: 'Jobbet' });
  const calm = reminderStep(reminder('calm'), [train('calm', 8)]);
  assert.deepEqual([calm.text, calm.done], [null, false], 'ingen notis när inget ändrats');
  const hurry = reminderStep(reminder('calm'), [train('hurry', 4.5)]);
  assert.match(hurry.text, /4 min .*21:50-tåget till jobbet$/);
  assert.equal(hurry.done, false);
  assert.equal(hurry.status, 'hurry');
  const rush = reminderStep(reminder('hurry'), [train('rush', 1.5)]);
  assert.match(rush.text, /nu .*21:50-tåget till jobbet$/);
  assert.equal(rush.done, true);
  const skip = reminderStep(reminder('calm'), [train('rush', 1)]);
  assert.equal(skip.done, true, 'grönt direkt till rött ger en notis');
});

test('påminnelse: försening, missat och försvunnet tåg', () => {
  const time = new Date('2026-11-04T21:50:00');
  const train = (status) => ({ key: 'k7', mode: 5, status, slackMinutes: 9, time });
  const reminder = (status) => ({ key: 'k7', status, label: 'Hem' });
  const delayed = reminderStep(reminder('hurry'), [train('calm')]);
  assert.deepEqual([delayed.status, delayed.text, delayed.done], ['calm', null, false]);
  assert.deepEqual(reminderStep(reminder('hurry'), [train('missed')]), { status: 'hurry', done: true });
  const gone = reminderStep(reminder('calm'), [{ ...train('calm'), key: 'k8' }]);
  assert.equal(gone.done, true);
  assert.match(gone.text, /Hittar inte/);
});

test('påminnelse: texten är en hel mening', () => {
  const time = new Date('2026-11-04T21:50:00');
  const text = reminderText({ status: 'hurry', slackMinutes: 3.2, time, mode: 5 }, 'Hem');
  assert.doesNotMatch(text, /\n/);
  assert.match(text, /3 min .* 21:50-bussen hem$/);
});

test('riktning och avstånd till stationen', () => {
  const from = { lat: 59.3, lon: 18.0 };
  const near = (value, expected) => assert.ok(Math.abs(value - expected) < 1, `${value} borde vara ${expected}`);
  near(bearingDegrees(from, { lat: 59.4, lon: 18.0 }), 0);
  near(bearingDegrees(from, { lat: 59.3, lon: 18.1 }), 90);
  near(bearingDegrees(from, { lat: 59.2, lon: 18.0 }), 180);
  near(bearingDegrees(from, { lat: 59.3, lon: 17.9 }), 270);
  assert.equal(distanceText(347), '350 m');
  assert.equal(distanceText(1240), '1,2 km');
});

test('kartan vrids efter gångvägen en bit framåt', () => {
  const position = { lat: 59.3, lon: 18 };
  const east = [[18, 59.3], [18.0001, 59.3], [18.002, 59.3]];
  assert.ok(Math.abs(routeBearing(position, east) - 90) < 1);
  const north = [[18, 59.3], [18, 59.31]];
  assert.ok(routeBearing(position, north) < 1);
  assert.ok(Math.abs(routeBearing(position, [[18, 59.3], [17.99999, 59.3]]) - 270) < 1);
});

test('gångvägen blir korta rader på svenska', () => {
  const step = (type, modifier, name, distance) => ({ maneuver: { type, modifier }, name, distance });
  const rows = walkSteps([
    step('depart', undefined, '', 2.5),
    step('turn', 'left', 'Karmstolsvägen', 51),
    step('continue', 'straight', 'Karmstolsvägen', 20),
    step('turn', 'right', '', 120.2),
    step('arrive', 'left', '', 0),
  ], 'Gubbängen');
  assert.deepEqual(rows, [
    { text: 'Börja gå', distance: '0 m' },
    { text: 'Sväng vänster in på Karmstolsvägen', distance: '70 m' },
    { text: 'Sväng höger', distance: '120 m' },
    { text: 'Framme vid Gubbängen', distance: '' },
  ]);
});

test('knappar: bara när det finns något att välja', () => {
  const hem = { id: 'h' };
  const jobbet = { id: 'j' };
  const gymmet = { id: 'g' };
  assert.deepEqual(destinationChoices([hem, jobbet], 'j', 'h'), [], 'hemma med bara jobbet kvar');
  assert.deepEqual(destinationChoices([hem, jobbet], 'h', 'h'), [jobbet], 'helg hemma: jobbet går att välja');
  assert.deepEqual(destinationChoices([hem, jobbet], 'j', null), [hem, jobbet], 'på stan');
  assert.deepEqual(destinationChoices([hem, jobbet, gymmet], 'j', 'h'), [jobbet, gymmet]);
  assert.deepEqual(destinationChoices([hem], 'h', null), [], 'bara en destination');
});

test('destination: bara vardagar', () => {
  const saturday = new Date('2026-11-07T09:00:00');
  const hem = { id: 'h' };
  const jobbet = { id: 'j', weekdaysOnly: true };
  const places = [hem, jobbet];
  assert.equal(isAvailable(jobbet, now), true);
  assert.equal(isAvailable(jobbet, saturday), false);
  assert.equal(nextDestination(places, 'h', 'h', now), jobbet, 'onsdag hemma');
  assert.equal(nextDestination(places, 'h', 'h', saturday), hem, 'lördag hemma: ingen resa till jobbet');
  assert.equal(nextDestination(places, 'j', 'h', saturday), hem, 'lördag med Jobbet kvar från fredagen');
  assert.equal(nextDestination(places, 'j', null, saturday), hem, 'lördag på stan: hem');
});

test('destination: det du själv valt gäller tills du är framme', () => {
  const saturday = new Date('2026-11-07T09:00:00');
  const hem = { id: 'h' };
  const jobbet = { id: 'j', weekdaysOnly: true };
  const places = [hem, jobbet];
  assert.equal(nextDestination(places, 'j', 'h', saturday, 'j'), jobbet, 'lördag, men du ska till jobbet');
  assert.equal(nextDestination(places, 'j', null, saturday, 'j'), jobbet, 'på vägen');
  assert.equal(nextDestination(places, 'j', 'j', saturday, 'j'), hem, 'framme: hem är nästa');
});
