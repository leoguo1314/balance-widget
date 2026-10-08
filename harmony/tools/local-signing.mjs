import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import { dirname, join, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const clone = value => JSON.parse(JSON.stringify(value));
function appOf(profile) {
  if (!profile || !profile.app || !Array.isArray(profile.app.products) ||
    !profile.app.products.some(product => product.name === 'default')) {
    throw new Error('The project must contain the default app product. Configuration values are omitted.');
  }
  return profile.app;
}
function validateSigning(signingConfigs, products) {
  if (!Array.isArray(signingConfigs) || signingConfigs.length === 0 ||
    signingConfigs.some(config => !config || typeof config.name !== 'string' || !config.name)) {
    throw new Error('An existing named DevEco signing configuration is required. Configuration values are omitted.');
  }
  if (new Set(signingConfigs.map(config => config.name)).size !== signingConfigs.length) {
    throw new Error('Signing configuration names must be unique. Configuration values are omitted.');
  }
  if (!Array.isArray(products) || !products.some(product => product.name === 'default') ||
    products.some(product => !product || typeof product.name !== 'string' ||
      !signingConfigs.some(config => config.name === product.signingConfig))) {
    throw new Error('The default product must select an existing signing configuration. Configuration values are omitted.');
  }
}

export function captureSigning(profile) {
  const app = appOf(profile);
  if (!Array.isArray(app.signingConfigs) || app.signingConfigs.length === 0) {
    throw new Error('There is no local signing configuration to save. An existing private backup will not be overwritten.');
  }
  const products = app.products.filter(product => typeof product.signingConfig === 'string' && product.signingConfig)
    .map(product => ({ name: product.name, signingConfig: product.signingConfig }));
  // DevEco can generate the sole default signer without assigning it to its product.
  if (!products.some(product => product.name === 'default') && app.signingConfigs.length === 1 &&
    app.signingConfigs[0].name === 'default') {
    products.push({ name: 'default', signingConfig: 'default' });
  }
  validateSigning(app.signingConfigs, products);
  return { format: 1, signingConfigs: clone(app.signingConfigs), products };
}

export function publicProfile(profile) {
  const result = clone(profile);
  const app = appOf(result);
  app.signingConfigs = [];
  for (const product of app.products) delete product.signingConfig;
  return result;
}

export function applySigning(profile, backup) {
  if (!backup || backup.format !== 1) throw new Error('Unsupported private signing backup format. Configuration values are omitted.');
  validateSigning(backup.signingConfigs, backup.products);
  const result = publicProfile(profile);
  for (const reference of backup.products) {
    const product = result.app.products.find(item => item.name === reference.name);
    if (!product) throw new Error('A saved signing reference no longer matches a project product. Configuration values are omitted.');
    product.signingConfig = reference.signingConfig;
  }
  result.app.signingConfigs = clone(backup.signingConfigs);
  return result;
}

export function assertPublic(profile) {
  const app = appOf(profile);
  if (!Array.isArray(app.signingConfigs) || app.signingConfigs.length !== 0 ||
    app.products.some(product => Object.hasOwn(product, 'signingConfig'))) {
    throw new Error('The Git index contains local signing configuration. Run public and stage the unsigned build profile before committing. Values are omitted.');
  }
}

function git(root, args) {
  const result = spawnSync('git', ['-C', root, ...args], { encoding: 'utf8' });
  if (result.error) throw new Error('Git is required for local signing isolation checks.');
  return result;
}

function ignoredDirectory(root, privateDir) {
  if (git(root, ['rev-parse', '--is-inside-work-tree']).status !== 0) {
    throw new Error('Local signing tools require the project to belong to an existing Git repository.');
  }
  const path = relative(root, privateDir).replaceAll('\\', '/') + '/';
  if (git(root, ['check-ignore', '--quiet', '--no-index', '--', path]).status !== 0) {
    throw new Error('The private signing directory must be ignored by Git before any signing material is saved.');
  }
  const tracked = git(root, ['ls-files', '-z', '--', path]);
  if (tracked.status !== 0 || tracked.stdout.length > 0) {
    throw new Error('The private signing directory contains tracked files. Remove private material from the Git index before continuing.');
  }
}

function parser(modulePath) {
  const candidates = modulePath ? [modulePath] : [
    process.env.DEVECO_JSON5_MODULE,
    process.env.DEVECO_COMMANDLINE_HOME && join(process.env.DEVECO_COMMANDLINE_HOME, 'hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'),
    process.env.DEVECO_STUDIO_HOME && join(process.env.DEVECO_STUDIO_HOME, 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'),
    'D:/HarmonyosDevTools/command-line-tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js',
    'D:/HarmonyosDevTools/DevEco Studio/tools/hvigor/hvigor-ohos-plugin/node_modules/json5/lib/index.js'
  ];
  const path = candidates.find(candidate => candidate && existsSync(candidate));
  if (!path) throw new Error('The official DevEco/Hvigor JSON5 parser is required. Use --json5-module with its lib/index.js path.');
  try {
    const json5 = createRequire(import.meta.url)(resolve(path));
    if (typeof json5.parse !== 'function') throw new Error();
    return json5.parse;
  } catch (_) {
    throw new Error('Unable to load the official toolchain JSON5 parser.');
  }
}

function atomicWrite(destination, data, privateDir) {
  const temporary = join(privateDir, 'write-' + randomUUID() + '.tmp');
  try {
    writeFileSync(temporary, JSON.stringify(data, null, 2) + '\n', { encoding: 'utf8', mode: 0o600, flag: 'wx' });
    renameSync(temporary, destination);
  } catch (_) {
    throw new Error('Unable to save local signing configuration atomically. Configuration values are omitted.');
  } finally {
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

export function runAction(root, action, modulePath = '') {
  if (!['save', 'apply', 'public', 'check'].includes(action)) {
    throw new Error('Usage: local-signing.mjs save|apply|public|check [--json5-module <official-toolchain-module>]');
  }
  const profilePath = join(root, 'build-profile.json5');
  const privateDir = join(root, 'build-logs/local-signing');
  const backupPath = join(privateDir, 'signing.local.json');
  ignoredDirectory(root, privateDir);
  if (action === 'check') {
    const prefix = git(root, ['rev-parse', '--show-prefix']);
    if (prefix.status !== 0) throw new Error('Unable to locate the project Git repository.');
    const indexPath = prefix.stdout.trim() + 'build-profile.json5';
    const staged = git(root, ['show', ':' + indexPath]);
    if (staged.status !== 0) throw new Error('The public build profile is missing from the Git index.');
    let profile;
    try { profile = JSON.parse(staged.stdout); }
    catch (_) { throw new Error('The Git index build profile must be strict JSON. Configuration values are omitted.'); }
    assertPublic(profile);
    return 'Git index is strict JSON and contains no signing configuration; private signing files are ignored.';
  }
  const parseJson5 = parser(modulePath);
  let profile;
  try { profile = parseJson5(readFileSync(profilePath, 'utf8')); }
  catch (_) { throw new Error('Unable to read or parse build-profile.json5. Configuration values are omitted.'); }
  const app = appOf(profile);
  if (!Array.isArray(app.signingConfigs)) throw new Error('The app signing configuration must be an array. Configuration values are omitted.');
  const hasSigning = app.signingConfigs.length > 0;
  if (action === 'apply' && hasSigning) {
    throw new Error('Local signing is already present. Run save and public before applying the private backup, so current signing changes are preserved.');
  }
  mkdirSync(privateDir, { recursive: true });
  if (action === 'save' || (action === 'public' && hasSigning)) {
    atomicWrite(backupPath, captureSigning(profile), privateDir);
  }
  if (action === 'public') {
    const unsigned = publicProfile(profile);
    assertPublic(unsigned);
    atomicWrite(profilePath, unsigned, privateDir);
    return 'Unsigned strict JSON written. Existing signing material is preserved only in the ignored local backup.';
  }
  if (action === 'apply') {
    let backup;
    try { backup = JSON.parse(readFileSync(backupPath, 'utf8')); }
    catch (_) { throw new Error('Unable to read the ignored local signing backup. Configuration values are omitted.'); }
    atomicWrite(profilePath, applySigning(profile, backup), privateDir);
    return 'Private signing applied for DevEco/local builds. Run public before staging this build profile, and check before committing.';
  }
  return 'Local signing saved to the ignored backup. The project build profile was not changed.';
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const action = process.argv[2];
    let modulePath = '';
    if (process.argv.length > 3) {
      if (process.argv.length !== 5 || process.argv[3] !== '--json5-module') throw new Error('Use --json5-module <official-toolchain-module> after the action.');
      modulePath = process.argv[4];
    }
    const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
    console.log(runAction(root, action, modulePath));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
