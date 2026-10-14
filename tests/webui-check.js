'use strict';

const fs = require('fs');
const path = require('path');

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

const dictKeys = (langName) => {
  const block = js.match(new RegExp('\\n    ' + langName + ': \\{([\\s\\S]*?)\\n    \\}'));
  if (!block) fail('missing ' + langName + ' translations');
  return new Set([...block[1].matchAll(/^\s*'([^']+)':/gm)].map((match) => match[1]));
};
const zhKeys = dictKeys('zh');
const enKeys = dictKeys('en');
const usedKeys = new Set([
  ...[...html.matchAll(/data-i18n(?:-placeholder|-aria|-title)?="([^"]+)"/g)].map((match) => match[1]),
  ...[...js.matchAll(/\bt\('([^']+)'/g)].map((match) => match[1])
]);
['zh', 'en'].forEach((langName) => {
  const keys = langName === 'zh' ? zhKeys : enKeys;
  const missing = [...usedKeys].filter((key) => !keys.has(key) && !key.endsWith('.'));
  if (missing.length) fail(langName + ' translations missing: ' + missing.join(', '));
});
const onlyOne = [...zhKeys].filter((key) => !enKeys.has(key)).concat([...enKeys].filter((key) => !zhKeys.has(key)));
if (onlyOne.length) fail('translation keys not in both languages: ' + onlyOne.join(', '));

process.stdout.write('WebUI structure, theme, and control bindings passed.\n');
