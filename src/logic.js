// Ren logik utan webbläsar-API:er, så att den går att testa med node --test.

export const RUSH_LIMIT_MIN = 2; // under så här mycket marginal: spring
export const HURRY_LIMIT_MIN = 5; // under så här mycket marginal: raska på

export const AT_PLACE_METERS = 400; // så här nära en destination räknas du som framme

export function distanceMeters(a, b) {
  const rad = (deg) => (deg * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

// Riktning från a till b i grader medurs från norr.
export function bearingDegrees(a, b) {
  const rad = (deg) => (deg * Math.PI) / 180;
  const dLon = rad(b.lon - a.lon);
  const y = Math.sin(dLon) * Math.cos(rad(b.lat));
  const x = Math.cos(rad(a.lat)) * Math.sin(rad(b.lat))
    - Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(dLon);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

// Riktningen gångvägen tar härifrån, sedd en bit framåt så att små krökar inte vrider kartan.
export function routeBearing(position, coordinates, aheadMeters = 30) {
  const points = coordinates.map(([lon, lat]) => ({ lat, lon }));
  const distances = points.map((point) => distanceMeters(position, point));
  const nearest = distances.indexOf(Math.min(...distances));
  const ahead = points.slice(nearest).find((point) => distanceMeters(position, point) >= aheadMeters);
  return bearingDegrees(position, ahead ?? points.at(-1));
}

export function distanceText(meters) {
  if (meters < 1000) return `${Math.round(meters / 10) * 10} m`;
  return `${(meters / 1000).toFixed(1).replace('.', ',')} km`;
}

const TURNS = {
  left: 'Sväng vänster',
  right: 'Sväng höger',
  'slight left': 'Håll vänster',
  'slight right': 'Håll höger',
  'sharp left': 'Sväng skarpt vänster',
  'sharp right': 'Sväng skarpt höger',
  uturn: 'Vänd om',
  straight: 'Gå rakt fram',
};

function stepText({ maneuver, name }) {
  if (maneuver.type === 'depart') return name ? `Börja gå på ${name}` : 'Börja gå';
  const turn = TURNS[maneuver.modifier] ?? 'Fortsätt';
  return name ? `${turn} in på ${name}` : turn;
}

// Gör om gångvägens steg till korta rader. Rakt fram på samma gata är inget att berätta,
// så de stegen läggs ihop med raden före.
export function walkSteps(steps, stationName) {
  const rows = [];
  for (const step of steps) {
    if (step.maneuver.type === 'arrive') continue;
    const last = rows.at(-1);
    if (last && step.maneuver.modifier === 'straight') {
      last.meters += step.distance;
    } else {
      rows.push({ text: stepText(step), meters: step.distance });
    }
  }
  return [
    ...rows.filter((row) => row.meters >= 1).map(({ text, meters }) => ({ text, distance: distanceText(meters) })),
    { text: `Framme vid ${stationName}`, distance: '' },
  ];
}

export function nearestStations(stations, position, count = 1) {
  return [...stations]
    .sort((a, b) => distanceMeters(position, a) - distanceMeters(position, b))
    .slice(0, count);
}

// Trafikslag i SL:s reseplanerare: hur linjen skrivs och vad avgången kallas i löpande text.
const MODES = {
  0: { line: 'Pendeltåg', noun: 'pendeltåget' },
  2: { line: 'Linje', noun: 'tåget' },
  4: { line: 'Spårvagn', noun: 'spårvagnen' },
  5: { line: 'Buss', noun: 'bussen' },
  9: { line: 'Båt', noun: 'båten' },
};
const OTHER_MODE = { line: 'Linje', noun: 'avgången' };
const WALK_CLASSES = new Set([99, 100]);

const isWalk = (leg) => WALK_CLASSES.has(leg.transportation?.product?.class);
const legTime = (point, kind) => new Date(point[`${kind}TimeEstimated`] ?? point[`${kind}TimePlanned`]);
const stopName = (point) => point.parent?.disassembledName ?? point.disassembledName ?? point.name?.replace(/, Stockholm$/, '');
const cancelled = (leg) => (leg.realtimeStatus ?? []).some((status) => status.includes('CANCELLED'));

// En resa från SL:s reseplanerare, kortad till det appen behöver. Du ska gå när första
// delen börjar, och första fordonet är det som visas stort. Inställda resor och resor
// utan fordon räknas inte.
export function parseJourney(journey) {
  const { legs } = journey;
  const ride = legs.findIndex((leg) => !isWalk(leg));
  if (ride < 0 || legs.some(cancelled)) return null;
  const board = legs[ride];
  const { transportation, origin } = board;
  const [lat, lon] = origin.parent?.coord ?? origin.coord;
  const leaveAt = legTime(legs[0].origin, 'departure');
  const time = legTime(origin, 'departure');
  const mode = transportation.product.class;
  return {
    key: `${transportation.id}|${origin.departureTimePlanned}`,
    leaveAt,
    time,
    arrival: legTime(legs.at(-1).destination, 'arrival'),
    mode,
    line: transportation.disassembledName ?? transportation.number ?? '',
    towards: transportation.destination?.name ?? '',
    stop: { name: stopName(origin), lat, lon },
    walkMinutes: (time - leaveAt) / 60000,
    walkMeters: legs.slice(0, ride).reduce((sum, leg) => sum + (leg.distance ?? 0), 0),
    transfers: legs.slice(ride + 1).filter((leg) => !isWalk(leg)).map((leg) => stopName(leg.origin)),
  };
}

// Resorna med marginal och färg. Samma avgång kan komma flera gånger, den räknas en gång.
export function buildTrips(journeys, now) {
  const seen = new Set();
  return journeys
    .map(parseJourney)
    .filter((trip) => trip && !seen.has(trip.key) && seen.add(trip.key))
    .map((trip) => {
      const slackMinutes = (trip.leaveAt - now) / 60000;
      return { ...trip, slackMinutes, status: classify(slackMinutes) };
    })
    .sort((a, b) => a.leaveAt - b.leaveAt);
}

// Snabbast fram vinner bland resorna du hinner med. Kommer två fram samtidigt
// väljs den du kan gå senare till, och de andra visas som fler avgångar.
export function pickTrips(trips) {
  const open = trips.filter((trip) => trip.status !== 'missed');
  const next = open.reduce((best, trip) => (
    !best || trip.arrival < best.arrival || (+trip.arrival === +best.arrival && trip.leaveAt > best.leaveAt) ? trip : best
  ), null);
  return { next, later: open.filter((trip) => trip !== next) };
}

export function lineText({ mode, line, towards }) {
  return `${(MODES[mode] ?? OTHER_MODE).line} ${line} mot ${towards}`;
}

export function tripName(trip, label) {
  return `${stockholmClock.format(trip.time)}-${(MODES[trip.mode] ?? OTHER_MODE).noun} ${tripPhrase(label)}`;
}

export function routeText(trip, label) {
  const walk = trip.walkMinutes >= 0.5 && `${Math.round(trip.walkMinutes)} min gång`;
  const transfers = trip.transfers.map((stop) => `byte ${stop}`);
  return [walk, trip.stop.name, ...transfers, label].filter(Boolean).join(' → ');
}

// Destinationen du står vid, om du är nära någon.
export function placeAt(places, position, meters = AT_PLACE_METERS) {
  const near = places
    .filter((place) => Number.isFinite(place.lat))
    .map((place) => ({ place, distance: distanceMeters(position, place) }))
    .filter(({ distance }) => distance < meters)
    .sort((a, b) => a.distance - b.distance);
  return near[0]?.place.id ?? null;
}

export function classify(slackMinutes) {
  if (slackMinutes < 0) return 'missed';
  if (slackMinutes < RUSH_LIMIT_MIN) return 'rush';
  if (slackMinutes < HURRY_LIMIT_MIN) return 'hurry';
  return 'calm';
}

// Rösten, samma som i iOS-appen (Board.swift): som en kompis som kan tidtabellen.
// Rubriken är en egen mening. Siffran, raden under och avgångens namn läses ihop till en mening.
const HEADLINES = {
  calm: ['Gott om tid.', 'Ingen brådska.', 'Du hinner.', 'Luta dig tillbaka.', 'Häng kvar en stund.'],
  hurry: ['På med skorna.', 'Börja avrunda.', 'Samla ihop grejerna.', 'Dags att röra på sig.', 'Snart dags.'],
  rush: ['Spring!', 'Nu gäller det!', 'Raska steg!', 'Full fart!', 'Iväg med dig!'],
  missed: ['Den hinner du inte.', 'Släpp den.', 'Den får gå utan dig.', 'Det kommer fler.', 'Missad. Ingen fara.'],
};
// Bara på morgonen, när avgången går före tio.
const MORNING_HEADLINES = ['Kaffet hinner du.'];
// Raden under siffran: liten bokstav, ingen punkt, och den slutar där avgångens namn tar vid.
const CAPTIONS = {
  calm: ['tills du behöver gå mot', 'tills du ska gå mot', 'innan du behöver dra mot', 'kvar innan du ska gå mot'],
  hurry: ['tills du behöver gå mot', 'sen drar du mot', 'sen är det dags för', 'kvar innan du ska gå mot'],
  rush: ['så hinner du med', 'om du ska hinna med', 'för att hinna med'],
  missed: ['ta nästa efter'],
};
// Det stora ordet när det är bråttom. Aldrig "gå".
const RUSH_WORDS = ['Nu', 'Iväg', 'Kör'];
// Påminnelsen när det blir gult eller rött. {m} är minuter, {n} avgångens namn.
const HURRY_ALERTS = ['Gå om {m} min, så hinner du med {n}.', 'Om {m} min behöver du gå mot {n}.',
  'Skorna på. Om {m} min går du mot {n}.', 'Snart dags: {n} vill ha dig om {m} min.'];
const RUSH_ALERTS = ['Spring nu, så hinner du med {n}.', 'Iväg nu om du ska hinna med {n}.',
  'Nu kör vi. {n} väntar inte.', 'Full fart, så hinner du med {n}.'];

// Småord som får finnas i både rubriken och raden under.
const SMALL_WORDS = new Set(['du', 'att', 'så', 'med', 'om', 'på', 'i', 'en', 'det', 'är',
  'för', 'mot', 'till', 'efter', 'sen', 'vi', 'dig']);
export const words = (text) => new Set(text.toLowerCase().split(/[^\p{L}]+/u).filter((w) => w && !SMALL_WORDS.has(w)));
const sharesWord = (a, b) => [...words(a)].some((w) => words(b).has(w));

// Samma avgång ger alltid samma ord, olika avgångar blandar. Samma räkning som i appen,
// så att webben och telefonen säger samma sak om samma avgång.
const MASK = (1n << 64n) - 1n;
function pick(list, time, salt, avoiding = null) {
  const fitting = avoiding ? list.filter((item) => !sharesWord(item, avoiding)) : list;
  const options = fitting.length ? fitting : list;
  let x = (BigInt.asUintN(64, BigInt(Math.trunc(time.getTime() / 60000))) + BigInt(salt) * 0x9E3779B97F4A7C15n) & MASK;
  x = ((x ^ (x >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
  x = ((x ^ (x >> 27n)) * 0x94D049BB133111EBn) & MASK;
  x ^= x >> 31n;
  return options[Number(x % BigInt(options.length))];
}

const stockholmHour = (date) => Number(new Intl.DateTimeFormat('sv-SE', {
  hour: 'numeric', hourCycle: 'h23', timeZone: 'Europe/Stockholm',
}).format(date));

export function headlines(status, time) {
  const list = HEADLINES[status] ?? [];
  return status === 'calm' && stockholmHour(time) < 10 ? [...list, ...MORNING_HEADLINES] : list;
}

// Orden följer avgången, så att de inte byts varje gång skärmen ritas om.
// Minuterna rundas nedåt: hellre en minut för tidigt än ett missat tåg.
export function departureMessage({ status, slackMinutes, time }) {
  const headline = pick(headlines(status, time), time, 1);
  const wait = status === 'rush' ? pick(RUSH_WORDS, time, 2, headline)
    : status === 'missed' ? '–' : `${Math.max(0, Math.floor(slackMinutes))} min`;
  const caption = pick(CAPTIONS[status] ?? [], time, 3, headline);
  return { headline, wait, caption };
}

const TRIP_PHRASES = { Hem: 'hem', Jobbet: 'till jobbet' };

export const tripPhrase = (label) => TRIP_PHRASES[label] ?? `till ${label}`;

// Knappar behövs bara när det finns ett val: inte för platsen du är på,
// och inte för den enda andra destinationen om appen redan valt den.
export function destinationChoices(places, activeId, hereId) {
  const choices = places.filter((place) => place.id !== hereId);
  return choices.length === 1 && choices[0].id === activeId ? [] : choices;
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

// Genvägen minns inget mellan körningarna, så under en resa får klockan avgöra:
// på förmiddagen är du på väg till jobbet, annars hem.
export function watchDestination({ home, work, position, now }) {
  const places = [{ id: 'home', label: 'Hem', ...home }];
  if (work) places.push({ id: 'work', label: 'Jobbet', weekdaysOnly: true, ...work });
  const hereId = placeAt(places, position);
  return { place: nextDestination(places, now.getHours() < 12 ? 'work' : 'home', hereId, now), hereId };
}

const stockholmClock = new Intl.DateTimeFormat('sv-SE', {
  hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Stockholm',
});

// Påminnelsen: en hel mening, som inte upprepar rubriken.
export function reminderText(trip, label) {
  const { headline } = departureMessage(trip);
  const minutes = Math.max(0, Math.floor(trip.slackMinutes));
  return pick(trip.status === 'rush' ? RUSH_ALERTS : HURRY_ALERTS, trip.time, 4, headline)
    .replace('{m}', minutes).replace('{n}', tripName(trip, label));
}

const URGENCY = { calm: 0, hurry: 1, rush: 2 };

// Ett steg i en påminnelse: notis varje gång läget blir allvarligare, klart när det är dags att gå.
// Blir tåget försenat går läget tillbaka, så att du får en ny notis när det skärps igen.
export function reminderStep({ key, status, label }, trips) {
  const train = trips.find((candidate) => candidate.key === key);
  if (!train) return { status, done: true, text: 'Hittar inte din avgång längre. Kolla läget i appen.' };
  if (train.status === 'missed') return { status, done: true };
  const text = URGENCY[train.status] > URGENCY[status] ? reminderText(train, label) : null;
  return { status: train.status, done: Boolean(text) && train.status === 'rush', text };
}

const WATCH_DOTS = { calm: '🟢', hurry: '🟡', rush: '🔴' };

// Kort svar för klockan: färg och besked först, sedan tid och rutt.
export function watchSummary({ place, atPlace, trips }) {
  if (atPlace) return `🏠 Du är redan vid ${place.label}`;
  const { next } = pickTrips(trips);
  if (!next) return `Hittar ingen resa du hinner med just nu\n${place.label}`;
  return [
    `${WATCH_DOTS[next.status]} ${departureMessage(next).headline}`,
    `${stockholmClock.format(next.time)} ${lineText(next)} från ${next.stop.name}`,
    `Gå senast ${stockholmClock.format(next.leaveAt)}, ${Math.max(1, Math.round(next.walkMinutes))} min gång`,
    routeText(next, place.label),
  ].join('\n');
}

// Bara vardagar: appen föreslår inte destinationen på helgen, men du kan fortfarande välja den själv.
export function isAvailable(place, now) {
  return !place.weekdaysOnly || ![0, 6].includes(now.getDay());
}

// När du är framme blir nästa destination aktiv, så Hem ger Jobbet och tvärtom.
// Annars ligger valet kvar, så att Jobbet inte hoppar tillbaka till Hem under resan.
// `hereId` är destinationen du står vid, `chosenId` det du själv valt, som gäller tills du är framme.
export function nextDestination(places, activeId, hereId, now, chosenId = null) {
  const active = places.find((place) => place.id === activeId) ?? places[0];
  const open = (place) => isAvailable(place, now);
  if (active.id !== hereId && (open(active) || active.id === chosenId)) return active;
  const index = places.indexOf(active);
  const others = [...places.slice(index + 1), ...places.slice(0, index)];
  return others.find((place) => place.id !== hereId && open(place))
    ?? [active, ...others].find((place) => place.id === hereId && open(place))
    ?? active;
}
