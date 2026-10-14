'use strict';

// Saves a whitelist the way the WebUI does, then reloads it through the real
// APPS_CMD + parseApps, and checks that every package survives the round trip.

const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { execFileSync, spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const js = fs.readFileSync(path.join(root, 'webroot/app.js'), 'utf8');

function fail(message) {
  process.stderr.write('Whitelist round-trip failed: ' + message + '\n');
  process.exit(1);
}

function grab(re, label) {
  const m = js.match(re);
  if (!m) fail('could not locate ' + label + ' in app.js');
  return m[1];
}

const appsCmd = grab(/const APPS_CMD = `([\s\S]*?)`\.trim\(\);/, 'APPS_CMD');
const saveTpl = grab(/async function saveWL\(\) \{[\s\S]*?const cmd = `([\s\S]*?)`\.trim\(\);/, 'saveWL command');
const parseSrc = grab(/(function parseApps\(stdout\) \{[\s\S]*?\n  \})\n/, 'parseApps');
const shqSrc = grab(/(const shq = [^\n]+)/, 'shq');
const b64Src = grab(/(const b64 = [^\n]+)/, 'b64');
const reSrc = grab(/(const PKG_RE = [^\n]+)/, 'PKG_RE');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'deepdoze-wl-'));
try {
  const pkgs = ['com.google.android.dialer', 'com.radolyn.ayugram'];
  const sandbox = {
    btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
    unescape, encodeURIComponent, pkgs, state: {}
  };
  vm.createContext(sandbox);
  vm.runInContext(shqSrc + ';' + b64Src + ';' + reSrc + ';' + parseSrc +
    ';this.parseApps = parseApps; this.saveCmd = `' + saveTpl + '`;', sandbox);

  const save = sandbox.saveCmd.trim().replace('D=/data/adb/deepdoze', 'D=' + dir);
  const saved = execFileSync('sh', ['-c', save], { encoding: 'utf8' }).trim();
  if (saved !== 'ok') fail('save command did not report ok');

  const load = appsCmd.split('/data/adb/deepdoze').join(dir);
  // pm/dumpsys are absent off-device; only the stdout matters here.
  const loadApps = () => spawnSync('sh', ['-c', load], { encoding: 'utf8' }).stdout;
  sandbox.parseApps(loadApps());
  const got = [...sandbox.state.protected].sort();
  if (got.join() !== pkgs.join()) fail('expected ' + pkgs.join(', ') + ' but reloaded ' + got.join(', '));

  // Files written by older versions have no trailing newline; they must still load fully.
  fs.writeFileSync(path.join(dir, 'whitelist'), pkgs.join('\n'));
  sandbox.parseApps(loadApps());
  const legacy = [...sandbox.state.protected].sort();
  if (legacy.join() !== pkgs.join()) fail('legacy file reloaded as ' + legacy.join(', '));
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

process.stdout.write('Whitelist save/reload round trip passed.\n');
