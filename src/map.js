// Kartan i gångvyn. Biblioteket laddas först när vyn öppnas, resten av appen behöver det inte.
const TILES = 'https://tiles.openfreemap.org/planet';
const GLYPHS = 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';
const THEMES = {
  idle: { land: '#14171c', park: '#1a2420', water: '#10262f', building: '#1b1f26', road: '#3a424e', label: '#aab2bd', route: '#f5f6f7', halo: '#14171c' },
  calm: { land: '#157a4b', park: '#1a8755', water: '#0f6461', building: '#1b8656', road: '#4aa67b', label: '#e3f5ec', route: '#ffffff', halo: '#157a4b' },
  hurry: { land: '#f2b632', park: '#e9ad2b', water: '#d9a02b', building: '#eaaf2e', road: '#f9dc8f', label: '#3d3214', route: '#14171c', halo: '#f2b632' },
  rush: { land: '#d92d2d', park: '#cf2a2a', water: '#b52323', building: '#cf3030', road: '#ea7272', label: '#ffe5e5', route: '#ffffff', halo: '#d92d2d' },
};
const ZOOM = 17;
const PITCH = 30;
const MIN_TURN = 2;
// Du är pilen. Den pekar alltid uppåt, det är kartan som vrids.
const ME = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2 4.5 21 12 17l7.5 4z"/></svg>';
const EMPTY = { type: 'FeatureCollection', features: [] };
const PAINTS = [
  ['background', 'background-color', 'land'],
  ['park', 'fill-color', 'park'],
  ['water', 'fill-color', 'water'],
  ['building', 'fill-color', 'building'],
  ['road', 'line-color', 'road'],
  ['road-name', 'text-color', 'label'],
  ['road-name', 'text-halo-color', 'halo'],
  ['route', 'line-color', 'route'],
  ['station', 'circle-color', 'route'],
  ['station', 'circle-stroke-color', 'halo'],
  ['station-name', 'text-color', 'route'],
  ['station-name', 'text-halo-color', 'halo'],
];

let map = null; // sätts först när kartan är klar att rita på
let ready = null;
let me = null;
let placed = false;

function loadLibrary() {
  if (window.maplibregl) return Promise.resolve();
  const css = document.createElement('link');
  css.rel = 'stylesheet';
  css.href = 'vendor/maplibre-gl.css';
  document.head.append(css);
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'vendor/maplibre-gl.js';
    script.onload = resolve;
    script.onerror = reject;
    document.head.append(script);
  });
}

function style(theme) {
  const colors = THEMES[theme];
  const tiles = { source: 'tiles' };
  return {
    version: 8,
    glyphs: GLYPHS,
    sources: {
      tiles: { type: 'vector', url: TILES },
      route: { type: 'geojson', data: EMPTY },
      station: { type: 'geojson', data: EMPTY },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': colors.land } },
      { ...tiles, id: 'park', type: 'fill', 'source-layer': 'park', paint: { 'fill-color': colors.park } },
      { ...tiles, id: 'water', type: 'fill', 'source-layer': 'water', paint: { 'fill-color': colors.water } },
      { ...tiles, id: 'building', type: 'fill', 'source-layer': 'building', minzoom: 14, paint: { 'fill-color': colors.building } },
      {
        ...tiles,
        id: 'road',
        type: 'line',
        'source-layer': 'transportation',
        filter: ['!in', 'class', 'rail', 'transit', 'ferry'],
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': colors.road,
          'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 12, 0.6, 17, 6],
        },
      },
      {
        ...tiles,
        id: 'road-name',
        type: 'symbol',
        'source-layer': 'transportation_name',
        minzoom: 14,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Regular'],
          'text-size': 13,
        },
        paint: { 'text-color': colors.label, 'text-halo-color': colors.halo, 'text-halo-width': 1.5 },
      },
      {
        id: 'route',
        type: 'line',
        source: 'route',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': colors.route, 'line-width': 6 },
      },
      {
        id: 'station',
        type: 'circle',
        source: 'station',
        paint: {
          'circle-radius': 9, 'circle-color': colors.route, 'circle-stroke-color': colors.halo, 'circle-stroke-width': 3,
        },
      },
      {
        id: 'station-name',
        type: 'symbol',
        source: 'station',
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 15,
          'text-offset': [0, 1.3],
          'text-anchor': 'top',
        },
        paint: { 'text-color': colors.route, 'text-halo-color': colors.halo, 'text-halo-width': 2 },
      },
    ],
  };
}

const point = ({ lat, lon }, properties = {}) => ({
  type: 'Feature', properties, geometry: { type: 'Point', coordinates: [lon, lat] },
});

async function createMap(container, theme) {
  await loadLibrary();
  const created = new window.maplibregl.Map({
    container,
    style: style(theme),
    center: [18.0686, 59.3293],
    zoom: 14,
    dragPan: false,
    dragRotate: false,
    keyboard: false,
    touchPitch: false,
    attributionControl: { compact: false },
  });
  // Du stannar i bild: det enda man kan göra med fingrarna är att zooma runt sig själv.
  created.touchZoomRotate.disableRotation();
  created.touchZoomRotate.enable({ around: 'center' });
  created.scrollZoom.enable({ around: 'center' });
  await new Promise((resolve) => { created.once('load', resolve); });
  const element = document.createElement('div');
  element.id = 'walk-me';
  element.innerHTML = ME;
  me = new window.maplibregl.Marker({ element, pitchAlignment: 'map', rotationAlignment: 'viewport' })
    .setLngLat(created.getCenter())
    .addTo(created);
  map = created;
}

export async function openMap(container, theme) {
  placed = false;
  ready ??= createMap(container, theme).catch((error) => {
    ready = null;
    throw error;
  });
  await ready;
  map.resize();
  themeMap(theme);
}

export function themeMap(theme) {
  if (!map) return;
  for (const [layer, property, color] of PAINTS) map.setPaintProperty(layer, property, THEMES[theme][color]);
}

// Kartan följer användaren i första person: det du har framför dig är uppåt på skärmen.
export function followMe(position, bearing) {
  if (!map) return;
  const center = [position.lon, position.lat];
  me.setLngLat(center);
  const view = { center, bearing, pitch: PITCH };
  if (!placed) {
    placed = true;
    map.jumpTo({ ...view, zoom: ZOOM });
    return;
  }
  const turned = Math.abs(((bearing - map.getBearing() + 540) % 360) - 180);
  const moved = map.getCenter().distanceTo(new window.maplibregl.LngLat(...center));
  // Kompassen darrar hela tiden, och en ny rörelse mitt i en nypning skulle avbryta den.
  if ((turned < MIN_TURN && moved < 1) || map.isZooming()) return;
  map.easeTo({ ...view, duration: 250, easing: (t) => t });
}

export function drawRoute(coordinates, station) {
  if (!map) return;
  map.getSource('route').setData({
    type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates },
  });
  map.getSource('station').setData(point(station, { name: station.name }));
}
