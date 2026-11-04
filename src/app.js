import {
  addressSuggestions, buildBoard, departureMessage, destinationChoices, distanceMeters,
  nearestStations, nextDestination, planTrip, tripPhrase,
} from './logic.js';
import { abortAfter, fetchDepartures, findStart } from './trip.js';

const ADDRESS_URL = 'https://journeyplanner.integration.sl.se/v2/stop-finder';
const OLD_HOME_KEY = 'nasta-tag.home';
const PLACES_KEY = 'nasta-tag.places';
const SUGGESTED_LABELS = ['Hem', 'Jobbet'];
const REFRESH_MS = 30000;
const MOVED_METERS = 40;
const LATER_COUNT = 3;
const SEARCH_DELAY_MS = 250;

const $ = (id) => document.getElementById(id);
const clock = new Intl.DateTimeFormat('sv-SE', { hour: '2-digit', minute: '2-digit' });

function loadPlaces() {
  const saved = JSON.parse(localStorage.getItem(PLACES_KEY) ?? 'null');
  if (saved) return saved;
  const home = JSON.parse(localStorage.getItem(OLD_HOME_KEY) ?? 'null');
  if (!home) return { places: [], activeId: null };
  const id = crypto.randomUUID();
  return { places: [{ ...home, id, label: 'Hem' }], activeId: id };
}

const state = {
  metro: null,
  ...loadPlaces(), // places: [{ id, label, address, lat, lon, station, weekdaysOnly }], activeId
  chosenId: null, // destinationen du själv valt, gäller tills du är framme
  draft: null, // destinationen som redigeras i inställningarna
  position: null,
  walkedFrom: null,
  start: null, // { station, walkMinutes, estimated }
  plan: null,
  departures: null,
  fetchedAt: null,
  problem: null, // { text, retry }
};

const activePlace = () => state.places.find((p) => p.id === state.activeId) ?? null;

function savePlaces() {
  const { places, activeId } = state;
  localStorage.setItem(PLACES_KEY, JSON.stringify({ places, activeId }));
}

function stationByName(name) {
  return state.metro.stations.find((s) => s.name === name);
}

async function refreshDepartures() {
  if (!state.start || !state.places.length) return;
  const { station } = state.start;
  const destination = nextDestination(
    state.places, state.activeId, station.name, new Date(), state.chosenId,
  );
  if (destination.id !== state.chosenId) state.chosenId = null;
  if (destination.id !== state.activeId) {
    state.activeId = destination.id;
    savePlaces();
  }
  state.plan = planTrip(state.metro.routes, station.name, destination.station);
  if (station.name === destination.station) {
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
  const start = await findStart(state.metro.stations, position);
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

function renderMessage(text, retry = false) {
  document.documentElement.dataset.status = 'idle';
  $('verdict').textContent = text;
  $('time').textContent = '';
  $('train').textContent = '';
  $('line').textContent = '';
  $('advice').textContent = '';
  $('later').replaceChildren();
  $('retry').hidden = !retry;
}

function laterRow(train) {
  const row = document.createElement('li');
  row.textContent = `${clock.format(train.time)}  ${train.line} ${train.destination}`;
  return row;
}

function renderDestinations() {
  const nav = $('destinations');
  const choices = destinationChoices(state.places, state.activeId, state.start?.station.name);
  nav.hidden = !choices.length;
  const key = JSON.stringify([choices.map((p) => [p.id, p.label]), state.activeId]);
  if (nav.dataset.key === key) return;
  nav.dataset.key = key;
  nav.replaceChildren(...choices.map((place) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = place.label;
    button.setAttribute('aria-pressed', String(place.id === state.activeId));
    button.addEventListener('click', () => {
      state.activeId = place.id;
      state.chosenId = place.id;
      applyPlaces();
    });
    return button;
  }));
}

function routeText(start, plan, destination) {
  if (!start || !destination || start.station.name === destination.station) return '';
  const walk = start.walkMinutes > 0 && `${start.estimated ? 'ca ' : ''}${minutes(start.walkMinutes)} gång`;
  const transfer = plan?.transfer && `byte ${plan.transfer}`;
  return [walk, start.station.name, transfer, destination.label].filter(Boolean).join(' → ');
}

function render() {
  const { start, plan } = state;
  const destination = activePlace();
  renderDestinations();
  $('route').textContent = routeText(start, plan, destination);
  $('updated').textContent = state.fetchedAt ? `Uppdaterad ${clock.format(state.fetchedAt)}` : '';

  if (!destination) return renderMessage('Börja med att lägga till en destination.');
  if (state.problem) return renderMessage(state.problem.text, state.problem.retry);
  if (!start) return renderMessage('Letar efter din plats …');
  if (start.station.name === destination.station) return renderMessage(`Du är redan vid ${destination.label}.`);
  if (!state.departures) return renderMessage('Hämtar avgångar …');

  const board = buildBoard({
    departures: state.departures,
    routes: state.metro.routes,
    from: start.station.name,
    target: plan.target,
    now: new Date(),
    walkMinutes: start.walkMinutes,
  });
  const [next, ...later] = board.filter((t) => t.status !== 'missed');
  if (!next) return renderMessage('Inga tåg du hinner med inom den närmaste timmen.');

  const message = departureMessage(next);
  document.documentElement.dataset.status = next.status;
  $('retry').hidden = true;
  $('verdict').textContent = message.lead;
  $('time').textContent = message.wait;
  $('advice').textContent = message.bridge;
  $('train').textContent = `${clock.format(next.time)}-tåget ${tripPhrase(destination.label)}`;
  $('line').textContent = `Linje ${next.line} mot ${next.destination}`;
  $('later').replaceChildren(...later.slice(0, LATER_COUNT).map(laterRow));
}

function fillStationSelect(select, selected) {
  const names = state.metro.stations.map((s) => s.name).sort((a, b) => a.localeCompare(b, 'sv'));
  select.replaceChildren(...names.map((name) => new Option(name, name, false, name === selected)));
}

function applyPlaces() {
  savePlaces();
  state.departures = null;
  render();
  if (state.start) refreshDepartures(); else startLocating();
}

function chooseLocation(location) {
  const station = nearestStations(state.metro.stations, location)[0].name;
  state.draft = { ...state.draft, ...location, station };
  $('address').value = '';
  $('results').replaceChildren();
  $('search-status').textContent = '';
  renderDraft();
}

function suggestionItem(place) {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = place.address;
  const station = document.createElement('small');
  station.textContent = `Närmaste station: ${nearestStations(state.metro.stations, place)[0].name}`;
  button.append(station);
  button.addEventListener('click', () => chooseLocation(place));
  const item = document.createElement('li');
  item.append(button);
  return item;
}

let searchTimer = null;
let searchAbort = null;

async function searchAddress(query) {
  searchAbort?.abort();
  const search = new AbortController();
  searchAbort = search;
  const params = new URLSearchParams({ name_sf: query, type_sf: 'any', any_obj_filter_sf: '12' });
  try {
    const res = await fetch(`${ADDRESS_URL}?${params}`, { signal: abortAfter(8000, search) });
    if (!res.ok) throw new Error();
    const { locations } = await res.json();
    const places = addressSuggestions(locations ?? []);
    $('search-status').textContent = places.length ? '' : 'Hittar ingen sådan adress i Stockholmsområdet.';
    $('results').replaceChildren(...places.map(suggestionItem));
  } catch {
    if (searchAbort === search) $('search-status').textContent = 'Adressökningen svarar inte just nu. Försök igen.';
  }
}

function onAddressInput() {
  clearTimeout(searchTimer);
  searchAbort?.abort();
  searchAbort = null;
  const query = $('address').value.trim();
  if (query.length < 3) {
    $('results').replaceChildren();
    $('search-status').textContent = '';
    return;
  }
  searchTimer = setTimeout(() => searchAddress(query), SEARCH_DELAY_MS);
}

function useCurrentLocation() {
  const failed = () => { $('search-status').textContent = 'Hittar inte din plats. Skriv adressen i stället.'; };
  const save = (position) => chooseLocation({ address: 'Min plats', ...position });
  if (state.position) return save(state.position);
  if (!navigator.geolocation) return failed();
  $('search-status').textContent = 'Hämtar din plats …';
  navigator.geolocation.getCurrentPosition(
    ({ coords }) => save({ lat: coords.latitude, lon: coords.longitude }),
    failed,
    { enableHighAccuracy: true, timeout: 15000 },
  );
}

function renderDraft() {
  const { draft } = state;
  $('saved-address').textContent = draft.address ?? '';
  $('saved-row').hidden = !draft.address;
  $('station-choice').hidden = !draft.station;
  if (draft.station) fillStationSelect($('place-station'), draft.station);
  $('nav-action').disabled = !draft.station || !$('place-label').value.trim();
}

function placeRow(place) {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = place.label;
  const details = document.createElement('small');
  details.textContent = [place.address, place.station, place.weekdaysOnly && 'Vardagar'].filter(Boolean).join(' · ');
  button.append(details);
  button.addEventListener('click', () => showPlaceForm(place));
  const item = document.createElement('li');
  item.append(button);
  return item;
}

function showList() {
  state.draft = null;
  $('settings-title').textContent = 'Inställningar';
  $('nav-back').hidden = true;
  $('nav-action').textContent = 'Klar';
  $('nav-action').disabled = false;
  $('place-form').hidden = true;
  $('view-list').hidden = false;
  $('place-list').replaceChildren(...state.places.map(placeRow));
  $('settings').scrollTop = 0;
}

function showPlaceForm(place) {
  const taken = new Set(state.places.map((p) => p.label));
  const label = place?.label ?? SUGGESTED_LABELS.find((name) => !taken.has(name)) ?? '';
  state.draft = { ...place };
  $('settings-title').textContent = place ? place.label : 'Ny destination';
  $('nav-back').hidden = false;
  $('nav-action').textContent = 'Spara';
  $('view-list').hidden = true;
  $('place-form').hidden = false;
  $('delete-group').hidden = !place;
  $('place-label').value = label;
  $('address').value = '';
  $('results').replaceChildren();
  $('search-status').textContent = '';
  $('place-weekdays').checked = place?.weekdaysOnly ?? label === 'Jobbet';
  renderDraft();
  $('settings').scrollTop = 0;
}

function saveDraft() {
  const place = {
    ...state.draft,
    label: $('place-label').value.trim(),
    weekdaysOnly: $('place-weekdays').checked,
  };
  if (place.id) {
    state.places = state.places.map((p) => (p.id === place.id ? place : p));
  } else {
    place.id = crypto.randomUUID();
    state.places = [...state.places, place];
  }
  state.activeId ??= place.id;
  applyPlaces();
  showList();
}

function deleteDraft() {
  state.places = state.places.filter((p) => p.id !== state.draft.id);
  if (state.activeId === state.draft.id) state.activeId = state.places[0]?.id ?? null;
  applyPlaces();
  showList();
}

function openSettings() {
  showList();
  if (!state.places.length) showPlaceForm();
  $('settings').showModal();
  if (!state.places.length) $('address').focus();
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
$('nav-back').addEventListener('click', showList);
$('nav-action').addEventListener('click', () => {
  if (state.draft) saveDraft(); else $('settings').close();
});
$('add-place').addEventListener('click', () => showPlaceForm());
$('delete-place').addEventListener('click', deleteDraft);
$('place-form').addEventListener('submit', (event) => {
  event.preventDefault();
  $('results').querySelector('button')?.click();
});
$('place-label').addEventListener('input', renderDraft);
$('address').addEventListener('input', onAddressInput);
$('use-location').addEventListener('click', useCurrentLocation);
$('place-station').addEventListener('change', () => {
  state.draft.station = $('place-station').value;
});
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
if (state.places.length) startLocating(); else openSettings();
setInterval(render, 1000);
setInterval(() => { if (!document.hidden) refreshDepartures(); }, REFRESH_MS);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshDepartures(); });
