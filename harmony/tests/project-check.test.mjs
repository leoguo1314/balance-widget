import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const privateValue = 'PRIVATE_SIGNING_SENTINEL_$string:password';
const ignored = new Set(['.hvigor', '.idea', 'oh_modules', 'node_modules', 'build', 'build-logs']);
const parser = [
  process.env.DEVECO_JSON5_MODULE,
  process.env.DEVECO_COMMANDLINE_HOME && join(process.env.DEVECO_COMMANDLINE_HOME, 'hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'),
  'D:/HarmonyosDevTools/command-line-tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js',
  'D:/HarmonyosDevTools/DevEco Studio/tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'
].find(path => path && existsSync(path));
const localOptions = { skip: parser ? false : 'Official DevEco JSON5 parser is unavailable; default CI checks use only Node.js.' };

function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'balance-project-check-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const root = join(directory, 'harmony');
  cpSync(project, root, { recursive: true, filter: path => {
    const segments = relative(project, path).split(/[\\/]/);
    return !segments.some(part => ignored.has(part)) && path !== join(project, 'build-profile.json5') &&
      !basename(path).endsWith('.local.json5') && basename(path) !== 'signing.local.json';
  } });
  const profile = { app: { signingConfigs: [], products: [{ name: 'default', compileSdkVersion: '26.0.0',
    targetSdkVersion: '26.0.0', compatibleSdkVersion: '26.0.0', runtimeOS: 'HarmonyOS' }],
    buildModeSet: [{ name: 'debug' }, { name: 'release' }] }, modules: [{ name: 'entry', srcPath: './entry',
    targets: [{ name: 'default', applyToProducts: ['default'] }] }] };
  const profilePath = join(root, 'build-profile.json5');
  const save = () => writeFileSync(profilePath, JSON.stringify(profile, null, 2));
  save();
  const run = (args = []) => spawnSync(process.execPath, [join(root, 'tools/check-project.mjs'), ...args], { encoding: 'utf8' });
  const sign = () => {
    profile.app.signingConfigs = [{ name: 'private-debug', type: 'HarmonyOS', material: {
      storePassword: privateValue, keyPassword: privateValue, certpath: 'private.cer', profile: 'private.p7b',
      storeFile: 'private.p12', keyAlias: 'debug', signAlg: 'SHA256withECDSA' } }];
    profile.app.products[0].signingConfig = 'private-debug';
    save();
  };
  return { root, profile, profilePath, save, run, sign };
}

function output(result) { return result.stdout + result.stderr; }
function assertPrivate(result) { assert.ok(!output(result).includes(privateValue), 'Signing values must not appear in checker output.'); }

test('CI checker remains dependency-free and skips private local signing files', t => {
  const f = fixture(t);
  writeFileSync(join(f.root, 'signing.local.json'), privateValue);
  writeFileSync(join(f.root, 'debug.local.json5'), privateValue);
  mkdirSync(join(f.root, '.idea'));
  writeFileSync(join(f.root, '.idea/private.json5'), privateValue);
  const result = f.run();
  assert.equal(result.status, 0, output(result));
  assert.match(result.stdout, /unsigned committed source \/ strict JSON/);
  assertPrivate(result);
});

test('CI checker rejects signing configurations without revealing material', t => {
  const f = fixture(t);
  f.sign();
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(output(result), /Committed source must contain no signing/);
  assertPrivate(result);
});

test('JSON parse failures do not echo private configuration values', t => {
  const f = fixture(t);
  writeFileSync(f.profilePath, `{ "app": { "storePassword": "${privateValue}", BROKEN } }`);
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(output(result), /Invalid strict JSON/);
  assertPrivate(result);
});

test('private local signing accepts official JSON5 syntax while preserving resource guards', localOptions, t => {
  const f = fixture(t);
  f.sign();
  writeFileSync(f.profilePath, '// DevEco local configuration\n' + readFileSync(f.profilePath, 'utf8').replace('"app":', 'app:'));
  const result = f.run(['--local-signing', '--json5-module', parser]);
  assert.equal(result.status, 0, output(result));
  assert.match(result.stdout, /private local signing \/ JSON5/);
  assertPrivate(result);
  writeFileSync(join(f.root, 'AppScope/resources/base/element/string.json'), JSON.stringify({ string: [] }));
  writeFileSync(join(f.root, 'entry/src/main/resources/base/element/string.json'), JSON.stringify({ string: [] }));
  const missing = f.run(['--local-signing', '--json5-module', parser]);
  assert.notEqual(missing.status, 0);
  assert.match(output(missing), /missing \$string:/);
  assertPrivate(missing);
});

test('private local signing requires an existing selected configuration', localOptions, t => {
  const f = fixture(t);
  const result = f.run(['--local-signing', '--json5-module', parser]);
  assert.notEqual(result.status, 0);
  assert.match(output(result), /Local signing requires an existing/);
  f.sign();
  f.profile.app.products[0].signingConfig = 'missing';
  f.save();
  const missing = f.run(['--local-signing', '--json5-module', parser]);
  assert.notEqual(missing.status, 0);
  assert.match(output(missing), /must select an existing local signing/);
  assertPrivate(missing);
});

test('private local signing still enforces API 26 and network guards', localOptions, t => {
  const f = fixture(t);
  f.sign();
  f.profile.app.products[0].targetSdkVersion = '25.0.0';
  f.save();
  const api = f.run(['--local-signing', '--json5-module', parser]);
  assert.notEqual(api.status, 0);
  assertPrivate(api);
  f.profile.app.products[0].targetSdkVersion = '26.0.0';
  f.save();
  const networkPath = join(f.root, 'entry/src/main/ets/platform/NetClient.ets');
  writeFileSync(networkPath, readFileSync(networkPath, 'utf8').replace('maxRedirects: 0', 'maxRedirects: 1'));
  const network = f.run(['--local-signing', '--json5-module', parser]);
  assert.notEqual(network.status, 0);
  assertPrivate(network);
});
