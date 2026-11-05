import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { addressSuggestions, buildBoard, classify, departureMessage, destinationChoices, isAvailable, nearestStations, nextDestination, reminderStep, reminderText, tripPhrase, watchDestination, watchSummary, planTrip, trainReaches } from '../src/logic.js';

const { routes, stations } = JSON.parse(await readFile(new URL('../data/metro.json', import.meta.url)));
const now = new Date('2026-11-04T10:00:00');
const departure = (expected, destination, extra = {}) => ({
  expected, destination, state: 'EXPECTED', line: { designation: '19' }, deviations: [], ...extra,
});

test('tåget kl 10.03 hinns inte med 4 minuters gångväg', () => {
  const board = buildBoard({
    departures: [departure('2026-11-04T10:03:00', 'Hässelby strand'), departure('2026-11-04T10:10:00', 'Hässelby strand')],
    routes, from: 'Slussen', target: 'Odenplan', now, walkMinutes: 4,
  });
  assert.equal(board[0].status, 'missed');
  assert.equal(board[1].status, 'calm');
  assert.equal(board[1].leaveBy.getMinutes(), 6);
});

test('marginalen ger färgklass', () => {
  assert.equal(classify(-0.1), 'missed');
  assert.equal(classify(0), 'rush');
  assert.equal(classify(1.9), 'rush');
  assert.equal(classify(2), 'hurry');
  assert.equal(classify(4.9), 'hurry');
  assert.equal(classify(5), 'calm');
});

test('inställda tåg visas inte', () => {
  const board = buildBoard({
    departures: [
      departure('2026-11-04T10:05:00', 'Alvik', { state: 'CANCELLED' }),
      departure('2026-11-04T10:06:00', 'Alvik', { deviations: [{ consequence: 'CANCELLED' }] }),
      departure('2026-11-04T10:07:00', 'Alvik'),
    ],
    routes, from: 'Slussen', target: 'Odenplan', now, walkMinutes: 0,
  });
  assert.equal(board.length, 1);
  assert.equal(board[0].time.getMinutes(), 7);
});

test('riktning och grenar', () => {
  assert.ok(trainReaches(routes, 'Slussen', 'Alvik', 'Odenplan'));
  assert.ok(!trainReaches(routes, 'Slussen', 'Farsta strand', 'Odenplan'));
  assert.ok(trainReaches(routes, 'Slussen', 'Farsta strand', 'Farsta strand'));
  assert.ok(!trainReaches(routes, 'Slussen', 'Hagsätra', 'Farsta'));
  assert.ok(!trainReaches(routes, 'Slussen', 'Alvik', 'Brommaplan'), 'tåget vänder före hemstationen');
  assert.ok(trainReaches(routes, 'Farsta', 'Hässelby strand', 'Gullmarsplan'));
});

test('byte väljs när linjerna inte hänger ihop', () => {
  assert.deepEqual(planTrip(routes, 'Odenplan', 'Slussen'), { target: 'Slussen', transfer: null });
  assert.equal(planTrip(routes, 'Odenplan', 'Akalla').transfer, 'Fridhemsplan');
  assert.ok(['T-Centralen', 'Gamla stan', 'Slussen'].includes(planTrip(routes, 'Ropsten', 'Farsta').transfer));
});

test('röda grenar som inte delar sträcka kräver byte vid Liljeholmen eller Östermalmstorg', () => {
  assert.equal(planTrip(routes, 'Fruängen', 'Bredäng').transfer, 'Liljeholmen');
  assert.equal(planTrip(routes, 'Ropsten', 'Mörby centrum').transfer, 'Östermalmstorg');
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
  const start = { station: { name: 'Slussen' }, walkMinutes: 3, estimated: false };
  const time = new Date('2026-11-04T10:12:00+01:00');
  const train = {
    time, leaveBy: new Date(time - 180000), status: 'calm', line: '18', destination: 'Farsta strand',
  };
  const missed = { ...train, status: 'missed' };
  const text = watchSummary({
    start, home: 'Hökarängen', plan: { transfer: null }, board: [missed, train],
  });
  assert.equal(text, [
    '🟢 Gott om tid',
    '10:12 linje 18 mot Farsta strand',
    'Gå senast 10:09, 3 min gång',
    'Slussen → Hökarängen',
  ].join('\n'));
});

test('klocksvar: redan hemma och inga tåg', () => {
  const start = { station: { name: 'Hökarängen' }, walkMinutes: 1 };
  assert.equal(watchSummary({ start, home: 'Hökarängen', plan: {}, board: [] }), '🏠 Du är redan vid Hökarängen');
  assert.match(watchSummary({ start, home: 'Slussen', plan: {}, board: [] }), /^Inga tåg/);
});

test('destination: byter när du är framme, annars ligger valet kvar', () => {
  const hem = { id: 'h', station: 'Hökarängen' };
  const jobbet = { id: 'j', station: 'Odenplan' };
  const gymmet = { id: 'g', station: 'Odenplan' };
  const places = [hem, jobbet, gymmet];
  assert.equal(nextDestination(places, 'h', 'Hökarängen', now), jobbet);
  assert.equal(nextDestination(places, 'j', 'Odenplan', now), hem, 'hoppar över platser vid samma station');
  assert.equal(nextDestination(places, 'j', 'Slussen', now), jobbet, 'mitt under resan');
  assert.equal(nextDestination([hem], 'h', 'Hökarängen', now), hem, 'bara en destination');
  assert.equal(nextDestination(places, 'borta', 'Slussen', now), hem, 'okänt val');
});

test('klockan: hem och jobb utan minne', () => {
  const at = (date, stationName, work = 'Odenplan') => watchDestination({
    home: 'Hökarängen', work, stationName, now: new Date(date),
  });
  const morning = '2026-11-04T08:00:00';
  const evening = '2026-11-04T17:00:00';
  const saturday = '2026-11-07T09:00:00';
  assert.equal(at(morning, 'Hökarängen'), 'Odenplan');
  assert.equal(at(evening, 'Hökarängen'), 'Odenplan', 'hemma går resan alltid till jobbet på vardagar');
  assert.equal(at(morning, 'Odenplan'), 'Hökarängen');
  assert.equal(at(morning, 'Slussen'), 'Odenplan', 'på väg till jobbet');
  assert.equal(at(evening, 'Slussen'), 'Hökarängen', 'på väg hem');
  assert.equal(at(saturday, 'Hökarängen'), 'Hökarängen', 'lördag hemma');
  assert.equal(at(saturday, 'Slussen'), 'Hökarängen', 'lördag på stan');
  assert.equal(at(morning, 'Slussen', null), 'Hökarängen', 'äldre genväg utan jobb');
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
  const train = (status, slackMinutes) => ({ journey: 7, status, slackMinutes, time });
  const reminder = (status) => ({ journey: 7, status, label: 'Jobbet' });
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
  const train = (status) => ({ journey: 7, status, slackMinutes: 9, time });
  const reminder = (status) => ({ journey: 7, status, label: 'Hem' });
  const delayed = reminderStep(reminder('hurry'), [train('calm')]);
  assert.deepEqual([delayed.status, delayed.text, delayed.done], ['calm', null, false]);
  assert.deepEqual(reminderStep(reminder('hurry'), [train('missed')]), { status: 'hurry', done: true });
  const gone = reminderStep(reminder('calm'), [{ ...train('calm'), journey: 8 }]);
  assert.equal(gone.done, true);
  assert.match(gone.text, /Hittar inte/);
});

test('påminnelse: texten är en hel mening', () => {
  const time = new Date('2026-11-04T21:50:00');
  const text = reminderText({ status: 'hurry', slackMinutes: 3.2, time }, 'Hem');
  assert.doesNotMatch(text, /\n/);
  assert.match(text, /3 min .* 21:50-tåget hem$/);
});

test('knappar: bara när det finns något att välja', () => {
  const hem = { id: 'h', station: 'Hökarängen' };
  const jobbet = { id: 'j', station: 'Odenplan' };
  const gymmet = { id: 'g', station: 'Slussen' };
  assert.deepEqual(destinationChoices([hem, jobbet], 'j', 'Hökarängen'), [], 'hemma med bara jobbet kvar');
  assert.deepEqual(destinationChoices([hem, jobbet], 'h', 'Hökarängen'), [jobbet], 'helg hemma: jobbet går att välja');
  assert.deepEqual(destinationChoices([hem, jobbet], 'j', 'Medborgarplatsen'), [hem, jobbet], 'på stan');
  assert.deepEqual(destinationChoices([hem, jobbet, gymmet], 'j', 'Hökarängen'), [jobbet, gymmet]);
  assert.deepEqual(destinationChoices([hem], 'h', 'Slussen'), [], 'bara en destination');
  assert.deepEqual(destinationChoices([hem, jobbet], 'h', undefined), [], 'plats okänd');
});

test('destination: bara vardagar', () => {
  const saturday = new Date('2026-11-07T09:00:00');
  const hem = { id: 'h', station: 'Hökarängen' };
  const jobbet = { id: 'j', station: 'Odenplan', weekdaysOnly: true };
  const places = [hem, jobbet];
  assert.equal(isAvailable(jobbet, now), true);
  assert.equal(isAvailable(jobbet, saturday), false);
  assert.equal(nextDestination(places, 'h', 'Hökarängen', now), jobbet, 'onsdag hemma');
  assert.equal(nextDestination(places, 'h', 'Hökarängen', saturday), hem, 'lördag hemma: ingen resa till jobbet');
  assert.equal(nextDestination(places, 'j', 'Hökarängen', saturday), hem, 'lördag med Jobbet kvar från fredagen');
  assert.equal(nextDestination(places, 'j', 'Slussen', saturday), hem, 'lördag på stan: hem');
});

test('destination: det du själv valt gäller tills du är framme', () => {
  const saturday = new Date('2026-11-07T09:00:00');
  const hem = { id: 'h', station: 'Hökarängen' };
  const jobbet = { id: 'j', station: 'Odenplan', weekdaysOnly: true };
  const places = [hem, jobbet];
  assert.equal(nextDestination(places, 'j', 'Hökarängen', saturday, 'j'), jobbet, 'lördag, men du ska till jobbet');
  assert.equal(nextDestination(places, 'j', 'Slussen', saturday, 'j'), jobbet, 'på vägen');
  assert.equal(nextDestination(places, 'j', 'Odenplan', saturday, 'j'), hem, 'framme: hem är nästa');
});
