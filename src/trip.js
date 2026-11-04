// Hämtar avgångar och gångtid. Används av både webbappen och klocktjänsten.
import { estimateWalkMinutes, nearestStations } from './logic.js';

const SL_URL = 'https://transport.integration.sl.se/v1';
const WALK_URL = 'https://routing.openstreetmap.de/routed-foot/route/v1/foot';
const WALK_CANDIDATES = 3; // fågelvägen ljuger vid vatten, så jämför gångvägen till flera

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export async function fetchDepartures(siteId) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`${SL_URL}/sites/${siteId}/departures?transport=METRO`);
    if (res.ok) return (await res.json()).departures;
    // SL:s öppna API svarar ibland 429 på enstaka anrop; nästa brukar gå igenom.
    if (res.status !== 429 || attempt === 3) throw new Error(`SL svarade ${res.status}`);
    await sleep(1500 * (attempt + 1));
  }
}

async function fetchWalkMinutes(position, station) {
  const path = `${position.lon},${position.lat};${station.lon},${station.lat}`;
  const res = await fetch(`${WALK_URL}/${path}?overview=false`, { signal: AbortSignal.timeout(6000) });
  if (!res.ok) throw new Error(`Gångvägen svarade ${res.status}`);
  return (await res.json()).routes[0].duration / 60;
}

export async function findStart(stations, position) {
  const candidates = nearestStations(stations, position, WALK_CANDIDATES);
  const walks = await Promise.allSettled(candidates.map((s) => fetchWalkMinutes(position, s)));
  const measured = candidates
    .map((station, i) => ({ station, walkMinutes: walks[i].value, estimated: false }))
    .filter((c) => c.walkMinutes !== undefined)
    .sort((a, b) => a.walkMinutes - b.walkMinutes);
  if (measured.length) return measured[0];
  return { station: candidates[0], walkMinutes: estimateWalkMinutes(position, candidates[0]), estimated: true };
}
