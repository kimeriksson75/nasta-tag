import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { buildBoard, classify, nearestStations, planTrip, trainReaches } from '../src/logic.js';

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
