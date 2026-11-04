// Ren logik utan webbläsar-API:er, så att den går att testa med node --test.

export const RUSH_LIMIT_MIN = 2; // under så här mycket marginal: spring
export const HURRY_LIMIT_MIN = 5; // under så här mycket marginal: raska på

const WALK_METERS_PER_MIN = 80;
const DETOUR_FACTOR = 1.3; // gångvägen är längre än fågelvägen
const GONE_STATES = new Set(['CANCELLED', 'PASSED', 'NOTCALLED', 'REPLACED']);

export function distanceMeters(a, b) {
  const rad = (deg) => (deg * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

export function nearestStations(stations, position, count = 1) {
  return [...stations]
    .sort((a, b) => distanceMeters(position, a) - distanceMeters(position, b))
    .slice(0, count);
}

export function estimateWalkMinutes(from, to) {
  return (distanceMeters(from, to) * DETOUR_FACTOR) / WALK_METERS_PER_MIN;
}

// Ett tåg från `from` mot slutstationen `destination` passerar `target` om
// target ligger efter from och senast vid destination på någon sträcka.
export function trainReaches(routes, from, destination, target) {
  return routes.some(({ stations }) => {
    const start = stations.indexOf(from);
    const end = stations.indexOf(destination);
    const stop = stations.indexOf(target);
    if (start < 0 || end < 0 || stop < 0 || start === stop) return false;
    return start < end ? start < stop && stop <= end : end <= stop && stop < start;
  });
}

function stopsBetween(routes, a, b) {
  const counts = routes
    .filter(({ stations }) => stations.includes(a) && stations.includes(b))
    .map(({ stations }) => Math.abs(stations.indexOf(a) - stations.indexOf(b)));
  return counts.length ? Math.min(...counts) : Infinity;
}

// Alla linjefärger möts vid T-Centralen, så ett byte räcker alltid.
export function planTrip(routes, from, home) {
  if (stopsBetween(routes, from, home) < Infinity) return { target: home, transfer: null };
  const names = [...new Set(routes.flatMap((r) => r.stations))];
  let best = null;
  let bestStops = Infinity;
  for (const name of names) {
    const stops = stopsBetween(routes, from, name) + stopsBetween(routes, name, home);
    if (stops < bestStops) {
      best = name;
      bestStops = stops;
    }
  }
  return { target: best, transfer: best };
}

export function classify(slackMinutes) {
  if (slackMinutes < 0) return 'missed';
  if (slackMinutes < RUSH_LIMIT_MIN) return 'rush';
  if (slackMinutes < HURRY_LIMIT_MIN) return 'hurry';
  return 'calm';
}

function isRunning(departure) {
  if (GONE_STATES.has(departure.state)) return false;
  return !departure.deviations?.some((d) => d.consequence === 'CANCELLED');
}

// Tåg mot målet, sorterade på tid, med marginal efter gångtiden.
export function buildBoard({ departures, routes, from, target, now, walkMinutes }) {
  return departures
    .filter((d) => isRunning(d) && trainReaches(routes, from, d.destination, target))
    .map((d) => {
      const time = new Date(d.expected ?? d.scheduled);
      const minutesLeft = (time - now) / 60000;
      const slackMinutes = minutesLeft - walkMinutes;
      return {
        time,
        minutesLeft,
        slackMinutes,
        leaveBy: new Date(time.getTime() - walkMinutes * 60000),
        status: classify(slackMinutes),
        line: d.line.designation,
        destination: d.destination,
      };
    })
    .filter((train) => train.minutesLeft > -0.5)
    .sort((a, b) => a.time - b.time);
}

const CITY_CENTRE = { lat: 59.3303, lon: 18.0586 };
const MAX_SUGGESTIONS = 5;

// Best match first; among equally good ones, the address closest to the city.
export function addressSuggestions(locations) {
  return locations
    .filter((location) => location.coord)
    .map((location) => {
      const [lat, lon] = location.coord;
      return {
        address: `${location.disassembledName}, ${location.parent?.name}`,
        lat,
        lon,
        quality: location.matchQuality ?? 0,
      };
    })
    .sort((a, b) => b.quality - a.quality
      || distanceMeters(a, CITY_CENTRE) - distanceMeters(b, CITY_CENTRE))
    .slice(0, MAX_SUGGESTIONS)
    .map(({ address, lat, lon }) => ({ address, lat, lon }));
}

const WATCH_VERDICTS = { calm: '🟢 Gott om tid', hurry: '🟡 Raska på', rush: '🔴 Spring' };

// Kort svar för klockan: färg och besked först, sedan tid och rutt.
export function watchSummary({ start, home, plan, board }) {
  if (start.station.name === home) return `🏠 Du är redan vid ${home}`;
  const next = board.find((train) => train.status !== 'missed');
  if (!next) return `Inga tåg du hinner med just nu\n${start.station.name} → ${home}`;
  const clock = new Intl.DateTimeFormat('sv-SE', {
    hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Stockholm',
  });
  const walk = Math.max(1, Math.round(start.walkMinutes));
  return [
    WATCH_VERDICTS[next.status],
    `${clock.format(next.time)} linje ${next.line} mot ${next.destination}`,
    `Gå senast ${clock.format(next.leaveBy)}, ${start.estimated ? 'ca ' : ''}${walk} min gång`,
    `${start.station.name} → ${home}${plan.transfer ? `, byt vid ${plan.transfer}` : ''}`,
  ].join('\n');
}

// Bara vardagar: appen föreslår inte destinationen på helgen, men du kan fortfarande välja den själv.
export function isAvailable(place, now) {
  return !place.weekdaysOnly || ![0, 6].includes(now.getDay());
}

// När du är framme blir nästa destination aktiv, så Hem ger Jobbet och tvärtom.
// Annars ligger valet kvar, så att Jobbet inte hoppar tillbaka till Hem under resan.
// `chosenId` är det du själv valt, det gäller tills du är framme.
export function nextDestination(places, activeId, stationName, now, chosenId = null) {
  const active = places.find((place) => place.id === activeId) ?? places[0];
  const open = (place) => isAvailable(place, now);
  if (active.station !== stationName && (open(active) || active.id === chosenId)) return active;
  const index = places.indexOf(active);
  const others = [...places.slice(index + 1), ...places.slice(0, index)];
  return others.find((place) => place.station !== stationName && open(place))
    ?? [active, ...others].find((place) => place.station === stationName && open(place))
    ?? active;
}
