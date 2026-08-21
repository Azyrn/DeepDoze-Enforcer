(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const shq = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
  const b64 = (s) => btoa(unescape(encodeURIComponent(s)));
  const PKG_RE = /^[a-zA-Z][a-zA-Z0-9_.]*$/;

  const I18N = {
    zh: {
      'brand.subtitle': '手机睡眠时的电池控制',

      'lang.to.zh': '切换到中文',
      'lang.to.en': '切换到英文',
      'theme.to.dark': '切换到深色主题',
      'theme.to.light': '切换到浅色主题',

      'rootwarn.title': '无法获取 Root 权限。',
      'rootwarn.body': '请从 KernelSU、APatch 或 MMRL 打开此页面，以便控制模块。',

      'engine.title': '睡眠引擎',
      'engine.label': '自动省电',
      'engine.checking': '正在检查引擎…',
      'engine.active': '已激活 — 锁定时生效',
      'engine.active.charging': '已激活 — 充电中暂停',
      'engine.off': '已关闭 — Android 电池管理仍生效',
      'engine.running': '运行中',
      'engine.stopped': '已停止',
      'engine.charging': '充电中',
      'engine.restricted': '{n} 个应用在上次锁定时被暂停',
      'engine.starting': '正在启动…',
      'engine.stopping': '正在停止…',
      'engine.started': '引擎已启动',
      'engine.stopped.msg': '引擎已停止 — 限制已解除',
      'engine.start.fail': '无法启动引擎',
      'engine.stop.fail': '无法停止引擎',

      'drain.title': '睡眠耗电',
      'drain.avg': '平均电流',
      'drain.best': '最低',
      'drain.highest': '最高',
      'drain.lock': '锁定手机开始测量',
      'drain.on': '开启引擎，然后锁定手机',
      'drain.measured': '锁定时从电池测量',
      'drain.last': '上次锁定会话',
      'drain.note': '请与您自己的基线对比。正常电流因设备、应用、信号和环境显示设置而异。',

      'restrict.title': '应用限制',
      'restrict.desc': '屏幕关闭时后台应用的处理方式。下次锁定时生效。',
      'restrict.aria': '应用限制模式',

      'mode.gentle': '温和',
      'mode.gentle.desc': '推迟后台任务。通知延迟的可能性最低。',
      'mode.balanced': '均衡',
      'mode.balanced.desc': '同时阻止后台活动。通知和同步可能会延迟到达。',
      'mode.aggressive': '激进',
      'mode.aggressive.desc': '强制停止空闲应用。部分通知需等到您打开应用。',
      'mode.off': '应用保持不变',
      'mode.off.desc': '不改变应用状态。下方启用时深度 Doze 仍可运行。',
      'mode.rec': '推荐',

      'system.title': '系统行为',
      'system.doze': '强制深度 Doze',
      'system.doze.desc': '屏幕关闭后进入 Android 最深度的空闲状态。',
      'system.cpu': '睡眠时限制 CPU',
      'system.cpu.exp': '实验性',
      'system.cpu.desc': '使用内核或性能管理器时请保持关闭。',
      'system.note': '解锁时恢复更改，充电或通话期间暂停。其他管理器设置的新值将被保留。',

      'apps.title': '受保护的应用',
      'apps.desc': '屏幕关闭时仍正常运行的应用。',
      'apps.search': '搜索应用或包名',
      'apps.filter.all': '全部',
      'apps.filter.protected': '受保护',
      'apps.filter.paused': '已限制',
      'apps.filter.sys': '系统应用',
      'apps.sort.az': 'A–Z',
      'apps.sort.prot': '受保护优先',
      'apps.select': '选择',
      'apps.loading': '正在加载应用…',
      'apps.filters.aria': '应用列表筛选',
      'apps.none': '这里没有应用。',
      'apps.nomatch': '没有匹配 “{q}” 的应用。',
      'apps.more': '显示另外 {n} 个',
      'apps.meta': '受保护 {a} 个 · {b} 个应用',
      'apps.loadfail': '无法读取应用列表。',
      'apps.always': '始终',
      'apps.osexempt': '系统豁免',
      'apps.protect.aria': '保护 {name}',
      'apps.bulkcount': '已选 {n} 个',
      'apps.bulkprotect': '保护',
      'apps.bulkunprotect': '取消保护',
      'apps.bulkcancel': '取消选择',
      'apps.select.first': '请先点击应用进行选择',
      'apps.bulk.protect': '已保护 {n} 个应用',
      'apps.bulk.unprotect': '已取消保护 {n} 个应用',
      'apps.always.msg': '始终受保护 — 无法更改',
      'apps.osexempt.msg': '受 Android 电池豁免保护',
      'apps.note': '时钟、闹钟和 root 管理器包始终受保护。Android 电池豁免应用会自动被尊重。Doze 本身可能仍会影响受保护的应用。',

      'activity.title': '最近活动',
      'activity.show': '显示',
      'activity.hide': '隐藏',
      'activity.empty': '暂无活动。锁定手机后会出现事件。',

      'save.ok': '已保存 — 下次锁定时生效',
      'save.fail': '无法保存设置',
      'wl.save.fail': '无法保存受保护的应用',

      'ev.start': '引擎已启动',
      'ev.start.d': '{mode} 模式 · 等待锁定',
      'ev.sleep': '进入深度睡眠',
      'ev.sleep.d': '手机已锁定 — CPU 已降低',
      'ev.unlock': '已解锁',
      'ev.unlock.d': '性能已完全恢复',
      'ev.paused': '已暂停 {n} 个后台应用',
      'ev.paused.d': '{mode} 模式 · 受保护的应用保持运行',
      'ev.resumed': '已恢复后台应用',
      'ev.resumed.d': '您已解锁手机',
      'ev.feed': '即时解锁检测已就绪',
      'ev.feed.d': '响应屏幕事件，而非轮询',
      'ev.seeded': '已保护默认应用',
      'ev.seeded.d': '拨号、短信、键盘和桌面保持唤醒',

      'time.justnow': '刚刚',
      'time.min': '{m} 分钟前',
      'time.hour': '{h} 小时 {m} 分钟前',
      'time.day': '{d} 天前',

      'doze.idle': '深度休眠中',
      'doze.maint': 'Doze 维护',
      'doze.entering': '正在进入 Doze',
      'doze.awake': '唤醒',

      'modename.gentle': '温和',
      'modename.balanced': '均衡',
      'modename.aggressive': '激进',
      'modename.off': '关闭',

      'footer.support': '支持'
    },
    en: {
      'brand.subtitle': 'Battery control while your phone sleeps',

      'lang.to.zh': 'Switch to Chinese',
      'lang.to.en': 'Switch to English',
      'theme.to.dark': 'Switch to dark theme',
      'theme.to.light': 'Switch to light theme',

      'rootwarn.title': 'Root access unavailable.',
      'rootwarn.body': 'Open this page from KernelSU, APatch, or MMRL so it can control the module.',

      'engine.title': 'Sleep engine',
      'engine.label': 'Save power automatically',
      'engine.checking': 'Checking engine…',
      'engine.active': 'Active — engages when you lock',
      'engine.active.charging': 'Active — paused while charging',
      'engine.off': 'Off — Android battery management still applies',
      'engine.running': 'Running',
      'engine.stopped': 'Stopped',
      'engine.charging': 'charging',
      'engine.restricted': '{n} apps paused at last lock',
      'engine.starting': 'Starting…',
      'engine.stopping': 'Stopping…',
      'engine.started': 'Engine started',
      'engine.stopped.msg': 'Engine stopped — restrictions lifted',
      'engine.start.fail': 'Could not start the engine',
      'engine.stop.fail': 'Could not stop the engine',

      'drain.title': 'Sleep drain',
      'drain.avg': 'Average current',
      'drain.best': 'Best',
      'drain.highest': 'Highest',
      'drain.lock': 'Lock your phone to start measuring',
      'drain.on': 'Turn the engine on, then lock your phone',
      'drain.measured': 'Measured from the battery while locked',
      'drain.last': 'Last locked session',
      'drain.note': 'Compare this reading with your own baseline. Normal current varies by device, apps, signal, and ambient display settings.',

      'restrict.title': 'App restriction',
      'restrict.desc': 'How background apps are treated while the screen is off. Applies at the next lock.',
      'restrict.aria': 'App restriction mode',

      'mode.gentle': 'Gentle',
      'mode.gentle.desc': 'Defers background work. Lowest chance of delayed notifications.',
      'mode.balanced': 'Balanced',
      'mode.balanced.desc': 'Also blocks background activity. Notifications and sync can arrive later.',
      'mode.aggressive': 'Aggressive',
      'mode.aggressive.desc': 'Force-stops idle apps. Some notifications wait until you open the app.',
      'mode.off': 'Apps unchanged',
      'mode.off.desc': 'Leaves app state alone. Deep Doze can still run when enabled below.',
      'mode.rec': 'Recommended',

      'system.title': 'System behavior',
      'system.doze': 'Force deep Doze',
      'system.doze.desc': 'Enter Android’s deepest idle state after the screen turns off.',
      'system.cpu': 'Limit CPU while asleep',
      'system.cpu.exp': 'Experimental',
      'system.cpu.desc': 'Leave off when using a kernel or performance manager.',
      'system.note': 'Changes are restored when you unlock, and paused during charging or calls. Newer values set by another manager are preserved.',

      'apps.title': 'Protected apps',
      'apps.desc': 'Apps that keep running normally while the screen is off.',
      'apps.search': 'Search apps or package names',
      'apps.filter.all': 'All',
      'apps.filter.protected': 'Protected',
      'apps.filter.paused': 'Restricted',
      'apps.filter.sys': 'System apps',
      'apps.sort.az': 'A–Z',
      'apps.sort.prot': 'Protected first',
      'apps.select': 'Select',
      'apps.loading': 'Loading apps…',
      'apps.filters.aria': 'App list filters',
      'apps.none': 'No apps here.',
      'apps.nomatch': 'No apps match “{q}”.',
      'apps.more': 'Show {n} more',
      'apps.meta': '{a} protected · {b} apps',
      'apps.loadfail': 'Could not read the app list.',
      'apps.always': 'always',
      'apps.osexempt': 'OS-exempt',
      'apps.protect.aria': 'Protect {name}',
      'apps.bulkcount': '{n} selected',
      'apps.bulkprotect': 'Protect',
      'apps.bulkunprotect': 'Unprotect',
      'apps.bulkcancel': 'Cancel selection',
      'apps.select.first': 'Tap apps to select them first',
      'apps.bulk.protect': 'Protected {n} app',
      'apps.bulk.unprotect': 'Unprotected {n} app',
      'apps.always.msg': 'Always protected — can’t change',
      'apps.osexempt.msg': 'Protected by Android’s battery exemption',
      'apps.note': 'Clock, alarm, and root-manager packages are always protected. Android battery-exempt apps are respected automatically. Doze itself may still affect protected apps.',

      'activity.title': 'Recent activity',
      'activity.show': 'Show',
      'activity.hide': 'Hide',
      'activity.empty': 'No activity yet. Events appear after you lock your phone.',

      'save.ok': 'Saved — applies at next lock',
      'save.fail': 'Could not save settings',
      'wl.save.fail': 'Could not save protected apps',

      'ev.start': 'Engine started',
      'ev.start.d': '{mode} mode · watching for lock',
      'ev.sleep': 'Entered deep sleep',
      'ev.sleep.d': 'Phone locked — CPU eased back',
      'ev.unlock': 'Unlocked',
      'ev.unlock.d': 'Full performance restored',
      'ev.paused': 'Paused {n} background app',
      'ev.paused.d': '{mode} mode · protected apps kept running',
      'ev.resumed': 'Resumed background apps',
      'ev.resumed.d': 'You unlocked your phone',
      'ev.feed': 'Instant unlock detection ready',
      'ev.feed.d': 'Reacting to screen events, not polling',
      'ev.seeded': 'Default apps protected',
      'ev.seeded.d': 'Dialer, SMS, keyboard and launcher kept awake',

      'time.justnow': 'just now',
      'time.min': '{m} min ago',
      'time.hour': '{h}h {m}m ago',
      'time.day': '{d}d ago',

      'doze.idle': 'Dozing',
      'doze.maint': 'Doze maintenance',
      'doze.entering': 'Entering doze',
      'doze.awake': 'Awake',

      'modename.gentle': 'Gentle',
      'modename.balanced': 'Balanced',
      'modename.aggressive': 'Aggressive',
      'modename.off': 'Off',

      'footer.support': 'Support'
    }
  };

  let lang = document.documentElement.dataset.lang === 'en' ? 'en' : 'zh';

  function t(key, vars) {
    let s = (I18N[lang] && I18N[lang][key]) || I18N.en[key] || key;
    if (vars) {
      Object.keys(vars).forEach((k) => { s = s.split('{' + k + '}').join(vars[k]); });
    }
    return s;
  }

  function applyStaticI18n() {
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      el.textContent = t(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
      el.setAttribute('placeholder', t(el.getAttribute('data-i18n-placeholder')));
    });
    document.querySelectorAll('[data-i18n-aria]').forEach((el) => {
      el.setAttribute('aria-label', t(el.getAttribute('data-i18n-aria')));
    });
  }

  function updateLangButton() {
    const b = $('langToggle');
    const to = lang === 'zh' ? 'en' : 'zh';
    b.textContent = to === 'zh' ? '文' : 'EN';
    b.setAttribute('aria-label', to === 'zh' ? t('lang.to.zh') : t('lang.to.en'));
    b.setAttribute('title', b.getAttribute('aria-label'));
  }

  const themeMedia = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  let savedTheme = null;
  try { savedTheme = localStorage.getItem('deepdoze-theme'); } catch (_) {}
  if (savedTheme !== 'light' && savedTheme !== 'dark') savedTheme = null;

  function applyTheme(theme, persist) {
    document.documentElement.dataset.theme = theme;
    const button = $('themeToggle');
    const next = theme === 'dark' ? 'light' : 'dark';
    const label = next === 'dark' ? t('theme.to.dark') : t('theme.to.light');
    button.setAttribute('aria-label', label);
    button.setAttribute('title', label);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', theme === 'dark' ? '#101413' : '#f5f7f5');
    if (persist) {
      savedTheme = theme;
      try { localStorage.setItem('deepdoze-theme', theme); } catch (_) {}
    }
  }

  applyTheme(savedTheme || (themeMedia && themeMedia.matches ? 'dark' : 'light'), false);
  updateLangButton();

  $('themeToggle').addEventListener('click', () => {
    const current = document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
    applyTheme(current === 'dark' ? 'light' : 'dark', true);
  });

  $('langToggle').addEventListener('click', () => setLang(lang === 'zh' ? 'en' : 'zh'));

  if (themeMedia && typeof themeMedia.addEventListener === 'function') {
    themeMedia.addEventListener('change', (event) => {
      if (!savedTheme) applyTheme(event.matches ? 'dark' : 'light', false);
    });
  }

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
        $('ver').textContent = '';
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
cfg() { sed -n "s/^\${1}=//p" $D/config 2>/dev/null | tail -n 1; }
mode=$(cfg mode); cpu=$(cfg enable_cpu_throttle); fdoze=$(cfg enable_force_doze)
echo "mode=\${mode:-gentle}"
echo "cpu=\${cpu:-false}"
echo "fdoze=\${fdoze:-true}"
read A B C < $D/draw_off 2>/dev/null; echo "avg=$A"; echo "max=$B"; echo "min=$C"
RC=0; [ -f $D/restricted_pkgs ] && RC=$(grep -c . $D/restricted_pkgs 2>/dev/null); echo "restricted=$RC"
R=no; M=/data/adb/modules/deepdoze_enforcer; K=$(cat $D/service.pid 2>/dev/null)
if [ -n "$K" ] && kill -0 $K 2>/dev/null; then
  C=$(tr '\\0' ' ' < /proc/$K/cmdline 2>/dev/null)
  case "$C" in *"$M/service.sh"*) R=yes ;; esac
fi
echo "running=$R"
echo "doze=$(dumpsys deviceidle get deep 2>/dev/null)"
B=/sys/class/power_supply/battery
echo "bstat=$(cat $B/status 2>/dev/null)"
echo "bpct=$(cat $B/capacity 2>/dev/null)"
echo "ver=$(grep -m1 '^version=' /data/adb/modules/deepdoze_enforcer/module.prop 2>/dev/null | cut -d= -f2)"
`.trim();

  const START_CMD = `
M=/data/adb/modules/deepdoze_enforcer
if command -v setsid >/dev/null 2>&1; then setsid sh $M/service.sh </dev/null >/dev/null 2>&1 & else nohup sh $M/service.sh </dev/null >/dev/null 2>&1 & fi
i=0; while [ $i -lt 5 ]; do
  sleep 1; K=$(cat /data/adb/deepdoze/service.pid 2>/dev/null)
  if [ -n "$K" ] && kill -0 $K 2>/dev/null; then
    C=$(tr '\\0' ' ' < /proc/$K/cmdline 2>/dev/null)
    case "$C" in *"$M/service.sh"*) echo started; exit 0 ;; esac
  fi
  i=$((i+1))
done
echo failed
`.trim();

  const STOP_CMD = `
P=/data/adb/deepdoze/service.pid
K=$(cat $P 2>/dev/null)
if [ -z "$K" ] || ! kill -0 $K 2>/dev/null; then echo stopped; exit 0; fi
C=$(tr '\\0' ' ' < /proc/$K/cmdline 2>/dev/null)
case "$C" in *"/data/adb/modules/deepdoze_enforcer/service.sh"*) ;; *) rm -f $P; echo stopped; exit 0 ;; esac
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
    if (s === 'IDLE') return t('doze.idle');
    if (s.indexOf('IDLE_MAINTENANCE') === 0) return t('doze.maint');
    if (s.indexOf('IDLE_PENDING') === 0 || s === 'SENSING' || s === 'LOCATING') return t('doze.entering');
    if (s === 'ACTIVE' || s === 'INACTIVE') return t('doze.awake');
    return s;
  }

  function modeName(m) { return t('modename.' + m) || m; }

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
    $('engineCard').classList.toggle('is-off', !running);
    $('engineTag').textContent = running
      ? (charging ? t('engine.active.charging') : t('engine.active'))
      : t('engine.off');

    const chips = [];
    chips.push('<span class="stchip ' + (running ? 'on' : 'off') + '"><span class="dot"></span>' + (running ? t('engine.running') : t('engine.stopped')) + '</span>');
    const dl = dozeLabel(s.doze);
    if (dl) chips.push('<span class="stchip"><span class="dot"></span>' + esc(dl) + '</span>');
    const pct = parseInt(s.bpct, 10);
    if (!isNaN(pct)) chips.push('<span class="stchip"><span class="dot"></span>' + pct + '%' + (charging ? ' · ' + t('engine.charging') : '') + '</span>');
    const rc = parseInt(s.restricted, 10);
    if (!isNaN(rc)) {
      state.restricted = rc;
      chips.push('<span class="stchip"><span class="dot"></span>' + t('engine.restricted', { n: rc }) + '</span>');
    }
    $('statusband').innerHTML = chips.join('');

    const avg = parseInt(s.avg, 10);
    const hero = $('hero');
    if (avg > 0) {
      $('avgma').innerHTML = avg + '<small>mA</small>';
      $('minma').textContent = parseInt(s.min, 10) > 0 ? s.min + ' mA' : '—';
      $('maxma').textContent = parseInt(s.max, 10) > 0 ? s.max + ' mA' : '—';
      $('drainSub').textContent = t('drain.measured');
      $('drainMeta').textContent = t('drain.last');
    } else {
      $('avgma').innerHTML = '—<small>mA</small>';
      $('minma').textContent = '—';
      $('maxma').textContent = '—';
      $('drainSub').textContent = running ? t('drain.lock') : t('drain.on');
      $('drainMeta').textContent = '';
    }
    hero.classList.toggle('live', running && avg > 0);

    const mode = ['gentle', 'balanced', 'aggressive', 'off'].includes(s.mode) ? s.mode : 'gentle';
    const r = document.querySelector('input[name="mode"][value="' + mode + '"]');
    if (r) r.checked = true;
    $('cfgCpu').checked = s.cpu === 'true';
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
    const mode = (document.querySelector('input[name="mode"]:checked') || {}).value || 'gentle';
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
    snack((r.stdout || '').trim() === 'ok' ? t('save.ok') : t('save.fail'));
  }

  let masterBusy = false;
  async function toggleMaster() {
    if (masterBusy) return;
    masterBusy = true;
    const master = $('master');
    const on = master.checked;
    master.disabled = true;
    $('engineTag').textContent = on ? t('engine.starting') : t('engine.stopping');
    const r = await exec(on ? START_CMD : STOP_CMD);
    const out = (r.stdout || '').trim();
    if (on) snack(out === 'started' ? t('engine.started') : t('engine.start.fail'));
    else snack(out === 'stopped' ? t('engine.stopped.msg') : t('engine.stop.fail'));
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
      $('applist').innerHTML = '<div class="empty">' + t('apps.loadfail') + '</div>';
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
    if (state.filter === 'protected') list = list.filter(isProtected);
    else if (state.filter === 'paused') list = list.filter((p) => !isProtected(p));
    list.sort((a, b) => {
      if (state.sort === 'prot') {
        const pa = isProtected(a);
        const pb = isProtected(b);
        if (pa !== pb) return pa ? -1 : 1;
      }
      return displayName(a).localeCompare(displayName(b)) || a.localeCompare(b);
    });
    return list;
  }

  function isProtected(pkg) {
    return ESSENTIALS.has(pkg) || state.protected.has(pkg) || state.osExempt.has(pkg);
  }

  function rowHTML(pkg) {
    const essential = ESSENTIALS.has(pkg);
    const osExempt = state.osExempt.has(pkg);
    const prot = isProtected(pkg);
    const name = displayName(pkg);
    const h = hue(pkg);
    const badges =
      (essential ? '<span class="mini always">' + t('apps.always') + '</span>' : '') +
      (osExempt ? '<span class="mini os">' + t('apps.osexempt') + '</span>' : '');
    const picked = state.selectMode && state.picked.has(pkg);
    const avatar = '<span class="avatar" style="--avatar-hue:' + h + '">' +
      (picked ? '✓' : esc(name.charAt(0))) + '</span>';
    const trail = state.selectMode ? '' :
      '<label class="sw" aria-label="' + t('apps.protect.aria', { name }) + '">' +
      '<input type="checkbox" role="switch" data-pkg="' + esc(pkg) + '"' + (prot ? ' checked' : '') + ((essential || osExempt) ? ' disabled' : '') + '>' +
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
      el.innerHTML = '<div class="empty">' + (state.q ? t('apps.nomatch', { q: state.q }) : t('apps.none')) + '</div>';
    } else {
      const shown = list.slice(0, state.limit);
      let html = shown.map(rowHTML).join('');
      if (list.length > state.limit) {
        html += '<button class="morebtn" id="morebtn">' + t('apps.more', { n: list.length - state.limit }) + '</button>';
      }
      el.innerHTML = html;
    }
    updateMeta();
  }

  function updateMeta() {
    const protCount = state.user.filter(isProtected).length;
    $('appMeta').textContent = t('apps.meta', { a: protCount, b: state.user.length });
    $('bulkCount').textContent = t('apps.bulkcount', { n: state.picked.size });
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
    if ((r.stdout || '').trim() === 'ok') snack(t('save.ok'));
    else snack(t('wl.save.fail'));
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
    if (!state.picked.size) { snack(t('apps.select.first')); return; }
    let n = 0;
    state.picked.forEach((p) => {
      if (ESSENTIALS.has(p) || state.osExempt.has(p)) return;
      if (protect && !state.protected.has(p)) { state.protected.add(p); n++; }
      if (!protect && state.protected.has(p)) { state.protected.delete(p); n++; }
    });
    setSelectMode(false);
    if (n) scheduleSaveWL();
    snack(protect ? t('apps.bulk.protect', { n }) : t('apps.bulk.unprotect', { n }));
  }

  function relative(secs) {
    const m = Math.floor(secs / 60);
    if (m < 1) return t('time.justnow');
    if (m < 60) return t('time.min', { m });
    const h = Math.floor(m / 60);
    if (h < 24) return t('time.hour', { h, m: m % 60 });
    return t('time.day', { d: Math.floor(h / 24) });
  }

  function formatEvent(line) {
    const m = line.match(/^\[([^\]]+)\]\s*(.*)$/);
    const when = m ? m[1] : '';
    const msg = m ? m[2] : line;
    let cls = '', title = msg, d = '';
    let mm;
    if ((mm = msg.match(/service started.*mode=(\w+)/))) {
      cls = 'on'; title = t('ev.start'); d = t('ev.start.d', { mode: modeName(mm[1]) });
    } else if (/cpu throttled/.test(msg)) {
      cls = 'on'; title = t('ev.sleep'); d = t('ev.sleep.d');
    } else if (/cpu restored/.test(msg)) {
      cls = 'off'; title = t('ev.unlock'); d = t('ev.unlock.d');
    } else if ((mm = msg.match(/restricted (\d+) apps.*mode=(\w+)/))) {
      cls = 'on'; title = t('ev.paused', { n: mm[1] });
      d = t('ev.paused.d', { mode: modeName(mm[2]) });
    } else if (/restored apps/.test(msg)) {
      cls = 'off'; title = t('ev.resumed'); d = t('ev.resumed.d');
    } else if (/event feed confirmed/.test(msg)) {
      cls = 'on'; title = t('ev.feed'); d = t('ev.feed.d');
    } else if (/seeded whitelist/.test(msg)) {
      cls = 'on'; title = t('ev.seeded'); d = t('ev.seeded.d');
    }
    let whenTxt = '';
    if (when) {
      const dt = new Date(when.replace(' ', 'T'));
      whenTxt = isNaN(dt) ? when : relative((Date.now() - dt.getTime()) / 1000);
    }
    return '<div class="ev"><span class="dot ' + cls + '"></span>' +
      '<div class="body"><div class="t">' + esc(title) + '</div>' +
      (d ? '<div class="d">' + esc(d) + '</div>' : '') + '</div>' +
      (whenTxt ? '<span class="when">' + esc(whenTxt) + '</span>' : '') + '</div>';
  }

  async function loadLog() {
    const r = await exec(LOG_CMD);
    const lines = (r.stdout || '').split('\n').map((l) => l.trim()).filter(Boolean);
    $('logview').innerHTML = lines.length
      ? lines.reverse().map(formatEvent).join('')
      : '<div class="empty">' + t('activity.empty') + '</div>';
  }

  let logShown = false;
  function updateDynamicLabels() {
    $('sortChip').textContent = state.sort === 'az' ? t('apps.sort.az') : t('apps.sort.prot');
    $('logtoggle').textContent = logShown ? t('activity.hide') : t('activity.show');
    $('bulkCount').textContent = t('apps.bulkcount', { n: state.picked.size });
  }

  function setLang(l) {
    lang = l === 'en' ? 'en' : 'zh';
    document.documentElement.dataset.lang = lang;
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    try { localStorage.setItem('deepdoze-lang', lang); } catch (_) {}
    applyStaticI18n();
    applyTheme(document.documentElement.dataset.theme, false);
    updateLangButton();
    updateDynamicLabels();
    if (state.appsLoaded) renderApps();
    refresh();
    if (logShown) loadLog();
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
    $('sortChip').textContent = state.sort === 'az' ? t('apps.sort.az') : t('apps.sort.prot');
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
    if (ESSENTIALS.has(pkg)) { snack(t('apps.always.msg')); return; }
    if (state.osExempt.has(pkg)) { snack(t('apps.osexempt.msg')); return; }
    if (state.picked.has(pkg)) state.picked.delete(pkg);
    else state.picked.add(pkg);
    renderApps();
  });

  $('logtoggle').addEventListener('click', () => {
    logShown = !logShown;
    $('logview').hidden = !logShown;
    $('logtoggle').textContent = logShown ? t('activity.hide') : t('activity.show');
    $('logtoggle').setAttribute('aria-expanded', logShown ? 'true' : 'false');
    if (logShown) loadLog();
  });

  document.addEventListener('click', (e) => {
    const a = e.target.closest('a[data-ext]');
    if (!a) return;
    e.preventDefault();
    exec('am start -a android.intent.action.VIEW -d ' + shq(a.getAttribute('data-ext')) + ' >/dev/null 2>&1');
  });

  applyStaticI18n();
  updateDynamicLabels();
  refresh();
  loadApps();
  setTimeout(() => document.body.classList.remove('booting'), 700);
  setInterval(() => {
    if (!document.hidden && !state.selectMode) refresh();
  }, 6000);
})();
