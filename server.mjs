// Webbappen plus /api/next, som ger klockans genväg ett färdigt textsvar, och /api/remind
// för notiser. Position och stationer används bara för svaret och sparas eller loggas inte.
// Påminnelser ligger bara i minnet och försvinner när tåget har gått.
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import webpush from 'web-push';
import { buildBoard, planTrip, reminderStep, watchDestination, watchSummary } from './src/logic.js';
import { fetchDepartures, findStart } from './src/trip.js';

const ROOT = import.meta.dirname;
const PORT = process.env.PORT ?? 5180;
const MAX_BODY_BYTES = 2048;
const MAX_REMINDERS = 100;
const REMINDER_TTL_MS = 2 * 60 * 60 * 1000;
const REMINDER_CHECK_MS = 20000;
const APP_ORIGIN = 'https://medgesej.se';
const PUSH_HOSTS = /^https:\/\/([a-z0-9-]+\.)*(push\.apple\.com|fcm\.googleapis\.com|push\.services\.mozilla\.com|notify\.windows\.com)\//;
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
};
const PUBLIC_FILES = new Set([
  '/index.html', '/sw.js', '/style.css', '/manifest.webmanifest', '/icon.svg', '/icon-180.png', '/icon-512.png',
  '/src/app.js', '/src/logic.js', '/src/map.js', '/src/trip.js', '/data/metro.json',
  '/vendor/maplibre-gl.js', '/vendor/maplibre-gl.css',
]);

const metro = JSON.parse(await readFile(join(ROOT, 'data/metro.json')));

function text(res, status, body) {
  res.writeHead(status, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
  res.end(body);
}

async function readJson(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > MAX_BODY_BYTES) throw new Error('För stort anrop');
  }
  return JSON.parse(body);
}

const stationNamed = (name) => metro.stations.find((s) => s.name.toLowerCase() === name.toLowerCase())?.name;

// Genvägar skickar tal som text, ibland med decimalkomma.
const coordinate = (value) => Number(String(value).trim().replace(',', '.'));

async function nextTrain(req, res) {
  let input;
  try {
    input = await readJson(req);
  } catch {
    return text(res, 400, 'Kunde inte läsa frågan.');
  }
  const position = { lat: coordinate(input.lat), lon: coordinate(input.lon) };
  const homeName = String(input.home ?? '').trim();
  const workName = String(input.work ?? '').trim();
  const home = stationNamed(homeName);
  const work = workName ? stationNamed(workName) : null;
  if (!Number.isFinite(position.lat) || !Number.isFinite(position.lon)) return text(res, 400, 'Hittar inte din plats.');
  if (!home) return text(res, 400, `Okänd hemstation: ${homeName}`);
  if (workName && !work) return text(res, 400, `Okänd jobbstation: ${workName}`);

  try {
    const start = await findStart(metro.stations, position);
    const now = new Date();
    const destination = watchDestination({ home, work, stationName: start.station.name, now });
    const plan = planTrip(metro.routes, start.station.name, destination);
    const departures = start.station.name === destination ? [] : await fetchDepartures(start.station.siteId);
    const board = buildBoard({
      departures,
      routes: metro.routes,
      from: start.station.name,
      target: plan.target,
      now,
      walkMinutes: start.walkMinutes,
    });
    text(res, 200, watchSummary({ start, home: destination, plan, board }));
  } catch {
    text(res, 502, 'Kunde inte hämta avgångar från SL.');
  }
}

const { VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY } = process.env;
if (VAPID_PRIVATE_KEY) webpush.setVapidDetails('https://medgesej.se/nasta-tag', VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const reminders = new Map();

async function remind(req, res) {
  if (!VAPID_PRIVATE_KEY) return text(res, 503, 'Notiser är inte igång.');
  let input;
  try {
    input = await readJson(req);
  } catch {
    return text(res, 400, 'Kunde inte läsa frågan.');
  }
  const { subscription, journey, status, walkMinutes } = input;
  const from = stationNamed(String(input.from ?? ''));
  const destination = stationNamed(String(input.destination ?? ''));
  const label = String(input.label ?? '').slice(0, 24);
  const valid = PUSH_HOSTS.test(subscription?.endpoint) && subscription.keys?.p256dh && subscription.keys?.auth
    && from && destination && from !== destination && label && Number.isFinite(journey)
    && ['calm', 'hurry'].includes(status) && walkMinutes >= 0 && walkMinutes <= 180;
  if (!valid) return text(res, 400, 'Kunde inte läsa frågan.');
  if (reminders.size >= MAX_REMINDERS) return text(res, 503, 'Försök igen om en stund.');
  const id = randomUUID();
  const { target } = planTrip(metro.routes, from, destination);
  reminders.set(id, {
    subscription, journey, status, walkMinutes, from, target, label, expires: Date.now() + REMINDER_TTL_MS,
  });
  text(res, 201, id);
}

async function cancelReminder(req, res) {
  try {
    reminders.delete((await readJson(req)).id);
    text(res, 200, 'Avstängd.');
  } catch {
    text(res, 400, 'Kunde inte läsa frågan.');
  }
}

async function checkReminder(id, reminder) {
  const { from, target, walkMinutes, subscription } = reminder;
  if (Date.now() > reminder.expires) return reminders.delete(id);
  const station = metro.stations.find((s) => s.name === from);
  const departures = await fetchDepartures(station.siteId);
  const board = buildBoard({ departures, routes: metro.routes, from, target, now: new Date(), walkMinutes });
  const step = reminderStep(reminder, board);
  reminder.status = step.status;
  if (step.done) reminders.delete(id);
  if (!step.text) return;
  const payload = JSON.stringify({ title: 'Nästa tåg', body: step.text });
  await webpush.sendNotification(subscription, payload, { TTL: 120, urgency: 'high' }).catch((error) => {
    if ([404, 410].includes(error.statusCode)) reminders.delete(id);
  });
}

async function checkReminders() {
  // Ett tillfälligt fel hos SL ska inte stoppa påminnelsen, nästa varv försöker igen.
  await Promise.allSettled([...reminders].map(([id, reminder]) => checkReminder(id, reminder)));
  setTimeout(checkReminders, REMINDER_CHECK_MS);
}

async function staticFile(req, res) {
  const { pathname } = new URL(req.url, 'http://localhost');
  const path = pathname === '/' ? '/index.html' : pathname;
  if (!PUBLIC_FILES.has(path)) return text(res, 404, 'Finns inte.');
  res.writeHead(200, { 'content-type': TYPES[extname(path)], 'cache-control': 'no-cache' });
  res.end(await readFile(join(ROOT, path)));
}

createServer((req, res) => {
  if (req.url.startsWith('/api/remind')) {
    res.setHeader('access-control-allow-origin', APP_ORIGIN);
    res.setHeader('access-control-allow-headers', 'content-type');
    if (req.method === 'OPTIONS') return text(res, 204, '');
  }
  if (req.method === 'POST' && req.url === '/api/remind') return remind(req, res);
  if (req.method === 'POST' && req.url === '/api/remind/cancel') return cancelReminder(req, res);
  if (req.method === 'POST' && req.url === '/api/next') return nextTrain(req, res);
  if (req.method === 'GET' || req.method === 'HEAD') return staticFile(req, res);
  text(res, 405, 'Går inte.');
}).listen(PORT);

checkReminders();
