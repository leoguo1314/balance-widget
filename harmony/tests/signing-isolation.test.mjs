import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { applySigning, assertPublic, captureSigning, publicProfile, runAction } from '../tools/local-signing.mjs';

const privateValue = 'MOCK_PRIVATE_SIGNING_VALUE';
const profile = () => ({ app: { signingConfigs: [{ name: 'default', type: 'HarmonyOS',
  material: { storePassword: privateValue, keyPassword: privateValue, storeFile: 'mock-private.p12', profile: 'mock-private.p7b' } }],
  products: [{ name: 'default', compileSdkVersion: '26.0.0', targetSdkVersion: '26.0.0', compatibleSdkVersion: '26.0.0', runtimeOS: 'HarmonyOS' }],
  buildModeSet: [{ name: 'debug' }] }, modules: [{ name: 'entry', srcPath: './entry' }] });

test('local backup adds the missing default product reference without mutating the source', () => {
  const source = profile();
  const backup = captureSigning(source);
  assert.deepEqual(backup.products, [{ name: 'default', signingConfig: 'default' }]);
  assert.ok(!Object.hasOwn(source.app.products[0], 'signingConfig'));
  assert.equal(backup.signingConfigs[0].material.storePassword, privateValue);
});

test('public profile removes signing material and every product reference while preserving SDK settings', () => {
  const source = profile();
  source.app.products[0].signingConfig = 'default';
  source.app.products.push({ name: 'secondary', signingConfig: 'default', targetSdkVersion: '26.0.0' });
  const result = publicProfile(source);
  assertPublic(result);
  assert.equal(result.app.products[0].targetSdkVersion, '26.0.0');
  assert.deepEqual(result.modules, source.modules);
  assert.ok(!JSON.stringify(result).includes(privateValue));
  assert.equal(source.app.signingConfigs.length, 1);
});

test('applying a private backup preserves current project changes', () => {
  const backup = captureSigning(profile());
  const current = publicProfile(profile());
  current.app.products[0].buildOption = { strictMode: { caseSensitiveCheck: true } };
  current.modules.push({ name: 'later', srcPath: './later' });
  const result = applySigning(current, backup);
  assert.equal(result.app.products[0].signingConfig, 'default');
  assert.deepEqual(result.app.products[0].buildOption, current.app.products[0].buildOption);
  assert.deepEqual(result.modules, current.modules);
  assert.equal(current.app.signingConfigs.length, 0);
});

test('capture refuses unsigned configurations, preserving any existing private backup', () => {
  assert.throws(() => captureSigning(publicProfile(profile())), /will not be overwritten/);
});

test('invalid or stale backup references fail without exposing private values', () => {
  const backup = captureSigning(profile());
  backup.products[0].signingConfig = privateValue;
  assert.throws(() => applySigning(publicProfile(profile()), backup), error => !error.message.includes(privateValue));
  const stale = captureSigning(profile());
  stale.products.push({ name: 'removed', signingConfig: 'default' });
  assert.throws(() => applySigning(publicProfile(profile()), stale), /no longer matches/);
});

test('public index audit rejects private material and leftover references', () => {
  assert.throws(() => assertPublic(profile()), /Git index contains local signing/);
  const unsigned = publicProfile(profile());
  unsigned.app.products[0].signingConfig = '';
  assert.throws(() => assertPublic(unsigned), /Git index contains local signing/);
});

const parser = [
  process.env.DEVECO_JSON5_MODULE,
  process.env.DEVECO_COMMANDLINE_HOME && join(process.env.DEVECO_COMMANDLINE_HOME, 'hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'),
  'D:/HarmonyosDevTools/command-line-tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js',
  'D:/HarmonyosDevTools/DevEco Studio/tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'
].find(path => path && existsSync(path));
const localOptions = { skip: parser && spawnSync('git', ['--version']).status === 0 ? false : 'Local DevEco JSON5/Git integration is unavailable; core isolation tests use only Node.js.' };

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'balance-signing-isolation-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = args => {
    const result = spawnSync('git', ['-C', root, ...args], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  };
  git(['init', '--quiet']);
  writeFileSync(join(root, '.gitignore'), 'build-logs/\n');
  writeFileSync(join(root, 'build-profile.json5'), JSON.stringify(publicProfile(profile()), null, 2));
  git(['add', '.gitignore', 'build-profile.json5']);
  return { root, git, profilePath: join(root, 'build-profile.json5'), backupPath: join(root, 'build-logs/local-signing/signing.local.json') };
}

test('save/public/apply keeps the Git index unsigned while restoring private IDE signing', localOptions, t => {
  const f = fixture(t);
  writeFileSync(f.profilePath, '// Local DevEco JSON5\n' + JSON.stringify(profile(), null, 2).replace('"app":', 'app:'));
  assert.ok(!runAction(f.root, 'save', parser).includes(privateValue));
  assert.equal(JSON.parse(readFileSync(f.backupPath)).signingConfigs[0].material.storePassword, privateValue);
  runAction(f.root, 'public', parser);
  assertPublic(JSON.parse(readFileSync(f.profilePath)));
  f.git(['add', 'build-profile.json5']);
  assert.match(runAction(f.root, 'check'), /strict JSON/);
  runAction(f.root, 'apply', parser);
  const signed = JSON.parse(readFileSync(f.profilePath));
  assert.equal(signed.app.products[0].signingConfig, 'default');
  assert.equal(signed.app.signingConfigs[0].material.storePassword, privateValue);
  assert.match(runAction(f.root, 'check'), /contains no signing/);
  assert.throws(() => runAction(f.root, 'apply', parser), /current signing changes are preserved/);
  f.git(['add', 'build-profile.json5']);
  assert.throws(() => runAction(f.root, 'check'), error => /Git index contains local signing/.test(error.message) && !error.message.includes(privateValue));
});

test('an unignored private directory is refused before any backup is created', localOptions, t => {
  const f = fixture(t);
  writeFileSync(join(f.root, '.gitignore'), '');
  writeFileSync(f.profilePath, JSON.stringify(profile()));
  assert.throws(() => runAction(f.root, 'save', parser), /must be ignored by Git/);
  assert.ok(!existsSync(f.backupPath));
});

test('local parse errors are sanitized and leave source and backup intact', localOptions, t => {
  const f = fixture(t);
  const broken = `{ app: { storePassword: '${privateValue}', BROKEN }`;
  writeFileSync(f.profilePath, broken);
  assert.throws(() => runAction(f.root, 'public', parser), error => /Configuration values are omitted/.test(error.message) && !error.message.includes(privateValue));
  assert.equal(readFileSync(f.profilePath, 'utf8'), broken);
  assert.ok(!existsSync(f.backupPath));
});
