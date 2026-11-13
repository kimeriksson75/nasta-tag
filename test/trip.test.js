import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchUpcomingTrips } from '../src/trip.js';

// En resa där gången börjar `walk` minuter före avgången `at` (minuter från nu).
const now = new Date('2026-11-13T07:00:00Z');
const at = (min) => new Date(+now + min * 60000).toISOString();
function journey(departs, walk = 3) {
  const point = (time) => ({ name: 'Slussen', coord: [59.32, 18.07], departureTimePlanned: time, arrivalTimePlanned: time });
  return {
    legs: [
      { transportation: { product: { class: 100 } }, origin: point(at(departs - walk)), destination: point(at(departs)), distance: 200 },
      { transportation: { id: 'L1', disassembledName: '17', product: { class: 2 }, destination: { name: 'Åkeshov' } },
        origin: point(at(departs)), destination: point(at(departs + 10)) },
    ],
  };
}

test('frågar vidare när alla resor redan har gått', async () => {
  const asked = [];
  const answers = [[journey(-2), journey(0), journey(1)], [journey(4), journey(6), journey(8)]];
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => {
    asked.push(new URL(url).searchParams.get('itd_time'));
    return { ok: true, json: async () => ({ journeys: answers.shift() ?? [] }) };
  };
  try {
    const journeys = await fetchUpcomingTrips({ lat: 59.3, lon: 18.0 }, { lat: 59.31, lon: 18.05 }, now);
    assert.equal(journeys.length, 6);
    assert.equal(asked[0], null);
    assert.equal(asked[1], '0802'); // senaste avgången 08:01 Stockholmstid plus en minut
  } finally {
    globalThis.fetch = original;
  }
});
