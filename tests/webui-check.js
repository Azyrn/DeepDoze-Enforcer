'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'webroot/index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'webroot/style.css'), 'utf8');
const js = fs.readFileSync(path.join(root, 'webroot/app.js'), 'utf8');

function fail(message) {
  process.stderr.write('WebUI check failed: ' + message + '\n');
  process.exit(1);
}

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
const duplicateIds = ids.filter((id, index) => ids.indexOf(id) !== index);
if (duplicateIds.length) fail('duplicate IDs: ' + [...new Set(duplicateIds)].join(', '));

const idSet = new Set(ids);
const jsIdRefs = [...js.matchAll(/\$\('([^']+)'\)/g)].map((match) => match[1]);
const missingIds = [...new Set(jsIdRefs.filter((id) => !idSet.has(id)))];
if (missingIds.length) fail('JavaScript references missing IDs: ' + missingIds.join(', '));

const requiredIds = [
  'themeToggle', 'master', 'statusband', 'avgma', 'modeGroup',
  'cfgDoze', 'cfgCpu', 'appsearch', 'applist', 'logtoggle', 'logview'
];
const missingRequired = requiredIds.filter((id) => !idSet.has(id));
if (missingRequired.length) fail('missing required controls: ' + missingRequired.join(', '));

if (!css.includes(':root') || !css.includes('html[data-theme="dark"]')) {
  fail('light/dark theme tokens are incomplete');
}
if (!css.includes('--text: #171b18')) fail('light theme does not use near-black primary text');

const openBraces = (css.match(/{/g) || []).length;
const closeBraces = (css.match(/}/g) || []).length;
if (openBraces !== closeBraces) fail('unbalanced CSS blocks');

const externalAssets = [...html.matchAll(/<(?:script|link)[^>]+(?:src|href)="(https?:\/\/[^"]+)"/gi)];
if (externalAssets.length) fail('external runtime assets are not allowed');

const sandbox = { window: {}, document: {}, navigator: { language: 'en' } };
vm.runInNewContext(fs.readFileSync(path.join(root, 'webroot/i18n.js'), 'utf8'), sandbox);
const { DD_I18N: i18n, DD_LANGS: langs } = sandbox.window;
if (!i18n || !langs || !i18n.en) fail('webroot/i18n.js does not define DD_I18N/DD_LANGS');
if (!html.includes('<script src="i18n.js"></script>')) fail('index.html does not load i18n.js');
const baseKeys = (dict) => new Set(Object.keys(dict).filter((key) => !key.includes('#')));
const enKeys = baseKeys(i18n.en);
const usedKeys = new Set([
  ...[...html.matchAll(/data-i18n(?:-placeholder|-aria|-title)?="([^"]+)"/g)].map((match) => match[1]),
  ...[...js.matchAll(/\bt\('([^']+)'/g)].map((match) => match[1]).filter((key) => !key.endsWith('.'))
]);
const unknown = [...usedKeys].filter((key) => !enKeys.has(key));
if (unknown.length) fail('keys used but not translated: ' + unknown.join(', '));
const placeholders = (text) => [...text.matchAll(/\{\w+\}/g)].map((match) => match[0]).sort().join();
langs.forEach(({ code }) => {
  const dict = i18n[code];
  if (!dict) fail('no translations for ' + code);
  const keys = baseKeys(dict);
  const missing = [...enKeys].filter((key) => !keys.has(key));
  const extra = [...keys].filter((key) => !enKeys.has(key));
  if (missing.length) fail(code + ' translations missing: ' + missing.join(', '));
  if (extra.length) fail(code + ' has unknown keys: ' + extra.join(', '));
  Object.keys(dict).forEach((key) => {
    if (placeholders(dict[key]) !== placeholders(i18n.en[key.split('#')[0]])) fail(code + ' ' + key + ' placeholders differ from English');
  });
});

process.stdout.write('WebUI structure, theme, and control bindings passed.\n');
