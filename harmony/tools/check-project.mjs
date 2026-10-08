import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const main = join(root, 'entry/src/main');
const read = path => readFileSync(join(root, path), 'utf8');
let localSigning = false;
let json5Module = '';
for (let index = 2; index < process.argv.length; index++) {
  const option = process.argv[index];
  if (option === '--local-signing') localSigning = true;
  else if (option === '--json5-module' && process.argv[index + 1]) json5Module = process.argv[++index];
  else throw new Error('Usage: check-project.mjs [--local-signing [--json5-module <official-toolchain-module>]]');
}
if (json5Module && !localSigning) throw new Error('--json5-module requires --local-signing. CI checks must use strict JSON.');
let parseJson5;
if (localSigning) {
  const candidates = [
    json5Module,
    process.env.DEVECO_JSON5_MODULE,
    process.env.DEVECO_COMMANDLINE_HOME && join(process.env.DEVECO_COMMANDLINE_HOME, 'hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'),
    process.env.DEVECO_STUDIO_HOME && join(process.env.DEVECO_STUDIO_HOME, 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'),
    'D:/HarmonyosDevTools/command-line-tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js',
    'D:/HarmonyosDevTools/DevEco Studio/tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'
  ];
  const parserPath = candidates.find(path => path && existsSync(path));
  if (!parserPath) throw new Error('Local signing requires the JSON5 library installed with DevEco/Hvigor. Pass --json5-module with its lib/index.js path.');
  try {
    const json5 = createRequire(import.meta.url)(resolve(parserPath));
    assert.equal(typeof json5.parse, 'function');
    parseJson5 = json5.parse;
  } catch (_) {
    throw new Error('Unable to load the official toolchain JSON5 parser.');
  }
}
const parsed = new Map();
function parseFile(file) {
  if (!parsed.has(file)) {
    try {
      const source = readFileSync(file, 'utf8');
      parsed.set(file, localSigning && extname(file) === '.json5' ? parseJson5(source) : JSON.parse(source));
    } catch (_) {
      // JSON parse errors can quote configuration values, including signing passwords.
      throw new Error(`Invalid ${localSigning && extname(file) === '.json5' ? 'JSON5' : 'strict JSON'} in ${file}. Configuration values are omitted.`);
    }
  }
  return parsed.get(file);
}
const json = path => parseFile(join(root, path));
function files(directory) {
  return readdirSync(directory, { withFileTypes: true })
    .filter(entry => !entry.name.endsWith('.local.json5') && entry.name !== 'signing.local.json')
    .filter(entry => !entry.isDirectory() || !['.hvigor', '.idea', 'oh_modules', 'node_modules', 'build', 'build-logs'].includes(entry.name))
    .flatMap(entry => {
      const path = join(directory, entry.name);
      return entry.isDirectory() ? files(path) : [path];
    });
}

for (const file of files(root).filter(p => ['.json', '.json5'].includes(extname(p)))) parseFile(file);
const app = json('build-profile.json5').app;
const product = app.products[0];
assert.equal(product.compileSdkVersion, '26.0.0');
assert.equal(product.targetSdkVersion, '26.0.0');
assert.equal(product.compatibleSdkVersion, '26.0.0');
assert.equal(product.runtimeOS, 'HarmonyOS');
assert.equal(json('hvigor/hvigor-config.json5').modelVersion, '26.0.0');
assert.equal(json('oh-package.json5').modelVersion, '26.0.0');
assert.ok(Array.isArray(app.signingConfigs), 'The app signing configuration must be an array. Values are omitted.');
if (localSigning) {
  assert.ok(app.signingConfigs.length > 0, 'Local signing requires an existing DevEco signing configuration. Values are omitted.');
  assert.ok(typeof product.signingConfig === 'string' && app.signingConfigs.some(config => config.name === product.signingConfig),
    'The default product must select an existing local signing configuration. Values are omitted.');
} else {
  assert.ok(app.signingConfigs.length === 0 && app.products.every(item => !item.signingConfig),
    'Committed source must contain no signing configurations or product signing references. Use --local-signing only for private local builds. Values are omitted.');
}

const module = json('entry/src/main/module.json5').module;
assert.deepEqual(module.deviceTypes, ['phone']);
assert.equal(module.mainElement, 'EntryAbility');
assert.deepEqual(module.requestPermissions.map(p => p.name), ['ohos.permission.INTERNET']);
for (const ability of [...module.abilities, ...module.extensionAbilities]) {
  assert.ok(existsSync(join(main, ability.srcEntry)), ability.srcEntry);
}
for (const page of json('entry/src/main/resources/base/profile/main_pages.json').src) {
  assert.ok(existsSync(join(main, 'ets', page + '.ets')), page);
}
const form = json('entry/src/main/resources/base/profile/form_config.json').forms[0];
assert.ok(existsSync(join(main, form.src)));
assert.equal(form.uiSyntax, 'arkts');
assert.deepEqual(form.supportDimensions, ['2*4']);
assert.equal(form.updateDuration, 1);
assert.ok(module.extensionAbilities.some(a => a.metadata.some(m => m.name === 'ohos.extension.form' && m.resource === '$profile:form_config')));

const resources = new Map();
for (const [kind, key, listKey] of [['string', 'string', 'string'], ['color', 'color', 'color']]) {
  const scope = json(`AppScope/resources/base/element/${key}.json`);
  const local = json(`entry/src/main/resources/base/element/${key}.json`);
  resources.set(kind, new Set([...scope[listKey], ...local[listKey]].map(e => e.name)));
}
resources.set('media', new Set(files(join(root, 'AppScope/resources/base/media')).map(p => basename(p, extname(p)))));
resources.set('profile', new Set(files(join(main, 'resources/base/profile')).map(p => basename(p, extname(p)))));
for (const file of files(root).filter(p => ['.json', '.json5'].includes(extname(p)))) {
  const data = parseFile(file);
  // Signing material is neither a resource-reference source nor diagnostic output.
  const resourceData = file === join(root, 'build-profile.json5') ? { ...data, app: { ...data.app, signingConfigs: [],
    products: data.app.products.map(({ signingConfig, ...item }) => item) } } : data;
  for (const match of JSON.stringify(resourceData).matchAll(/\$(string|color|media|profile):([A-Za-z0-9_]+)/g)) {
    assert.ok(resources.get(match[1]).has(match[2]), `${file}: missing ${match[0]}`);
  }
}
for (const file of files(join(main, 'ets')).filter(p => ['.ts', '.ets'].includes(extname(p)))) {
  const source = readFileSync(file, 'utf8');
  for (const match of source.matchAll(/from\s+['"](\.[^'"]+)['"]/g)) {
    const path = resolve(dirname(file), match[1]);
    assert.ok(['.ets', '.ts'].some(ext => existsSync(path + ext)), `${file}: missing ${match[1]}`);
  }
  assert.ok(!/console\.(?:log|debug|info|warn|error)/.test(source), `${file}: unexpected response/credential logging`);
}
const net = read('entry/src/main/ets/platform/NetClient.ets');
assert.match(net, /maxRedirects:\s*0/);
assert.match(net, /remoteValidation:\s*'system'/);
assert.match(net, /maxLimit:\s*1048576/);
assert.match(read('entry/src/main/ets/platform/Vault.ets'), /asset\.Tag\.SECRET/);
assert.match(read('entry/src/main/ets/platform/Repository.ets'), /a\.revision === b\.revision/);
assert.match(read('entry/src/main/ets/platform/HistoryStore.ets'), /account_id=\? AND revision=\?/);
console.log(`Harmony project structure, resource references, API 26 configuration and transport guards passed (${localSigning ? 'private local signing / JSON5' : 'unsigned committed source / strict JSON'}). This is not an SDK build.`);
