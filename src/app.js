import {
  buildBoard, distanceMeters, estimateWalkMinutes, nearestStations, planTrip,
} from './logic.js';

const SL_URL = 'https://transport.integration.sl.se/v1';
const WALK_URL = 'https://routing.openstreetmap.de/routed-foot/route/v1/foot';
const GEOCODE_URL = 'https://photon.komoot.io/api/';
const STOCKHOLM_BBOX = '17.4,58.9,18.8,59.8';
const HOME_KEY = 'nasta-tag.home';
const REFRESH_MS = 30000;
const WALK_CANDIDATES = 3; // fågelvägen ljuger vid vatten, så jämför gångvägen till flera
const MOVED_METERS = 40;
const LATER_COUNT = 3;

const $ = (id) => document.getElementById(id);
const clock = new Intl.DateTimeFormat('sv-SE', { hour: '2-digit', minute: '2-digit' });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const state = {
  metro: null,
  home: JSON.parse(localStorage.getItem(HOME_KEY) ?? 'null'),
  position: null,
  walkedFrom: null,
  start: null, // { station, walkMinutes, estimated }
  plan: null,
  departures: null,
  fetchedAt: null,
  problem: null, // { text, retry }
};

function stationByName(name) {
  return state.metro.stations.find((s) => s.name === name);
}

async function fetchDepartures(siteId) {
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

async function findStart(position) {
  const candidates = nearestStations(state.metro.stations, position, WALK_CANDIDATES);
  const walks = await Promise.allSettled(candidates.map((s) => fetchWalkMinutes(position, s)));
  const measured = candidates
    .map((station, i) => ({ station, walkMinutes: walks[i].value, estimated: false }))
    .filter((c) => c.walkMinutes !== undefined)
    .sort((a, b) => a.walkMinutes - b.walkMinutes);
  if (measured.length) return measured[0];
  return { station: candidates[0], walkMinutes: estimateWalkMinutes(position, candidates[0]), estimated: true };
}

async function refreshDepartures() {
  if (!state.start || !state.home) return;
  const { station } = state.start;
  state.plan = planTrip(state.metro.routes, station.name, state.home.station);
  if (station.name === state.home.station) {
    state.departures = [];
    render();
    return;
  }
  try {
    const departures = await fetchDepartures(station.siteId);
    if (state.start?.station !== station) return;
    state.departures = departures;
    state.fetchedAt = new Date();
    state.problem = null;
  } catch {
    if (!state.departures) state.problem = { text: 'Kunde inte hämta avgångar från SL.', retry: true };
  }
  render();
}

async function onPosition({ coords }) {
  const position = { lat: coords.latitude, lon: coords.longitude };
  state.position = position;
  if (state.problem?.gps) state.problem = null;
  $('start-picker').hidden = true;
  if (state.walkedFrom && distanceMeters(state.walkedFrom, position) < MOVED_METERS) return;
  state.walkedFrom = position;
  const start = await findStart(position);
  const changed = start.station !== state.start?.station;
  state.start = start;
  if (changed) state.departures = null;
  await refreshDepartures();
}

function onPositionError() {
  if (state.position) return;
  state.problem = { text: 'Hittar inte din plats. Tillåt plats eller välj station här nedanför.', retry: true, gps: true };
  $('start-picker').hidden = false;
  render();
}

let watchId = null;
function startLocating() {
  if (watchId !== null) navigator.geolocation?.clearWatch(watchId);
  if (!navigator.geolocation) return onPositionError();
  watchId = navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true, maximumAge: 30000, timeout: 15000,
  });
}

function minutes(value) {
  return `${Math.max(1, Math.round(value))} min`;
}

function adviceFor(train, now) {
  if (train.status === 'rush') return train.slackMinutes < 1 ? 'Gå nu, marginalen är under en minut' : 'Gå nu';
  const wait = (train.leaveBy - now) / 60000;
  return `Gå senast ${clock.format(train.leaveBy)}, om ${minutes(wait)}`;
}

const VERDICTS = { calm: 'Gott om tid', hurry: 'Raska på', rush: 'Spring' };

function renderMessage(text, retry = false) {
  document.documentElement.dataset.status = 'idle';
  $('verdict').textContent = text;
  $('time').textContent = '';
  $('train').textContent = '';
  $('advice').textContent = '';
  $('missed').textContent = '';
  $('later').replaceChildren();
  $('retry').hidden = !retry;
}

function laterRow(train) {
  const row = document.createElement('li');
  const at = document.createElement('span');
  at.className = 'at';
  at.textContent = clock.format(train.time);
  const to = document.createElement('span');
  to.className = 'to';
  to.textContent = `${train.line} ${train.destination}`;
  const tag = document.createElement('span');
  tag.className = 'tag';
  tag.textContent = `gå ${clock.format(train.leaveBy)}`;
  row.append(at, to, tag);
  return row;
}

function render() {
  const { start, home, plan } = state;
  if (start) {
    const walk = `${start.estimated ? 'ca ' : ''}${minutes(start.walkMinutes)} gång`;
    const walkPart = start.walkMinutes > 0 ? ` · ${walk}` : '';
    $('route').textContent = `${start.station.name}${walkPart} → ${home?.station ?? ''}`;
  } else {
    $('route').textContent = home ? `Hem till ${home.station}` : '';
  }
  $('updated').textContent = state.fetchedAt ? `Uppdaterad ${clock.format(state.fetchedAt)}` : '';

  if (!home) return renderMessage('Börja med att spara din hemadress.');
  if (state.problem) return renderMessage(state.problem.text, state.problem.retry);
  if (!start) return renderMessage('Letar efter din plats …');
  if (start.station.name === home.station) return renderMessage('Du är redan vid din hemstation.');
  if (!state.departures) return renderMessage('Hämtar avgångar …');

  const now = new Date();
  const board = buildBoard({
    departures: state.departures,
    routes: state.metro.routes,
    from: start.station.name,
    target: plan.target,
    now,
    walkMinutes: start.walkMinutes,
  });
  const reachable = board.filter((t) => t.status !== 'missed');
  const missed = board.filter((t) => t.status === 'missed');
  const [next, ...later] = reachable;
  if (!next) return renderMessage('Inga tåg du hinner med inom den närmaste timmen.');

  document.documentElement.dataset.status = next.status;
  $('retry').hidden = true;
  $('verdict').textContent = VERDICTS[next.status];
  $('time').textContent = clock.format(next.time);
  const change = plan.transfer ? `, byt vid ${plan.transfer}` : '';
  $('train').textContent = `Linje ${next.line} mot ${next.destination}${change}`;
  $('advice').textContent = adviceFor(next, now);
  $('missed').textContent = missed.length
    ? `Du hinner inte ${missed.map((t) => clock.format(t.time)).join(', ')}`
    : '';
  $('later').replaceChildren(...later.slice(0, LATER_COUNT).map(laterRow));
}

function fillStationSelect(select, selected) {
  const names = state.metro.stations.map((s) => s.name).sort((a, b) => a.localeCompare(b, 'sv'));
  select.replaceChildren(...names.map((name) => new Option(name, name, false, name === selected)));
}

function placeLabel({ properties: p }) {
  const street = p.street ? `${p.street} ${p.housenumber ?? ''}`.trim() : p.name;
  const named = p.street && p.name && p.name !== p.street ? `${p.name}, ` : '';
  return `${named}${street}, ${p.city ?? p.district ?? p.county ?? ''}`.replace(/, $/, '');
}

let chosenPlace = null;

function choosePlace(feature, button) {
  const [lon, lat] = feature.geometry.coordinates;
  chosenPlace = { address: placeLabel(feature), lat, lon };
  for (const other of $('results').querySelectorAll('button')) other.setAttribute('aria-pressed', other === button);
  fillStationSelect($('home-station'), nearestStations(state.metro.stations, chosenPlace)[0].name);
  $('home-choice').hidden = false;
  $('save-home').disabled = false;
}

async function searchAddress(event) {
  event.preventDefault();
  $('results').replaceChildren();
  $('home-choice').hidden = true;
  $('save-home').disabled = true;
  chosenPlace = null;
  $('search-status').textContent = 'Söker …';
  const params = new URLSearchParams({ q: $('address').value, limit: '5', bbox: STOCKHOLM_BBOX, lang: 'default' });
  try {
    const res = await fetch(`${GEOCODE_URL}?${params}`, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error();
    const { features } = await res.json();
    $('search-status').textContent = features.length ? 'Välj rätt adress:' : 'Hittade ingen adress i Stockholmsområdet.';
    $('results').replaceChildren(...features.map((feature) => {
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = placeLabel(feature);
      button.setAttribute('aria-pressed', 'false');
      button.addEventListener('click', () => choosePlace(feature, button));
      item.append(button);
      return item;
    }));
    if (features.length === 1) choosePlace(features[0], $('results').querySelector('button'));
  } catch {
    $('search-status').textContent = 'Adressökningen svarar inte just nu. Försök igen.';
  }
}

function saveHome() {
  state.home = { ...chosenPlace, station: $('home-station').value };
  localStorage.setItem(HOME_KEY, JSON.stringify(state.home));
  $('settings').close();
  state.departures = null;
  render();
  if (state.start) refreshDepartures(); else startLocating();
}

function openSettings() {
  $('address').value = state.home?.address ?? '';
  $('search-status').textContent = state.home ? `Sparad hemstation: ${state.home.station}` : '';
  $('results').replaceChildren();
  $('home-choice').hidden = true;
  $('save-home').disabled = true;
  $('settings').showModal();
}

function pickStartManually() {
  const station = stationByName($('start-station').value);
  if (!station) return;
  state.start = { station, walkMinutes: 0, estimated: false };
  state.departures = null;
  state.problem = null;
  render();
  refreshDepartures();
}

$('open-settings').addEventListener('click', openSettings);
$('close-settings').addEventListener('click', () => $('settings').close());
$('search-form').addEventListener('submit', searchAddress);
$('save-home').addEventListener('click', saveHome);
$('start-station').addEventListener('change', pickStartManually);
$('retry').addEventListener('click', () => {
  state.problem = null;
  render();
  if (state.start) refreshDepartures(); else startLocating();
});

state.metro = await (await fetch('data/metro.json')).json();
fillStationSelect($('start-station'), '');
$('start-station').prepend(new Option('Välj station', '', true, true));
render();
if (state.home) startLocating(); else openSettings();
setInterval(render, 1000);
setInterval(() => { if (!document.hidden) refreshDepartures(); }, REFRESH_MS);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshDepartures(); });
