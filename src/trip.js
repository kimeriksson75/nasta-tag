// Hämtar resor från SL och gångvägen till första hållplatsen. Används av både webbappen och servern.
import { buildTrips } from './logic.js';

const TRIPS_URL = 'https://journeyplanner.integration.sl.se/v2/trips';
const WALK_URL = 'https://routing.openstreetmap.de/routed-foot/route/v1/foot';
const MAX_TRIPS = 3; // mer än så svarar SL inte med

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// AbortSignal.any och timeout saknas i äldre Safari, så vi avbryter med en vanlig timer.
export function abortAfter(ms, controller = new AbortController()) {
  setTimeout(() => controller.abort(), ms);
  return controller.signal;
}

const place = ({ lat, lon }) => `${lon.toFixed(5)}:${lat.toFixed(5)}:WGS84[dd.ddddd]`;
const stockholmParts = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Europe/Stockholm', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
});

// Resor härifrån till destinationen med alla trafikslag, med uppdaterade tider.
// Med `departAt` börjar listan vid den tiden i stället för nu.
export async function fetchTrips(from, to, departAt = null) {
  const params = new URLSearchParams({
    type_origin: 'coord',
    name_origin: place(from),
    type_destination: 'coord',
    name_destination: place(to),
    calc_number_of_trips: String(MAX_TRIPS),
  });
  if (departAt) {
    const part = Object.fromEntries(stockholmParts.formatToParts(departAt).map(({ type, value }) => [type, value]));
    params.set('itd_date', `${part.year}${part.month}${part.day}`);
    params.set('itd_time', `${part.hour}${part.minute}`);
  }
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`${TRIPS_URL}?${params}`, { signal: abortAfter(15000) });
    if (res.ok) return (await res.json()).journeys ?? [];
    // SL:s öppna API svarar ibland 429 på enstaka anrop; nästa brukar gå igenom.
    if (res.status !== 429 || attempt === 3) throw new Error(`SL svarade ${res.status}`);
    await sleep(1500 * (attempt + 1));
  }
}

async function fetchWalk(position, station, query) {
  const path = `${position.lon},${position.lat};${station.lon},${station.lat}`;
  const res = await fetch(`${WALK_URL}/${path}?${query}`, { signal: abortAfter(6000) });
  if (!res.ok) throw new Error(`Gångvägen svarade ${res.status}`);
  return (await res.json()).routes[0];
}

// Reseplaneraren låter gången till hållplatsen börja före den tid man frågar om, så när det är
// nära och tätt mellan avgångarna kan alla svar redan ha gått. Då frågar vi vidare från den
// senaste avgången tills det finns några att visa.
export async function fetchUpcomingTrips(from, to, now = new Date(), wanted = 3) {
  let all = await fetchTrips(from, to);
  for (let round = 0; round < 2; round++) {
    const trips = buildTrips(all, now);
    if (!trips.length || trips.filter((trip) => trip.status !== 'missed').length >= wanted) break;
    const latest = Math.max(...trips.map((trip) => +trip.time));
    all = all.concat(await fetchTrips(from, to, new Date(latest + 60000)));
  }
  return all;
}

export async function fetchWalkRoute(position, station) {
  const route = await fetchWalk(position, station, 'overview=full&geometries=geojson&steps=true');
  return {
    coordinates: route.geometry.coordinates,
    meters: route.distance,
    minutes: route.duration / 60,
    steps: route.legs[0].steps,
  };
}
