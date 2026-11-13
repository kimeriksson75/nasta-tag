import {
  addressSuggestions, bearingDegrees, buildTrips, departureMessage, destinationChoices, distanceMeters,
  distanceText, lineText, nextDestination, pickTrips, placeAt, routeBearing, routeText, tripName, walkSteps,
} from './logic.js';
import { drawRoute, followMe, openMap, themeMap } from './map.js';
import { abortAfter, fetchUpcomingTrips, fetchWalkRoute } from './trip.js';

const ADDRESS_URL = 'https://journeyplanner.integration.sl.se/v2/stop-finder';
const OLD_HOME_KEY = 'nasta-tag.home';
const PLACES_KEY = 'nasta-tag.places';
const REMINDER_KEY = 'nasta-tag.reminder';
const API_URL = location.hostname === 'medgesej.se' ? 'https://nasta-tag-production.up.railway.app' : '';
const PUSH_KEY = 'BNkk_La9F8B2DPFc6wgGUCp_8uRT3ZvUzQQiuVHnyHsfEHQKBbKOiC2AqtGWFMJQ9cw1xRIHLbFpldAwRmri0dQ';
const NEAR_STOP_METERS = 30;
const CAN_NOTIFY = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
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
  metro: null, // tunnelbanans stationer, för äldre sparade destinationer och för att välja start utan plats
  ...loadPlaces(), // places: [{ id, label, address, lat, lon, weekdaysOnly }], activeId
  chosenId: null, // destinationen du själv valt, gäller tills du är framme
  hereId: null, // destinationen du står vid, om någon
  next: null, // resan som visas stort
  reminder: JSON.parse(localStorage.getItem(REMINDER_KEY)), // { id, until, stop, destination }
  reminderProblem: null,
  movingReminder: false,
  walkStop: null, // hållplatsen gångvyn visar vägen till
  walkRoute: null, // gångvägens punkter medan gångvyn är öppen
  heading: null, // kompassriktning, null tills telefonen har svarat
  compassOffered: typeof window.DeviceOrientationEvent?.requestPermission === 'function',
  arrowAngle: 0,
  draft: null, // destinationen som redigeras i inställningarna
  position: null,
  walkedFrom: null,
  journeys: null, // resorna från SL till destinationen i journeysFor
  journeysFor: null,
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

// Hem ger Jobbet och tvärtom när du är framme. Ett eget val gäller tills du är framme.
function chooseDestination() {
  state.hereId = state.position ? placeAt(state.places, state.position) : null;
  const destination = nextDestination(state.places, state.activeId, state.hereId, new Date(), state.chosenId);
  if (destination.id !== state.chosenId) state.chosenId = null;
  if (destination.id !== state.activeId) {
    state.activeId = destination.id;
    savePlaces();
  }
  return destination;
}

let tripsAsked = 0;
async function refreshTrips() {
  if (!state.position || !state.places.length) return;
  const destination = chooseDestination();
  if (state.hereId === destination.id) return render();
  const asked = ++tripsAsked;
  try {
    const journeys = await fetchUpcomingTrips(state.position, destination);
    if (asked !== tripsAsked) return; // ett nyare svar är på väg
    state.journeys = journeys;
    state.journeysFor = destination.id;
    state.fetchedAt = new Date();
    state.problem = null;
  } catch {
    if (asked === tripsAsked && state.journeysFor !== destination.id) {
      state.problem = { text: 'Kunde inte hämta resor från SL.', retry: true };
    }
  }
  render();
  followReminder();
}

async function onPosition({ coords }) {
  const position = { lat: coords.latitude, lon: coords.longitude };
  state.position = position;
  followOnMap();
  if (state.problem?.gps) state.problem = null;
  $('start-picker').hidden = true;
  if (state.walkedFrom && distanceMeters(state.walkedFrom, position) < MOVED_METERS) return;
  state.walkedFrom = position;
  await refreshTrips();
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

function setStatus(status) {
  const root = document.documentElement;
  if (root.dataset.status === status) return;
  root.dataset.status = status;
  themeMap(status);
}

function saveReminder(reminder) {
  state.reminder = reminder;
  if (reminder) localStorage.setItem(REMINDER_KEY, JSON.stringify(reminder));
  else localStorage.removeItem(REMINDER_KEY);
}

function renderReminder() {
  if (state.reminder && Date.now() > state.reminder.until) saveReminder(null);
  const button = $('remind');
  const on = Boolean(state.reminder);
  button.hidden = !CAN_NOTIFY || (!on && !['calm', 'hurry'].includes(state.next?.status));
  button.setAttribute('aria-pressed', String(on));
  button.textContent = state.reminderProblem ?? (on ? 'Notiser på' : 'Påminn mig');
}

async function pushSubscription() {
  const registration = await navigator.serviceWorker.register('sw.js');
  await navigator.serviceWorker.ready;
  const key = Uint8Array.from(atob(PUSH_KEY.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
  return await registration.pushManager.getSubscription()
    ?? registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
}

async function post(path, body) {
  const res = await fetch(`${API_URL}${path}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Servern svarade ${res.status}`);
  return res.text();
}

async function armReminder() {
  const { next, position } = state;
  const destination = activePlace();
  const id = await post('/api/remind', {
    subscription: await pushSubscription(),
    key: next.key,
    time: next.time.toISOString(),
    status: next.status,
    from: position,
    to: { lat: destination.lat, lon: destination.lon },
    label: destination.label,
  });
  return {
    id, until: next.time.getTime() + 60000, stop: next.stop.name, destination: destination.id,
  };
}

async function startReminder() {
  if (await Notification.requestPermission() !== 'granted') {
    throw new Error('Tillåt notiser för appen i Inställningar');
  }
  saveReminder(await armReminder());
}

// Har du bytt hållplats eller mål gäller påminnelsen fel avgång, så den flyttar med.
// Är det redan dags att gå finns inget kvar att påminna om.
async function followReminder() {
  const { reminder, next } = state;
  if (!reminder || !next || state.movingReminder) return;
  if (reminder.stop === next.stop.name && reminder.destination === activePlace().id) return;
  state.movingReminder = true;
  try {
    const moved = next.status === 'rush' ? null : await armReminder();
    await post('/api/remind/cancel', { id: reminder.id }).catch(() => {});
    saveReminder(moved);
    renderReminder();
  } catch {
    // Den gamla påminnelsen ligger kvar, och nästa uppdatering försöker igen.
  } finally {
    state.movingReminder = false;
  }
}

async function toggleReminder() {
  state.reminderProblem = null;
  try {
    if (state.reminder) {
      await post('/api/remind/cancel', { id: state.reminder.id });
      saveReminder(null);
    } else {
      await startReminder();
    }
  } catch (error) {
    state.reminderProblem = error.message.startsWith('Tillåt') ? error.message : 'Det gick inte. Försök igen.';
  }
  renderReminder();
}

function renderMessage(text, retry = false) {
  state.next = null;
  renderReminder();
  setStatus('idle');
  $('verdict').textContent = text;
  $('time').textContent = '';
  $('train').textContent = '';
  $('line').textContent = '';
  $('advice').textContent = '';
  renderLater([]);
  $('retry').hidden = !retry;
}

function laterRow(trip) {
  const row = document.createElement('li');
  row.textContent = `${clock.format(trip.time)}  ${lineText(trip)}`;
  return row;
}

function renderLater(trains) {
  $('upcoming').hidden = !trains.length;
  $('later').replaceChildren(...trains.map(laterRow));
}

function renderDestinations() {
  const nav = $('destinations');
  const choices = state.position ? destinationChoices(state.places, state.activeId, state.hereId) : [];
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

function onOrientation(event) {
  const heading = event.webkitCompassHeading ?? (event.absolute ? 360 - event.alpha : null);
  if (heading === null || Number.isNaN(heading)) return;
  state.heading = heading;
  renderCompass();
  followOnMap();
}

function listenToCompass() {
  state.compassOffered = false;
  addEventListener('deviceorientation', onOrientation);
  addEventListener('deviceorientationabsolute', onOrientation);
}

// iPhone kräver ett tryck första gången. Har du redan sagt ja går det utan.
async function askForCompass(fromTap) {
  try {
    if (await DeviceOrientationEvent.requestPermission() === 'granted') listenToCompass();
    else if (fromTap) state.compassOffered = false;
  } catch {
    if (fromTap) state.compassOffered = false;
  }
  renderCompass();
}

// Gångvägens längd när den finns, annars fågelvägen.
function stopDistance() {
  const { next, position } = state;
  return next.walkMeters || distanceMeters(position, next.stop);
}

function renderCompass() {
  const { next, position, compassOffered, heading } = state;
  const button = $('compass');
  const near = !position || !next || distanceMeters(position, next.stop) < NEAR_STOP_METERS;
  button.hidden = near || !(next.walkMinutes > 0);
  if (button.hidden) return;
  const distance = distanceText(stopDistance());
  $('compass-text').textContent = distance;
  $('walk-distance').textContent = `${distance} · ${minutes(next.walkMinutes)} gång`;
  $('compass-hint').hidden = !compassOffered;
  for (const arrow of document.querySelectorAll('.arrow')) arrow.hidden = heading === null;
  if (heading === null) return;
  // Kortaste vägen runt, så att pilen inte snurrar ett varv när den passerar norr.
  const target = bearingDegrees(position, next.stop) - heading;
  state.arrowAngle += ((target - state.arrowAngle + 540) % 360 + 360) % 360 - 180;
  document.documentElement.style.setProperty('--arrow', `${state.arrowAngle}deg`);
}

function stepRow({ text, distance }) {
  const row = document.createElement('li');
  const what = document.createElement('span');
  what.textContent = text;
  const far = document.createElement('span');
  far.textContent = distance;
  row.append(what, far);
  return row;
}

let mapReady = null;

// Uppåt på kartan är dit du tittar. Utan kompass är det dit gångvägen leder.
function followOnMap() {
  const { position, walkStop, heading, walkRoute } = state;
  if (!$('walk').open || !walkStop) return;
  const along = walkRoute ? routeBearing(position, walkRoute) : bearingDegrees(position, walkStop);
  followMe(position, heading ?? along);
}

async function loadWalkRoute() {
  const { position, walkStop: stop } = state;
  try {
    const route = await fetchWalkRoute(position, stop);
    if (state.walkStop !== stop || !$('walk').open) return;
    $('walk-steps').replaceChildren(...walkSteps(route.steps, stop.name).map(stepRow));
    $('walk-status').textContent = '';
    state.walkRoute = route.coordinates;
    await mapReady;
    drawRoute(route.coordinates, stop);
    followOnMap();
  } catch {
    $('walk-status').textContent = 'Hittar ingen gångväg just nu. Prova Kartor.';
  }
}

// Byter resan hållplats medan gångvyn är öppen följer vyn med.
function showWalkStop(stop) {
  if (state.walkStop?.name === stop.name) return;
  state.walkStop = stop;
  state.walkRoute = null;
  $('walk-title').textContent = `Till ${stop.name}`;
  $('walk-maps').href = `https://maps.apple.com/?daddr=${stop.lat},${stop.lon}&dirflg=w`;
  $('walk-steps').replaceChildren();
  $('walk-status').textContent = '';
  loadWalkRoute();
}

function openWalkView() {
  state.walkStop = null;
  $('walk').showModal();
  renderCompass();
  // Vägbeskrivningen väntar inte på kartan, den ska synas även om kartan inte går att ladda.
  $('walk-map').hidden = false;
  mapReady = openMap($('walk-map'), document.documentElement.dataset.status)
    .then(followOnMap)
    .catch(() => { $('walk-map').hidden = true; });
  showWalkStop(state.next.stop);
}

let lastAllMissed = 0;
function render() {
  const destination = activePlace();
  renderDestinations();
  $('updated').textContent = state.fetchedAt ? `Uppdaterad ${clock.format(state.fetchedAt)}` : '';
  const show = (text, retry) => {
    $('route').textContent = '';
    renderMessage(text, retry);
    renderCompass();
  };

  if (!destination) return show('Börja med att lägga till en destination.');
  if (state.problem) return show(state.problem.text, state.problem.retry);
  if (!state.position) return show('Letar efter din plats …');
  if (state.hereId === destination.id) return show(`Du är redan vid ${destination.label}.`);
  if (!state.journeys || state.journeysFor !== destination.id) return show('Hämtar resor …');

  const { next, later } = pickTrips(buildTrips(state.journeys, new Date()));
  if (!next) {
    // SL ger bara tre resor åt gången. Har alla gått frågar vi efter nya, högst var tionde sekund.
    if (Date.now() - lastAllMissed > 10000) {
      lastAllMissed = Date.now();
      refreshTrips();
    }
    return show('Hittar ingen resa du hinner med just nu.');
  }

  state.next = next;
  $('route').textContent = routeText(next, destination.label);
  renderCompass();
  if ($('walk').open) showWalkStop(next.stop);
  renderReminder();
  const message = departureMessage(next);
  setStatus(next.status);
  $('retry').hidden = true;
  $('verdict').textContent = message.lead;
  $('time').textContent = message.wait;
  $('advice').textContent = message.bridge;
  $('train').textContent = tripName(next, destination.label);
  $('line').textContent = lineText(next);
  renderLater(later.slice(0, LATER_COUNT));
}

function fillStationSelect(select, selected) {
  const names = state.metro.stations.map((s) => s.name).sort((a, b) => a.localeCompare(b, 'sv'));
  select.replaceChildren(...names.map((name) => new Option(name, name, false, name === selected)));
}

function applyPlaces() {
  savePlaces();
  state.journeys = null;
  render();
  if (state.position) refreshTrips(); else startLocating();
}

function chooseLocation(location) {
  state.draft = { ...state.draft, ...location };
  $('address').value = '';
  $('results').replaceChildren();
  $('search-status').textContent = '';
  renderDraft();
}

function suggestionItem(place) {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = place.address;
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
  $('nav-action').disabled = !Number.isFinite(draft.lat) || !$('place-label').value.trim();
}

function placeRow(place) {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = place.label;
  const details = document.createElement('small');
  details.textContent = [place.address, place.weekdaysOnly && 'Vardagar'].filter(Boolean).join(' · ');
  button.append(details);
  button.addEventListener('click', () => showPlaceForm(place));
  const item = document.createElement('li');
  item.append(button);
  return item;
}

function showList() {
  $('push-note').hidden = CAN_NOTIFY;
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

// Utan plats från telefonen räknar appen resan från stationen du väljer.
function pickStartManually() {
  const station = stationByName($('start-station').value);
  if (!station) return;
  state.position = { lat: station.lat, lon: station.lon };
  state.walkedFrom = state.position;
  state.problem = null;
  render();
  refreshTrips();
}

// Äldre destinationer sparades som tunnelbanestation. Resorna behöver en plats, så stationen får vara den.
function migratePlaces() {
  let changed = false;
  state.places = state.places.map((place) => {
    if (Number.isFinite(place.lat)) return place;
    const station = stationByName(place.station);
    if (!station) return place;
    changed = true;
    return { ...place, address: place.address ?? station.name, lat: station.lat, lon: station.lon };
  });
  if (changed) savePlaces();
}

$('open-settings').addEventListener('click', openSettings);
$('nav-back').addEventListener('click', showList);
$('nav-action').addEventListener('click', () => {
  if (state.draft) saveDraft(); else $('settings').close();
});
$('add-place').addEventListener('click', () => showPlaceForm());
$('remind').addEventListener('click', toggleReminder);
$('compass').addEventListener('click', () => {
  // Första trycket tar fram pilen, nästa öppnar gångvyn.
  if (state.compassOffered) askForCompass(true);
  else openWalkView();
});
$('walk-back').addEventListener('click', () => $('walk').close());
$('delete-place').addEventListener('click', deleteDraft);
$('place-form').addEventListener('submit', (event) => {
  event.preventDefault();
  $('results').querySelector('button')?.click();
});
$('place-label').addEventListener('input', renderDraft);
$('address').addEventListener('input', onAddressInput);
$('use-location').addEventListener('click', useCurrentLocation);
$('start-station').addEventListener('change', pickStartManually);
$('retry').addEventListener('click', () => {
  state.problem = null;
  render();
  if (state.position) refreshTrips(); else startLocating();
});

if (state.compassOffered) askForCompass(false); else listenToCompass();
state.metro = await (await fetch('data/metro.json')).json();
migratePlaces();
fillStationSelect($('start-station'), '');
$('start-station').prepend(new Option('Välj station', '', true, true));
render();
if (state.places.length) startLocating(); else openSettings();
setInterval(render, 1000);
setInterval(() => { if (!document.hidden) refreshTrips(); }, REFRESH_MS);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshTrips(); });
