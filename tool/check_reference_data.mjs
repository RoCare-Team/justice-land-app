// Checks that lib/core/config/reference_data.dart still matches the web app's
// own src/data.
//
//   node tool/check_reference_data.mjs [path-to-web-repo]
//
// Those lists ship with the app rather than being fetched, so a lawyer filling
// in the registration wizard on a train is not blocked by a dropdown that
// needs the network. The cost of that is drift: a state list that disagrees
// with the server's is how a profile ends up with a city and a state that
// contradict each other, and nothing would complain at the time. This is what
// notices.
//
// Reads the practice areas from a running dev server (/api/services) because
// they are assembled from several files behind an import alias; everything
// else is read straight off disk.

import { readFileSync } from 'node:fs';

/** Windows path separators, as a file: URL wants them. */
const slashes = (p) => p.split('\\').join('/');

const repo = slashes(process.argv[2] || '../../legal-care-india');
const web = new URL(`${repo}/src/data/`, `file:///${slashes(process.cwd())}/`).href;
const api = process.env.API_BASE_URL || 'http://localhost:3000';
const { LANGUAGES, STATES } = await import(web + 'languages.js');
const { COURTS } = await import(web + 'courts.js');
const { STATES_CITIES } = await import(web + 'indiaLocations.js');
const services = (await (await fetch(`${api}/api/services`)).json()).services;

const dart = readFileSync('lib/core/config/reference_data.dart', 'utf8');

const STR = /'([^']*)'/g;

function block(marker) {
  const i = dart.indexOf(marker);
  if (i < 0) return [];
  const s = dart.indexOf('[', i);
  const e = dart.indexOf('];', s);
  return [...dart.slice(s, e).matchAll(STR)].map((m) => m[1]);
}

let drift = 0;
function cmp(label, a, b) {
  const same = JSON.stringify(a) === JSON.stringify(b);
  if (!same) drift += 1;
  console.log(`${same ? 'MATCH ' : 'DRIFT '} ${label}  (web ${a.length} / app ${b.length})`);
  if (!same) {
    console.log('   missing from app:', a.filter((x) => !b.includes(x)));
    console.log('   extra in app    :', b.filter((x) => !a.includes(x)));
  }
}

cmp('languages', LANGUAGES, block('static const List<String> languages'));
cmp('courts', COURTS, block('static const List<String> courts'));
cmp('states', STATES, block('static const List<String> states'));

const groups = [...dart.matchAll(/ServiceGroup\('([^']+)', '([^']+)'\)/g)];
cmp('service names', services.map((s) => s.name), groups.map((m) => m[1]));
cmp('service slugs', services.map((s) => s.slug), groups.map((m) => m[2]));

const start = dart.indexOf('statesCities = {');
const src = dart.slice(start, dart.indexOf('};', start));
const dartMap = {};
for (const m of src.matchAll(/'([^']+)':\s*\[([^\]]*)\]/g)) {
  dartMap[m[1]] = [...m[2].matchAll(STR)].map((x) => x[1]);
}
cmp('statesCities keys', Object.keys(STATES_CITIES), Object.keys(dartMap));
let bad = [];
for (const k of Object.keys(STATES_CITIES)) {
  if (JSON.stringify(STATES_CITIES[k]) !== JSON.stringify(dartMap[k] || [])) bad.push(k);
}
if (bad.length) drift += 1;
console.log(bad.length ? `DRIFT  city lists differ for: ${bad.join(', ')}` : 'MATCH  every state city list');
console.log(drift ? `\n${drift} section(s) drifted` : '\nreference_data.dart is in sync with the web data');
