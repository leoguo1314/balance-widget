import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const main = join(root, 'entry/src/main');
const read = path => readFileSync(join(root, path), 'utf8');
const json = path => JSON.parse(read(path));
function files(directory) {
  return readdirSync(directory, { withFileTypes: true })
    .filter(entry => !entry.isDirectory() || !['.hvigor', 'oh_modules', 'node_modules', 'build', 'build-logs'].includes(entry.name))
    .flatMap(entry => {
      const path = join(directory, entry.name);
      return entry.isDirectory() ? files(path) : [path];
    });
}

for (const file of files(root).filter(p => ['.json', '.json5'].includes(extname(p)))) JSON.parse(readFileSync(file, 'utf8'));
const product = json('build-profile.json5').app.products[0];
assert.equal(product.compileSdkVersion, '26.0.0');
assert.equal(product.targetSdkVersion, '26.0.0');
assert.equal(product.compatibleSdkVersion, '26.0.0');
assert.equal(product.runtimeOS, 'HarmonyOS');
assert.equal(json('hvigor/hvigor-config.json5').modelVersion, '26.0.0');
assert.equal(json('oh-package.json5').modelVersion, '26.0.0');
assert.deepEqual(json('build-profile.json5').app.signingConfigs, []);

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
  for (const match of readFileSync(file, 'utf8').matchAll(/\$(string|color|media|profile):([A-Za-z0-9_]+)/g)) {
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
console.log('Harmony project structure, resource references, API 26 configuration and transport guards passed. This is not an SDK build.');
