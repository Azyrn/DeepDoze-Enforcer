(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const shq = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
  const b64 = (s) => btoa(unescape(encodeURIComponent(s)));
  const PKG_RE = /^[a-zA-Z][a-zA-Z0-9_.]*$/;

  const ESSENTIALS = new Set([
    'com.google.android.deskclock', 'com.android.deskclock', 'com.sec.android.app.clockpackage',
    'com.oneplus.deskclock', 'com.coloros.alarmclock', 'com.miui.clock', 'com.android.alarmclock',
    'com.oppo.alarmclock', 'com.transsion.deskclock', 'com.topjohnwu.magisk', 'me.weishu.kernelsu',
    'me.bmax.apatch'
  ]);

  let hasRoot = true;

  function exec(cmd) {
    return new Promise((resolve) => {
      if (typeof ksu === 'undefined' || typeof ksu.exec !== 'function') {
        hasRoot = false;
        $('rootwarn').classList.add('show');
        resolve({ errno: -1, stdout: '', stderr: 'no root bridge' });
        return;
      }
      const name = 'cb_' + Date.now() + '_' + Math.floor(Math.random() * 1e6);
      window[name] = (errno, stdout, stderr) => {
        delete window[name];
        resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
      };
      try {
        ksu.exec(cmd, '{}', name);
      } catch (e) {
        delete window[name];
        resolve({ errno: -1, stdout: '', stderr: String(e) });
      }
    });
  }

  let snackTimer;
  function snack(msg) {
    const el = $('snackbar');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(snackTimer);
    snackTimer = setTimeout(() => el.classList.remove('show'), 2600);
  }

  const STATUS_CMD = `
D=/data/adb/deepdoze
[ -f $D/config ] && . $D/config 2>/dev/null
echo "mode=\${mode:-balanced}"
echo "cpu=\${enable_cpu_throttle:-true}"
echo "fdoze=\${enable_force_doze:-true}"
read A B C < $D/draw_off 2>/dev/null; echo "avg=$A"; echo "max=$B"; echo "min=$C"
RC=0; [ -f $D/restricted_pkgs ] && RC=$(grep -c . $D/restricted_pkgs 2>/dev/null); echo "restricted=$RC"
R=no; K=$(cat $D/service.pid 2>/dev/null); [ -n "$K" ] && kill -0 $K 2>/dev/null && R=yes; echo "running=$R"
echo "doze=$(dumpsys deviceidle get deep 2>/dev/null)"
B=/sys/class/power_supply/battery
echo "bstat=$(cat $B/status 2>/dev/null)"
echo "bpct=$(cat $B/capacity 2>/dev/null)"
echo "ver=$(grep -m1 '^version=' /data/adb/modules/deepdoze_enforcer/module.prop 2>/dev/null | cut -d= -f2)"
`.trim();

  const START_CMD = `
M=/data/adb/modules/deepdoze_enforcer
if command -v setsid >/dev/null 2>&1; then setsid sh $M/service.sh </dev/null >/dev/null 2>&1 & else nohup sh $M/service.sh </dev/null >/dev/null 2>&1 & fi
i=0; while [ $i -lt 5 ]; do sleep 1; K=$(cat /data/adb/deepdoze/service.pid 2>/dev/null); [ -n "$K" ] && kill -0 $K 2>/dev/null && { echo started; exit 0; }; i=$((i+1)); done
echo failed
`.trim();

  const STOP_CMD = `
P=/data/adb/deepdoze/service.pid
K=$(cat $P 2>/dev/null)
if [ -z "$K" ] || ! kill -0 $K 2>/dev/null; then echo stopped; exit 0; fi
kill $K 2>/dev/null
i=0; while [ $i -lt 6 ]; do sleep 1; kill -0 $K 2>/dev/null || { echo stopped; exit 0; }; i=$((i+1)); done
echo failed
`.trim();

  const APPS_CMD = `
echo "#USER"
pm list packages -3 2>/dev/null | sed 's/^package://'
echo "#SYS"
pm list packages -s 2>/dev/null | sed 's/^package://'
echo "#WL"
cat /data/adb/deepdoze/whitelist 2>/dev/null
echo "#DIW"
dumpsys deviceidle whitelist 2>/dev/null
`.trim();

  const LOG_CMD = 'tail -n 40 /data/adb/deepdoze/service.log 2>/dev/null';

  function parseKV(text) {
    const o = {};
    text.split('\n').forEach((l) => {
      const i = l.indexOf('=');
      if (i > 0) o[l.slice(0, i).trim()] = l.slice(i + 1).trim();
    });
    return o;
  }

  const NOISE = new Set(['android', 'app', 'apps', 'mobile', 'client', 'free', 'pro', 'lite', 'release', 'main', 'official', 'phone']);
  const TLD = new Set(['com', 'org', 'net', 'io', 'me', 'co', 'dev', 'app', 'in', 'cn', 'ru', 'de', 'fr', 'uk', 'tv', 'ai', 'sh', 'xyz', 'is', 'it', 'us', 'eu', 'kr', 'jp', 'tw', 'be', 'ch', 'se', 'nl', 'gov', 'edu']);

  const nameCache = new Map();
  function displayName(pkg) {
    let n = nameCache.get(pkg);
    if (n) return n;
    let parts = pkg.split('.');
    while (parts.length > 1 && TLD.has(parts[0])) parts = parts.slice(1);
    let words = parts.filter((w) => !NOISE.has(w.toLowerCase()));
    if (!words.length) words = [parts[parts.length - 1]];
    n = words.map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
    nameCache.set(pkg, n);
    return n;
  }

  function hue(pkg) {
    let h = 0;
    for (let i = 0; i < pkg.length; i++) h = (h * 31 + pkg.charCodeAt(i)) >>> 0;
    return h % 360;
  }

  function dozeLabel(s) {
    s = (s || '').trim();
    if (!s || s === 'unknown') return '';
    if (s === 'IDLE') return 'Dozing';
    if (s.indexOf('IDLE_MAINTENANCE') === 0) return 'Doze maintenance';
    if (s.indexOf('IDLE_PENDING') === 0 || s === 'SENSING' || s === 'LOCATING') return 'Entering doze';
    if (s === 'ACTIVE' || s === 'INACTIVE') return 'Awake';
    return s;
  }

  const state = {
    user: [], sys: [],
    protected: new Set(),
    osExempt: new Set(),
    filter: 'all',
    showSys: false,
    sort: 'az',
    q: '',
    selectMode: false,
    picked: new Set(),
    limit: 150,
    appsLoaded: false,
    restricted: null
  };

  function applyStatus(s) {
    $('ver').textContent = s.ver || '';

    const running = s.running === 'yes';
    const charging = s.bstat === 'Charging' || s.bstat === 'Full';
    const master = $('master');
    if (!masterBusy) {
      master.disabled = false;
      master.checked = running;
    }
    $('engineTag').textContent = running
      ? (charging ? 'Active — paused while charging' : 'Active — engages when you lock')
      : 'Engine off — nothing is being saved';

    const chips = [];
    chips.push('<span class="stchip ' + (running ? 'on' : 'off') + '"><span class="dot"></span>' + (running ? 'Running' : 'Stopped') + '</span>');
    const dl = dozeLabel(s.doze);
    if (dl) chips.push('<span class="stchip"><span class="dot"></span>' + esc(dl) + '</span>');
    const pct = parseInt(s.bpct, 10);
    if (!isNaN(pct)) chips.push('<span class="stchip"><span class="dot"></span>' + pct + '%' + (charging ? ' · charging' : '') + '</span>');
    const rc = parseInt(s.restricted, 10);
    if (!isNaN(rc)) {
      state.restricted = rc;
      chips.push('<span class="stchip"><span class="dot"></span>' + rc + ' apps paused at last lock</span>');
    }
    $('statusband').innerHTML = chips.join('');

    const avg = parseInt(s.avg, 10);
    const hero = $('hero');
    if (avg > 0) {
      $('avgma').innerHTML = avg + '<small>mA</small>';
      $('minma').textContent = parseInt(s.min, 10) > 0 ? s.min + ' mA' : '—';
      $('maxma').textContent = parseInt(s.max, 10) > 0 ? s.max + ' mA' : '—';
      $('drainSub').textContent = 'Measured from the battery while locked';
      $('drainMeta').textContent = 'last locked session';
    } else {
      $('avgma').innerHTML = '—<small>mA</small>';
      $('minma').textContent = '—';
      $('maxma').textContent = '—';
      $('drainSub').textContent = running ? 'Lock your phone to start measuring' : 'Turn the engine on, then lock your phone';
      $('drainMeta').textContent = '';
    }
    hero.classList.toggle('live', running && avg > 0);

    const mode = ['gentle', 'balanced', 'aggressive', 'off'].includes(s.mode) ? s.mode : 'balanced';
    const r = document.querySelector('input[name="mode"][value="' + mode + '"]');
    if (r) r.checked = true;
    $('cfgCpu').checked = s.cpu !== 'false';
    $('cfgDoze').checked = s.fdoze !== 'false';
  }

  async function refresh() {
    if (!hasRoot) return;
    const r = await exec(STATUS_CMD);
    if (r.errno !== 0) return;
    applyStatus(parseKV(r.stdout));
  }

  let cfgSaving = false;
  async function saveConfig() {
    const mode = (document.querySelector('input[name="mode"]:checked') || {}).value || 'balanced';
    const cpu = $('cfgCpu').checked ? 'true' : 'false';
    const fdoze = $('cfgDoze').checked ? 'true' : 'false';
    if (cfgSaving) return;
    cfgSaving = true;
    const cmd = `
D=/data/adb/deepdoze; mkdir -p $D
{ grep -vE '^(mode|enable_cpu_throttle|enable_force_doze)=' $D/config 2>/dev/null
  printf 'mode=%s\\nenable_cpu_throttle=%s\\nenable_force_doze=%s\\n' ${shq(mode)} ${shq(cpu)} ${shq(fdoze)}
} > $D/config.tmp && mv $D/config.tmp $D/config && echo ok
`.trim();
    const r = await exec(cmd);
    cfgSaving = false;
    snack((r.stdout || '').trim() === 'ok' ? 'Saved — applies at next lock' : 'Could not save settings');
  }

  let masterBusy = false;
  async function toggleMaster() {
    if (masterBusy) return;
    masterBusy = true;
    const master = $('master');
    const on = master.checked;
    master.disabled = true;
    $('engineTag').textContent = on ? 'Starting…' : 'Stopping…';
    const r = await exec(on ? START_CMD : STOP_CMD);
    const out = (r.stdout || '').trim();
    if (on) snack(out === 'started' ? 'Engine started' : 'Could not start the engine');
    else snack(out === 'stopped' ? 'Engine stopped — restrictions lifted' : 'Could not stop the engine');
    masterBusy = false;
    await refresh();
  }

  function parseApps(stdout) {
    let sect = null;
    state.user = [];
    state.sys = [];
    const wl = [];
    state.osExempt = new Set();
    (stdout || '').split('\n').forEach((l) => {
      l = l.trim();
      if (!l) return;
      if (l === '#USER' || l === '#SYS' || l === '#WL' || l === '#DIW') { sect = l; return; }
      if (sect === '#USER' && PKG_RE.test(l)) state.user.push(l);
      else if (sect === '#SYS' && PKG_RE.test(l)) state.sys.push(l);
      else if (sect === '#WL' && l.charAt(0) !== '#' && PKG_RE.test(l)) wl.push(l);
      else if (sect === '#DIW' && l.indexOf(',') > 0) {
        const p = l.split(',')[1];
        if (p && PKG_RE.test(p)) state.osExempt.add(p);
      }
    });
    state.protected = new Set(wl);
    state.appsLoaded = true;
  }

  async function loadApps() {
    const r = await exec(APPS_CMD);
    if (r.errno !== 0) {
      $('applist').innerHTML = '<div class="empty">Could not read the app list.</div>';
      return;
    }
    parseApps(r.stdout);
    renderApps();
  }

  function visibleApps() {
    let list = state.user.slice();
    if (state.showSys) list = list.concat(state.sys);
    state.protected.forEach((p) => list.push(p));
    list = [...new Set(list)];
    const q = state.q;
    if (q) {
      list = list.filter((p) => p.toLowerCase().includes(q) || displayName(p).toLowerCase().includes(q));
    }
    if (state.filter === 'protected') list = list.filter((p) => state.protected.has(p) || ESSENTIALS.has(p));
    else if (state.filter === 'paused') list = list.filter((p) => !state.protected.has(p) && !ESSENTIALS.has(p));
    list.sort((a, b) => {
      if (state.sort === 'prot') {
        const pa = state.protected.has(a) || ESSENTIALS.has(a);
        const pb = state.protected.has(b) || ESSENTIALS.has(b);
        if (pa !== pb) return pa ? -1 : 1;
      }
      return displayName(a).localeCompare(displayName(b)) || a.localeCompare(b);
    });
    return list;
  }

  function rowHTML(pkg) {
    const essential = ESSENTIALS.has(pkg);
    const prot = essential || state.protected.has(pkg);
    const name = displayName(pkg);
    const h = hue(pkg);
    const badges =
      (essential ? '<span class="mini always">always</span>' : '') +
      (state.osExempt.has(pkg) ? '<span class="mini os">OS-exempt</span>' : '');
    const picked = state.selectMode && state.picked.has(pkg);
    const avatar = '<span class="avatar" style="background:hsl(' + h + ',32%,24%)">' +
      (picked ? '✓' : esc(name.charAt(0))) + '</span>';
    const trail = state.selectMode ? '' :
      '<label class="sw" aria-label="Protect ' + esc(name) + '">' +
      '<input type="checkbox" role="switch" data-pkg="' + esc(pkg) + '"' + (prot ? ' checked' : '') + (essential ? ' disabled' : '') + '>' +
      '<span class="track"><span class="thumb"></span></span></label>';
    return '<div class="approw' + (picked ? ' picked' : '') + '" data-row="' + esc(pkg) + '">' +
      avatar +
      '<span class="body"><span class="nm"><span>' + esc(name) + '</span>' + badges + '</span>' +
      '<span class="pk">' + esc(pkg) + '</span></span>' +
      trail + '</div>';
  }

  function renderApps() {
    if (!state.appsLoaded) return;
    const list = visibleApps();
    const el = $('applist');
    if (!list.length) {
      el.innerHTML = '<div class="empty">' + (state.q ? 'No apps match “' + esc(state.q) + '”.' : 'No apps here.') + '</div>';
    } else {
      const shown = list.slice(0, state.limit);
      let html = shown.map(rowHTML).join('');
      if (list.length > state.limit) {
        html += '<button class="morebtn" id="morebtn">Show ' + (list.length - state.limit) + ' more</button>';
      }
      el.innerHTML = html;
    }
    updateMeta();
  }

  function updateMeta() {
    const protCount = new Set([...state.protected].filter((p) => PKG_RE.test(p))).size;
    $('appMeta').textContent = protCount + ' protected · ' + state.user.length + ' user apps';
    $('bulkCount').textContent = state.picked.size + ' selected';
  }

  let saveTimer, wlSaving = false, wlPending = false;
  function scheduleSaveWL() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveWL, 600);
  }

  async function saveWL() {
    if (wlSaving) { wlPending = true; return; }
    wlSaving = true;
    const pkgs = [...state.protected].filter((p) => PKG_RE.test(p) && !ESSENTIALS.has(p)).sort();
    const cmd = `
D=/data/adb/deepdoze; mkdir -p $D
printf '%s' ${shq(b64(pkgs.join('\n')))} | base64 -d > $D/whitelist && echo ok
`.trim();
    const r = await exec(cmd);
    wlSaving = false;
    if ((r.stdout || '').trim() === 'ok') snack('Saved — applies at next lock');
    else snack('Could not save protected apps');
    if (wlPending) { wlPending = false; saveWL(); }
  }

  function setSelectMode(on) {
    state.selectMode = on;
    state.picked.clear();
    $('selectChip').setAttribute('aria-pressed', on ? 'true' : 'false');
    $('bulkbar').classList.toggle('show', on);
    document.body.classList.toggle('selecting', on);
    renderApps();
  }

  function bulk(protect) {
    if (!state.picked.size) { snack('Tap apps to select them first'); return; }
    let n = 0;
    state.picked.forEach((p) => {
      if (ESSENTIALS.has(p)) return;
      if (protect && !state.protected.has(p)) { state.protected.add(p); n++; }
      if (!protect && state.protected.has(p)) { state.protected.delete(p); n++; }
    });
    setSelectMode(false);
    if (n) scheduleSaveWL();
    snack(n + (protect ? ' app' + (n === 1 ? '' : 's') + ' protected' : ' app' + (n === 1 ? '' : 's') + ' unprotected'));
  }

  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

  function relative(secs) {
    const m = Math.floor(secs / 60);
    if (m < 1) return 'just now';
    if (m < 60) return m + ' min ago';
    const h = Math.floor(m / 60);
    if (h < 24) return h + 'h ' + (m % 60) + 'm ago';
    return Math.floor(h / 24) + 'd ago';
  }

  function formatEvent(line) {
    const m = line.match(/^\[([^\]]+)\]\s*(.*)$/);
    const when = m ? m[1] : '';
    const msg = m ? m[2] : line;
    let cls = '', t = msg, d = '';
    let mm;
    if ((mm = msg.match(/service started.*mode=(\w+)/))) {
      cls = 'on'; t = 'Engine started'; d = cap(mm[1]) + ' mode · watching for lock';
    } else if (/cpu throttled/.test(msg)) {
      cls = 'on'; t = 'Entered deep sleep'; d = 'Phone locked — CPU eased back';
    } else if (/cpu restored/.test(msg)) {
      cls = 'off'; t = 'Unlocked'; d = 'Full performance restored';
    } else if ((mm = msg.match(/restricted (\d+) apps.*mode=(\w+)/))) {
      cls = 'on'; t = 'Paused ' + mm[1] + ' background app' + (mm[1] === '1' ? '' : 's');
      d = cap(mm[2]) + ' mode · protected apps kept running';
    } else if (/restored apps/.test(msg)) {
      cls = 'off'; t = 'Resumed background apps'; d = 'You unlocked your phone';
    } else if (/event feed confirmed/.test(msg)) {
      cls = 'on'; t = 'Instant unlock detection ready'; d = 'Reacting to screen events, not polling';
    } else if (/seeded whitelist/.test(msg)) {
      cls = 'on'; t = 'Default apps protected'; d = 'Dialer, SMS, keyboard and launcher kept awake';
    }
    let whenTxt = '';
    if (when) {
      const dt = new Date(when.replace(' ', 'T'));
      whenTxt = isNaN(dt) ? when : relative((Date.now() - dt.getTime()) / 1000);
    }
    return '<div class="ev"><span class="dot ' + cls + '"></span>' +
      '<div class="body"><div class="t">' + esc(t) + '</div>' +
      (d ? '<div class="d">' + esc(d) + '</div>' : '') + '</div>' +
      (whenTxt ? '<span class="when">' + esc(whenTxt) + '</span>' : '') + '</div>';
  }

  async function loadLog() {
    const r = await exec(LOG_CMD);
    const lines = (r.stdout || '').split('\n').map((l) => l.trim()).filter(Boolean);
    $('logview').innerHTML = lines.length
      ? lines.reverse().map(formatEvent).join('')
      : '<div class="empty">No activity yet — events appear after you lock your phone.</div>';
  }

  $('master').addEventListener('change', toggleMaster);
  $('modeGroup').addEventListener('change', saveConfig);
  $('cfgCpu').addEventListener('change', saveConfig);
  $('cfgDoze').addEventListener('change', saveConfig);

  let searchTimer;
  $('appsearch').addEventListener('input', (e) => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      state.q = e.target.value.trim().toLowerCase();
      state.limit = 150;
      renderApps();
    }, 120);
  });

  document.querySelectorAll('.chip[data-filter]').forEach((c) => {
    c.addEventListener('click', () => {
      state.filter = c.getAttribute('data-filter');
      state.limit = 150;
      document.querySelectorAll('.chip[data-filter]').forEach((x) => x.setAttribute('aria-pressed', x === c ? 'true' : 'false'));
      renderApps();
    });
  });

  $('sysChip').addEventListener('click', () => {
    state.showSys = !state.showSys;
    state.limit = 150;
    $('sysChip').setAttribute('aria-pressed', state.showSys ? 'true' : 'false');
    renderApps();
  });

  $('sortChip').addEventListener('click', () => {
    state.sort = state.sort === 'az' ? 'prot' : 'az';
    $('sortChip').textContent = state.sort === 'az' ? 'A–Z' : 'Protected first';
    $('sortChip').setAttribute('aria-pressed', state.sort === 'prot' ? 'true' : 'false');
    renderApps();
  });

  $('selectChip').addEventListener('click', () => setSelectMode(!state.selectMode));
  $('bulkProtect').addEventListener('click', () => bulk(true));
  $('bulkUnprotect').addEventListener('click', () => bulk(false));
  $('bulkCancel').addEventListener('click', () => setSelectMode(false));

  $('applist').addEventListener('change', (e) => {
    const cb = e.target;
    if (cb.type !== 'checkbox') return;
    const pkg = cb.getAttribute('data-pkg');
    if (!pkg) return;
    if (cb.checked) state.protected.add(pkg);
    else state.protected.delete(pkg);
    scheduleSaveWL();
    updateMeta();
  });

  $('applist').addEventListener('click', (e) => {
    const more = e.target.closest('#morebtn');
    if (more) {
      state.limit += 200;
      renderApps();
      return;
    }
    if (!state.selectMode) return;
    const row = e.target.closest('.approw');
    if (!row) return;
    const pkg = row.getAttribute('data-row');
    if (ESSENTIALS.has(pkg)) { snack('Always protected — can’t change'); return; }
    if (state.picked.has(pkg)) state.picked.delete(pkg);
    else state.picked.add(pkg);
    renderApps();
  });

  let logShown = false;
  $('logtoggle').addEventListener('click', () => {
    logShown = !logShown;
    $('logview').style.display = logShown ? 'block' : 'none';
    $('logtoggle').textContent = logShown ? 'Hide' : 'Show';
    if (logShown) loadLog();
  });

  document.addEventListener('click', (e) => {
    const a = e.target.closest('a[data-ext]');
    if (!a) return;
    e.preventDefault();
    exec('am start -a android.intent.action.VIEW -d ' + shq(a.getAttribute('data-ext')) + ' >/dev/null 2>&1');
  });

  refresh();
  loadApps();
  setInterval(() => {
    if (!document.hidden && !state.selectMode) refresh();
  }, 6000);
})();
