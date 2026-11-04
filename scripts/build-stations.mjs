// Genererar data/metro.json från SL Transport (ingen API-nyckel behövs).
// Linjesträckningarna är handskrivna: API:et säger inte i vilken ordning
// stationerna ligger. Kör: node scripts/build-stations.mjs
import { writeFile } from 'node:fs/promises';

const BASE = 'https://transport.integration.sl.se/v1';

const greenWest = ['Hässelby strand', 'Hässelby gård', 'Johannelund', 'Vällingby', 'Råcksta', 'Blackeberg', 'Islandstorget', 'Ängbyplan', 'Åkeshov', 'Brommaplan', 'Abrahamsberg', 'Stora mossen', 'Alvik', 'Kristineberg', 'Thorildsplan', 'Fridhemsplan', 'S:t Eriksplan', 'Odenplan', 'Rådmansgatan', 'Hötorget', 'T-Centralen', 'Gamla stan', 'Slussen', 'Medborgarplatsen', 'Skanstull', 'Gullmarsplan'];
const redCore = ['Liljeholmen', 'Hornstull', 'Zinkensdamm', 'Mariatorget', 'Slussen', 'Gamla stan', 'T-Centralen', 'Östermalmstorg'];
const blueCore = ['Kungsträdgården', 'T-Centralen', 'Rådhuset', 'Fridhemsplan', 'Stadshagen', 'Västra skogen'];

// Varje sträcka är en rak väg. Ett tåg mot D från A passerar H om H ligger
// mellan A och D på en sträcka som innehåller både A och D.
const routes = [
  { color: 'green', stations: [...greenWest, 'Skärmarbrink', 'Hammarbyhöjden', 'Björkhagen', 'Kärrtorp', 'Bagarmossen', 'Skarpnäck'] },
  { color: 'green', stations: [...greenWest, 'Skärmarbrink', 'Blåsut', 'Sandsborg', 'Skogskyrkogården', 'Tallkrogen', 'Gubbängen', 'Hökarängen', 'Farsta', 'Farsta strand'] },
  { color: 'green', stations: [...greenWest, 'Globen', 'Enskede gård', 'Sockenplan', 'Svedmyra', 'Stureby', 'Bandhagen', 'Högdalen', 'Rågsved', 'Hagsätra'] },
  { color: 'red', stations: ['Norsborg', 'Hallunda', 'Alby', 'Fittja', 'Masmo', 'Vårby gård', 'Vårberg', 'Skärholmen', 'Sätra', 'Bredäng', 'Mälarhöjden', 'Axelsberg', 'Örnsberg', 'Aspudden', ...redCore, 'Karlaplan', 'Gärdet', 'Ropsten'] },
  { color: 'red', stations: ['Fruängen', 'Västertorp', 'Hägerstensåsen', 'Telefonplan', 'Midsommarkransen', ...redCore, 'Stadion', 'Tekniska högskolan', 'Universitetet', 'Bergshamra', 'Danderyds sjukhus', 'Mörby centrum'] },
  { color: 'blue', stations: [...blueCore, 'Huvudsta', 'Solna strand', 'Sundbybergs centrum', 'Duvbo', 'Rissne', 'Rinkeby', 'Tensta', 'Hjulsta'] },
  { color: 'blue', stations: [...blueCore, 'Solna centrum', 'Näckrosen', 'Hallonbergen', 'Kista', 'Husby', 'Akalla'] },
];

async function getJson(path) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const res = await fetch(`${BASE}${path}`);
    if (res.ok) return res.json();
    if (res.status !== 429) throw new Error(`${path}: HTTP ${res.status}`);
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error(`${path}: fortsatt 429`);
}

const [sites, stopPoints] = [await getJson('/sites?expand=true'), await getJson('/stop-points')];
const metroPoints = stopPoints.filter((p) => p.stop_area.type === 'METROSTN');
const metroAreaNames = new Set(metroPoints.map((p) => p.stop_area.name));
const wanted = [...new Set(routes.flatMap((r) => r.stations))];

const stations = [];
const problems = [];
for (const name of wanted) {
  const points = metroPoints.filter((p) => p.stop_area.name === name);
  const areaIds = new Set(points.map((p) => p.stop_area.id));
  const linked = sites.filter((s) => s.stop_areas?.some((a) => areaIds.has(a)));
  // Vissa siter heter något annat än stationen (S:t Eriksplan = "Sankt Eriksplan").
  const sameName = linked.filter((s) => s.name === name);
  const candidates = sameName.length ? sameName : linked;
  if (!points.length || candidates.length !== 1) {
    problems.push(`${name}: ${points.length} perronger, ${candidates.length} siter (${candidates.map((c) => c.id)})`);
    continue;
  }
  const mean = (k) => points.reduce((sum, p) => sum + p[k], 0) / points.length;
  stations.push({ name, siteId: candidates[0].id, lat: +mean('lat').toFixed(5), lon: +mean('lon').toFixed(5) });
}
const unknown = [...metroAreaNames].filter((n) => !wanted.includes(n));
console.log(`${stations.length}/${wanted.length} stationer klara`);
console.log('Problem:', problems);
console.log('Hos SL men inte i linjekartan:', unknown);
if (problems.length) process.exit(1);
await writeFile(new URL('../data/metro.json', import.meta.url), JSON.stringify({ stations, routes }) + '\n');
