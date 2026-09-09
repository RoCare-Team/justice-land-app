// Checks that every backend path lib/core/network/endpoints.dart names is a
// route that actually exists in the web project, and that the method the app
// uses is one that route exports.
//
//   node tool/check_api_contract.mjs [path-to-web-repo]
//
// The app has no backend of its own, so "does this endpoint exist" is a
// question with a definite answer: it is a file under src/app/api. This reads
// both sides and reports anything the app calls that the server does not
// answer — the failure that otherwise shows up as a 404 on a phone, months
// later, in whichever screen nobody opened during testing.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const webRoot = resolve(
  process.argv[2] || '../../legal-care-india'
);
const apiRoot = join(webRoot, 'src/app/api');

/** Every route.js under src/app/api, as a URL path plus its exported methods. */
function routes(dir, prefix = '') {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      out.push(...routes(full, `${prefix}/${entry}`));
    } else if (entry === 'route.js') {
      const src = readFileSync(full, 'utf8');
      const methods = [...src.matchAll(/export async function ([A-Z]+)/g)].map((m) => m[1]);
      out.push({ path: `/api${prefix}`, methods });
    }
  }
  return out;
}

const server = routes(apiRoot);

/** A route path matches a called path when the dynamic segments line up. */
function find(called) {
  const want = called.split('/').filter(Boolean);
  // Prefer a literal match, so /api/advocates/nearby is not read as a [slug].
  const literal = server.find((r) => r.path === called);
  if (literal) return literal;
  return server.find((r) => {
    const have = r.path.split('/').filter(Boolean);
    if (have.length !== want.length) return false;
    return have.every((seg, i) => seg.startsWith('[') || seg === want[i]);
  });
}

const dart = readFileSync('lib/core/network/endpoints.dart', 'utf8');

// The two forms endpoints.dart declares: a const string, and a one-line
// function that interpolates a single segment. An interpolated segment becomes
// the placeholder `X`, which `find` then matches against a `[slug]`.
const segment = (p) => p.replace(/\$\{?\w+\}?/g, 'X');

/** member name → the path it names. */
const declared = new Map();
for (const m of dart.matchAll(
  /static\s+(?:const\s+String|String)\s+(\w+)[^=]*=>?\s*'(\/api\/[^']*)'/g
)) {
  declared.set(m[1], segment(m[2]));
}

const called = new Set(declared.values());
// Any path written somewhere other than a declaration still has to exist.
for (const m of dart.matchAll(/'(\/api\/[^']*)'/g)) called.add(segment(m[1]));

// Which HTTP methods the app actually sends to each path, read off the calls
// in the service layer — an endpoint whose route exists but exports no GET is
// still a 405 the day someone opens that screen.
const services = readdirSync('lib/services')
  .map((f) => readFileSync(join('lib/services', f), 'utf8'))
  .join('\n');

const used = new Map();
for (const m of services.matchAll(/_api\.(get|post|put|patch|delete)\(\s*Endpoints\.(\w+)/g)) {
  const [, verb, name] = m;
  const path = declared.get(name);
  if (!path) continue;
  if (!used.has(path)) used.set(path, new Set());
  used.get(path).add(verb.toUpperCase());
}

let bad = 0;
for (const path of [...called].sort()) {
  const route = find(path);
  if (!route) {
    bad += 1;
    console.log(`MISSING  ${path}  — no route.js answers this`);
    continue;
  }
  const verbs = [...(used.get(path) || [])];
  const unsupported = verbs.filter((v) => !route.methods.includes(v));
  if (unsupported.length) {
    bad += 1;
    console.log(
      `METHOD   ${path}  — app sends ${unsupported.join(', ')}; route exports ${route.methods.join(', ')}`
    );
  } else {
    console.log(`ok       ${path.padEnd(38)} ${(verbs.join(',') || '—').padEnd(12)} → ${route.path}`);
  }
}

console.log(
  bad
    ? `\n${bad} endpoint(s) the app calls are not served by the web backend`
    : `\nall ${called.size} endpoints resolve to a route in ${webRoot}`
);
process.exit(bad ? 1 : 0);
