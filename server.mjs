// Webbappen plus /api/next, som ger klockans genväg ett färdigt textsvar.
// Position och stationer används bara för svaret och sparas eller loggas inte.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { buildBoard, planTrip, watchDestination, watchSummary } from './src/logic.js';
import { fetchDepartures, findStart } from './src/trip.js';

const ROOT = import.meta.dirname;
const PORT = process.env.PORT ?? 5180;
const MAX_BODY_BYTES = 2048;
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
  '/index.html', '/style.css', '/manifest.webmanifest', '/icon.svg', '/icon-180.png', '/icon-512.png',
  '/src/app.js', '/src/logic.js', '/src/trip.js', '/data/metro.json',
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

async function staticFile(req, res) {
  const { pathname } = new URL(req.url, 'http://localhost');
  const path = pathname === '/' ? '/index.html' : pathname;
  if (!PUBLIC_FILES.has(path)) return text(res, 404, 'Finns inte.');
  res.writeHead(200, { 'content-type': TYPES[extname(path)], 'cache-control': 'no-cache' });
  res.end(await readFile(join(ROOT, path)));
}

createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/api/next') return nextTrain(req, res);
  if (req.method === 'GET' || req.method === 'HEAD') return staticFile(req, res);
  text(res, 405, 'Går inte.');
}).listen(PORT);
