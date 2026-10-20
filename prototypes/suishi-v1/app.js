'use strict';

(() => {
  const $ = id => document.getElementById(id);
  const storageKey = 'suishi-ui-v1';
  const defaults = { scale: 60, policy: 'complete', response: 'balanced', offset: 0, grid: false, gridOpacity: 24 };
  const titles = ['山野之间 · 多洛米蒂的慢时光', '在湖边，什么都不做的一天', '去山里，把生活调慢一点'];
  let saved = null;
  let storageAvailable = true;
  try { saved = JSON.parse(localStorage.getItem(storageKey) || 'null'); } catch { storageAvailable = false; }
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const number = (value, fallback, min, max) => typeof value === 'number' && Number.isFinite(value) ? clamp(value, min, max) : fallback;
  const loaded = saved?.prefs || {};
  const prefs = {
    scale: number(loaded.scale, defaults.scale, 35, 100),
    policy: ['complete', 'crop'].includes(loaded.policy) ? loaded.policy : defaults.policy,
    response: ['soft', 'balanced', 'fast'].includes(loaded.response) ? loaded.response : defaults.response,
    offset: number(loaded.offset, defaults.offset, -5, 5),
    grid: typeof loaded.grid === 'boolean' ? loaded.grid : defaults.grid,
    gridOpacity: number(loaded.gridOpacity, defaults.gridOpacity, 10, 60)
  };
  const state = {
    view: 'watch', mode: 'preview', head: -8, neutral: 0, angle: -8,
    frozenAngle: -8, following: false, auto: false, playing: false, muted: false,
    title: typeof saved?.media?.title === 'string' ? saved.media.title.slice(0, 180) : titles[0],
    link: typeof saved?.media?.link === 'string' ? saved.media.link.slice(0, 2048) : '',
    time: number(saved?.media?.time, 151, 0, 754), duration: 754,
    x: 0, y: 0, first: false, settings: false, error: false, gridDirty: true
  };
  let toastTimer, lastFrame = 0, playbackRemainder = 0, lastSave = 0, lastRenderedAngle = null;
  let geometry = null, drag = null, previousFocus = null, settingsOrigin = null;
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const rad = a => a * Math.PI / 180;
  const signed = (n, digits = 0) => `${Math.abs(n) < .05 ? '' : n < 0 ? '−' : '+'}${Math.abs(n).toFixed(digits)}°`;
  const timeLabel = seconds => `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`;
  const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;

  function toast(message, warning = false) {
    clearTimeout(toastTimer);
    const el = $('toast');
    el.querySelector('use').setAttribute('href', warning ? '#i-help' : '#i-check');
    el.querySelector('span').textContent = message;
    el.hidden = false;
    toastTimer = setTimeout(() => { el.hidden = true; }, 3600);
  }

  function persist() {
    try {
      localStorage.setItem(storageKey, JSON.stringify({ version: 1, prefs, media: { title: state.title, link: state.link, time: Math.floor(state.time) } }));
      storageAvailable = true;
    } catch { storageAvailable = false; }
    $('saveStatus').textContent = storageAvailable ? '偏好自动保存在此浏览器' : '仅本次有效 · 浏览器存储不可用';
  }

  function paintRange(input) {
    const ratio = (Number(input.value) - Number(input.min)) / (Number(input.max) - Number(input.min));
    input.style.setProperty('--fill', `${clamp(ratio, 0, 1) * 100}%`);
  }

  function syncMedia() {
    $('videoTitle').textContent = state.title;
    $('resumeTitle').textContent = state.title;
    $('resumeTime').textContent = timeLabel(state.time);
    $('currentTime').textContent = timeLabel(state.time);
    $('seek').value = state.time;
    paintRange($('seek'));
    $('playButton').innerHTML = icon(state.playing ? 'pause' : 'play');
    $('playButton').setAttribute('aria-label', state.playing ? '暂停预览' : '播放预览');
    $('playStateLabel').textContent = state.playing ? '预览播放中' : '已暂停';
    $('picture').classList.toggle('playing', state.playing);
    $('muteButton').setAttribute('aria-pressed', String(state.muted));
    $('muteButton').setAttribute('aria-label', state.muted ? '取消静音预览' : '静音预览');
    $('muteButton').style.opacity = state.muted ? '.5' : '1';
  }

  function syncPrefs() {
    for (const key of ['scale', 'offset', 'gridOpacity']) {
      $(key).value = prefs[key];
      paintRange($(key));
    }
    $('scaleOutput').textContent = `${prefs.scale}%`;
    $('offsetOutput').textContent = signed(prefs.offset, Number.isInteger(prefs.offset) ? 0 : 1);
    $('gridOpacityOutput').textContent = `${prefs.gridOpacity}%`;
    for (const name of ['policy', 'response']) document.querySelectorAll(`input[name=${name}]`).forEach(input => { input.checked = input.value === prefs[name]; });
    $('gridSwitch').setAttribute('aria-checked', String(prefs.grid));
    $('gridButton').setAttribute('aria-pressed', String(prefs.grid));
    $('gridButton').setAttribute('aria-label', prefs.grid ? '关闭引导线' : '开启引导线');
    $('gridSettings').hidden = !prefs.grid;
    state.gridDirty = true;
    geometry = null;
  }

  function syncTracking() {
    const modes = {
      preview: '头部跟随未开启', tracking: '正在跟随', paused: '跟随已暂停',
      lost: '暂未识别人脸 · 保持画面', denied: '摄像头不可用', error: '视频加载失败'
    };
    $('trackingText').textContent = modes[state.mode] || modes.preview;
    $('trackingPill').dataset.state = state.mode;
    $('followButton').classList.toggle('following', state.following);
    $('followButton').innerHTML = icon(state.following ? 'pause' : 'face') + `<span>${state.following ? '暂停跟随' : state.mode === 'paused' ? '恢复跟随' : '开启头部跟随'}</span>`;
    $('followButton').disabled = state.error;
    $('autoButton').setAttribute('aria-pressed', String(state.auto));
    $('autoButton').innerHTML = icon(state.auto ? 'pause' : 'play') + `<span>${state.auto ? '停止演示' : '自动演示'}</span>`;
    const messages = {
      lost: ['暂时没有识别到你', '画面保持原位。回到镜头前后，平滑恢复跟随。'],
      denied: ['暂时无法使用摄像头', '正式版请在系统设置中允许随视访问摄像头。'],
      error: ['视频暂时没有加载成功', '可以重试，或返回选片打开另一个视频。']
    };
    const message = messages[state.mode];
    $('stageMessage').hidden = !message;
    $('stageMessage').classList.toggle('no-face', state.mode === 'lost');
    $('stageRetry').textContent = state.mode === 'lost' ? '模拟恢复' : '重试';
    if (message) {
      $('stageMessageTitle').textContent = message[0];
      $('stageMessageBody').textContent = message[1];
    }
    $('stage').classList.toggle('load-error', state.error);
  }

  function setView(view, focus = false) {
    if (state.settings) closeSettings(false);
    state.view = view;
    $('watchView').hidden = view !== 'watch';
    $('browseView').hidden = view !== 'browse';
    for (const tab of document.querySelectorAll('[data-view]')) {
      const selected = tab.dataset.view === view;
      tab.classList.toggle('selected', selected);
      tab.setAttribute('aria-current', selected ? 'page' : 'false');
    }
    // Hide the watching session; keep it alive and pause its simulated media.
    if (view === 'browse') { state.playing = false; state.auto = false; syncMedia(); syncTracking(); }
    else { geometry = null; state.gridDirty = true; }
    if (focus) $(view === 'browse' ? 'browseTab' : 'watchTab').focus();
  }

  function startVideo(title, link = '', resume = false) {
    state.title = title;
    state.link = link;
    if (!resume) state.time = 0;
    state.error = false;
    state.first = false;
    if (state.mode === 'error') state.mode = state.following ? 'tracking' : 'preview';
    state.playing = true;
    $('resumeCard').hidden = false;
    $('scenario').value = state.following ? 'tracking' : 'preview';
    syncMedia(); syncTracking(); setView('watch'); persist();
    toast('已进入随视观看 · 当前为场景与播放进度模拟');
  }

  function parseVideo(raw) {
    const text = raw.trim();
    let match = text.match(/^BV[0-9A-Za-z]{10}$/i);
    if (match) return { id: 'BV' + text.slice(2), link: `https://www.bilibili.com/video/BV${text.slice(2)}` };
    if (/^av[1-9]\d*$/i.test(text)) return { id: text, link: `https://www.bilibili.com/video/${text.toLowerCase()}` };
    const urlText = text.match(/https?:\/\/[^\s，。<>]+/i)?.[0];
    if (!urlText) return null;
    let url;
    try { url = new URL(urlText); } catch { return null; }
    if (url.hostname === 'b23.tv' || url.hostname === 'www.b23.tv') return { short: true };
    if (!['bilibili.com', 'www.bilibili.com', 'm.bilibili.com'].includes(url.hostname)) return null;
    const id = url.pathname.match(/^\/video\/(BV[0-9A-Za-z]{10}|av[1-9]\d*)\/?$/i)?.[1];
    if (!id) return null;
    const clean = new URL(`https://www.bilibili.com/video/${id}`);
    for (const key of ['p', 't']) {
      const value = url.searchParams.get(key);
      if (value && /^\d+$/.test(value) && Number(value) < 1e7) clean.searchParams.set(key, value);
    }
    return { id, link: clean.href, time: Number(clean.searchParams.get('t') || 0) };
  }

  function setScenario(value) {
    state.auto = false;
    state.frozenAngle = state.angle;
    state.error = value === 'error';
    state.mode = value === 'first' ? 'preview' : value;
    state.following = ['tracking', 'lost'].includes(value);
    state.first = value === 'first';
    $('resumeCard').hidden = state.first;
    if (value === 'first') {
      state.playing = false;
      $('address').value = '';
      $('search').value = '';
      filterSamples('');
      setView('browse');
    } else setView('watch');
    if (value === 'preview') state.frozenAngle = state.head;
    syncMedia(); syncTracking();
  }

  function follow() {
    if (state.error) return;
    if (state.mode === 'denied') {
      toast('这是摄像头不可用状态。可在“体验状态”中模拟恢复。', true);
      return;
    }
    if (state.following) {
      state.following = false; state.auto = false; state.mode = 'paused'; state.frozenAngle = state.angle;
    } else {
      state.following = true; state.mode = 'tracking';
      toast('已模拟开启头部跟随 · 本原型不调用摄像头');
    }
    $('scenario').value = state.following ? 'tracking' : 'preview';
    syncTracking();
  }

  function calibrate() {
    if (state.mode === 'denied' || state.mode === 'lost') { toast('识别恢复后再校准水平。当前为状态模拟。', true); return; }
    state.neutral = state.head;
    prefs.offset = 0;
    state.frozenAngle = 0;
    syncPrefs(); persist();
    toast('已将当前姿势校准为水平');
  }

  function calculateGeometry() {
    const stage = $('stage');
    const w = stage.clientWidth, h = stage.clientHeight;
    const mobile = w < 600;
    // A fixed 16:9 surface. Its size never changes in response to rotation.
    const vw = Math.min(w, h * 16 / 9) * prefs.scale / 100;
    const vh = vw * 9 / 16;
    const minX = vw / 2 + 8, maxX = w - vw / 2 - 8;
    const preferredY = mobile ? h * .44 : h * .45;
    const cx = clamp(w / 2 + state.x, Math.min(minX, w / 2), Math.max(maxX, w / 2));
    const cy = clamp(preferredY + state.y, Math.min(vh / 2 + 8, h / 2), Math.max(h - vh / 2 - 8, h / 2));
    const availableW = 2 * Math.min(cx - 4, w - cx - 4);
    const availableH = 2 * Math.min(cy - 4, h - cy - 4);
    const fits = degrees => {
      const a = rad(Math.abs(degrees));
      const ax = Math.min(a, Math.atan2(vh, vw)), ay = Math.min(a, Math.atan2(vw, vh));
      return vw * Math.cos(ax) + vh * Math.sin(ax) <= availableW + .01 && vw * Math.sin(ay) + vh * Math.cos(ay) <= availableH + .01;
    };
    let safe = 45;
    if (prefs.policy === 'complete' && !fits(45)) {
      let low = 0, high = 45;
      for (let i = 0; i < 32; i++) { const mid = (low + high) / 2; if (fits(mid)) low = mid; else high = mid; }
      safe = low < .1 ? 0 : low;
    }
    $('geometryHint').textContent = prefs.policy === 'complete' ? `当前可完整旋转约 ±${Math.floor(safe)}°。放大或靠近边缘会减少空间。` : '按姿势自由旋转，超出观看区域的边角会被裁切。';
    return { w, h, vw, vh, cx, cy, safe };
  }

  function drawGuides(g) {
    const canvas = $('guideCanvas');
    const ratio = Math.min(devicePixelRatio || 1, 2);
    if (canvas.width !== Math.round(g.w * ratio) || canvas.height !== Math.round(g.h * ratio)) {
      canvas.width = Math.round(g.w * ratio); canvas.height = Math.round(g.h * ratio);
    }
    const c = canvas.getContext('2d');
    c.setTransform(ratio, 0, 0, ratio, 0, 0); c.clearRect(0, 0, g.w, g.h);
    if (!prefs.grid || state.error) return;
    c.save();
    c.beginPath(); c.rect(0, 0, g.w, g.h);
    const a = rad(state.angle), cos = Math.cos(a), sin = Math.sin(a);
    const corners = [[-1,-1],[1,-1],[1,1],[-1,1]];
    corners.forEach(([sx,sy],i) => {
      const x = sx * g.vw / 2, y = sy * g.vh / 2;
      const px = g.cx + x * cos - y * sin, py = g.cy + x * sin + y * cos;
      if (i) c.lineTo(px,py); else c.moveTo(px,py);
    });
    c.closePath(); c.clip('evenodd');
    // One horizontal grid, only outside the media. No second rotation pipeline.
    c.globalAlpha = prefs.gridOpacity / 100; c.strokeStyle = '#555555'; c.lineWidth = 1;
    const gap = 64, x0 = (g.w / 2) % gap, y0 = (g.h / 2) % gap;
    c.beginPath();
    for (let x = x0; x < g.w; x += gap) { c.moveTo(x,0); c.lineTo(x,g.h); }
    for (let y = y0; y < g.h; y += gap) { c.moveTo(0,y); c.lineTo(g.w,y); }
    c.stroke(); c.restore();
  }

  function showSettings(origin) {
    if (state.settings) return;
    state.settings = true;
    settingsOrigin = origin || document.activeElement;
    $('settingsBackdrop').hidden = false; $('settingsPanel').hidden = false;
    for (const id of ['watchView', 'browseView']) $(id).inert = true;
    document.querySelector('.titlebar').inert = true;
    document.querySelector('.prototype-controls').inert = true;
    $('settingsPanel').querySelector('[data-action=closeSettings]').focus();
  }
  function closeSettings(restore = true) {
    state.settings = false;
    $('settingsBackdrop').hidden = true; $('settingsPanel').hidden = true;
    for (const id of ['watchView', 'browseView']) $(id).inert = false;
    document.querySelector('.titlebar').inert = false;
    document.querySelector('.prototype-controls').inert = false;
    if (restore && settingsOrigin?.isConnected) settingsOrigin.focus();
    settingsOrigin = null;
  }

  function filterSamples(query) {
    const q = query.trim().toLowerCase();
    let count = 0;
    document.querySelectorAll('[data-video]').forEach(card => {
      const match = !q || card.textContent.toLowerCase().includes(q);
      card.hidden = !match; if (match) count++;
    });
    $('sampleGrid').hidden = count === 0;
    $('noResults').hidden = count > 0;
    $('resultsLabel').textContent = q ? `搜索示例：${query}` : '试着点开一个视频';
  }

  function openDialog(id) {
    previousFocus = document.activeElement;
    $(id).showModal();
  }
  function closeDialog() {
    document.querySelectorAll('dialog[open]').forEach(d => d.close());
    if (previousFocus?.isConnected) previousFocus.focus();
  }

  const actions = {
    help: () => openDialog('helpDialog'),
    login: () => openDialog('loginDialog'),
    closeDialog,
    browse: () => setView('browse', true),
    settings: origin => showSettings(origin),
    closeSettings: () => closeSettings(),
    follow,
    calibrate,
    center: () => { state.x = state.y = 0; geometry = null; toast('画面已居中'); },
    grid: () => { prefs.grid = !prefs.grid; syncPrefs(); persist(); },
    play: () => { if (state.error) return; state.playing = !state.playing; syncMedia(); persist(); },
    mute: () => { state.muted = !state.muted; syncMedia(); toast(state.muted ? '已模拟静音 · 场景预览本身无音轨' : '已取消模拟静音'); },
    quality: () => toast('正式版使用 B 站播放器清晰度菜单；此原型无实际视频流。', true),
    auto: () => {
      if (state.error) { toast('先恢复视频加载，再体验自动旋转。', true); return; }
      if (reducedMotion.matches) { toast('系统已启用减少动态效果，请用角度滑杆逐步体验。', true); return; }
      state.auto = !state.auto;
      if (state.auto) {
        state.following = true; state.mode = 'tracking'; state.neutral = 0;
        $('scenario').value = 'tracking'; setView('watch');
      }
      syncTracking();
    },
    retry: () => {
      state.error = false; state.mode = state.following ? 'tracking' : 'preview';
      if (!state.following && state.mode === 'preview') state.frozenAngle = state.angle;
      $('scenario').value = state.following ? 'tracking' : 'preview'; syncTracking(); toast('已模拟恢复');
    },
    resume: () => startVideo(state.title, state.link, true),
    browserBack: () => { $('address').value = ''; $('search').value = ''; filterSamples(''); toast('已返回选片示意首页'); },
    reload: () => { filterSamples($('search').value); toast('已刷新示意页面 · 正式版加载 B 站官网'); },
    clearSearch: () => { $('search').value = ''; filterSamples(''); $('search').focus(); },
    resetSettings: () => { Object.assign(prefs, defaults); state.x = state.y = 0; syncPrefs(); persist(); toast('观看设置已恢复默认'); },
    fullscreen: async () => {
      try {
        if (document.fullscreenElement) await document.exitFullscreen();
        else if ($('appWindow').requestFullscreen) await $('appWindow').requestFullscreen();
        else toast('当前浏览器不支持网页全屏，请使用浏览器全屏。', true);
      } catch { toast('当前预览环境未允许全屏，请在独立浏览器中打开。', true); }
    }
  };

  document.addEventListener('click', event => {
    const actionElement = event.target.closest('[data-action]');
    if (actionElement) actions[actionElement.dataset.action]?.(actionElement);
    const tab = event.target.closest('[data-view]');
    if (tab) setView(tab.dataset.view);
    const video = event.target.closest('[data-video]');
    if (video) startVideo(titles[Number(video.dataset.video)]);
  });
  $('settingsBackdrop').addEventListener('click', () => closeSettings());
  $('scenario').addEventListener('change', event => setScenario(event.target.value));
  $('headAngle').addEventListener('input', event => {
    state.head = Number(event.target.value); state.auto = false;
    $('headOutput').textContent = signed(state.head); paintRange(event.target); syncTracking();
    if (state.mode === 'paused') toast('跟随已暂停，点击“恢复跟随”后画面才会转动。', true);
  });
  for (const key of ['scale', 'offset', 'gridOpacity']) $(key).addEventListener('input', event => { prefs[key] = Number(event.target.value); syncPrefs(); persist(); });
  for (const name of ['policy', 'response']) document.querySelectorAll(`input[name=${name}]`).forEach(input => input.addEventListener('change', () => { prefs[name] = input.value; syncPrefs(); persist(); }));
  $('seek').addEventListener('input', event => { state.time = Number(event.target.value); syncMedia(); });
  $('seek').addEventListener('change', persist);
  $('addressForm').addEventListener('submit', event => {
    event.preventDefault();
    const result = parseVideo($('address').value);
    if (result?.short) { toast('此原型不联网解析短链接，请粘贴完整视频地址或 BV 号。', true); return; }
    if (!result) { toast('请输入有效的 B 站普通投稿链接或 BV / av 号。', true); $('address').setAttribute('aria-invalid','true'); return; }
    $('address').removeAttribute('aria-invalid');
    startVideo(`B 站视频 · ${result.id}`, result.link);
    if (result.time) { state.time = clamp(result.time, 0, state.duration); syncMedia(); persist(); }
  });
  $('address').addEventListener('input', () => $('address').removeAttribute('aria-invalid'));
  $('searchForm').addEventListener('submit', event => { event.preventDefault(); filterSamples($('search').value); });
  $('search').addEventListener('input', () => filterSamples($('search').value));
  $('picture').addEventListener('pointerdown', event => {
    if (!event.altKey || event.target.closest('button,input')) return;
    drag = { x: event.clientX, y: event.clientY, sx: state.x, sy: state.y };
    $('picture').setPointerCapture(event.pointerId); event.preventDefault();
  });
  $('picture').addEventListener('pointermove', event => {
    if (!drag) return;
    state.x = drag.sx + event.clientX - drag.x; state.y = drag.sy + event.clientY - drag.y;
    geometry = null; state.gridDirty = true;
  });
  for (const event of ['pointerup','pointercancel','lostpointercapture']) $('picture').addEventListener(event, () => { drag = null; });
  $('picture').addEventListener('dblclick', event => { if (!event.target.closest('button,input')) actions.center(); });
  document.addEventListener('keydown', event => {
    const editing = event.target.closest('input,textarea,select,[contenteditable]');
    const dialogOpen = document.querySelector('dialog[open]');
    if (event.key === 'Escape') {
      if (dialogOpen) return;
      if (state.settings) { event.preventDefault(); closeSettings(); }
      else if (!document.fullscreenElement && state.view === 'watch') setView('browse', true);
      return;
    }
    if (state.settings && event.key === 'Tab') {
      const elements = [...$('settingsPanel').querySelectorAll('button,input,select,[tabindex="0"]')].filter(el => !el.closest('[hidden]') && !el.disabled);
      const first = elements[0], last = elements[elements.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
      return;
    }
    if (editing || dialogOpen || state.settings) return;
    if ((event.metaKey || event.ctrlKey) && event.key === ',') { event.preventDefault(); showSettings(); return; }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'r') { event.preventDefault(); calibrate(); return; }
    if (event.metaKey || event.ctrlKey || event.altKey || state.view !== 'watch') return;
    if (event.key === ' ' && event.target.closest('button,a')) return;
    if (event.key === ' ') { event.preventDefault(); actions.play(); }
    else if (event.key.toLowerCase() === 'g') actions.grid();
    else if (event.key.toLowerCase() === 'f') actions.fullscreen();
  });
  document.addEventListener('fullscreenchange', () => { geometry = null; state.gridDirty = true; });
  document.addEventListener('visibilitychange', () => { lastFrame = 0; persist(); });
  window.addEventListener('pagehide', persist);
  new ResizeObserver(() => { geometry = null; state.gridDirty = true; }).observe($('stage'));
  reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) { state.auto = false; syncTracking(); } });

  function frame(ms) {
    const dt = lastFrame ? Math.min(.064, (ms - lastFrame) / 1000) : 0;
    lastFrame = ms;
    if (state.view === 'watch' && !document.hidden) {
      if (!geometry) geometry = calculateGeometry();
      const g = geometry;
      if (state.auto) {
        state.head = Math.sin(ms / 4800) * 15;
        $('headAngle').value = state.head;
        $('headOutput').textContent = signed(state.head);
        paintRange($('headAngle'));
      }
      let target = state.frozenAngle;
      if (state.mode === 'preview' || state.mode === 'tracking') target = clamp(state.head - state.neutral + prefs.offset, -45, 45);
      const desired = clamp(target, -g.safe, g.safe);
      const tau = { soft: .6, balanced: .32, fast: .12 }[prefs.response];
      state.angle = reducedMotion.matches ? desired : state.angle + (desired - state.angle) * (1 - Math.exp(-dt / tau));
      state.angle = clamp(state.angle, -g.safe, g.safe);
      if (Math.abs(state.angle - desired) < .01) state.angle = desired;
      const picture = $('picture');
      picture.style.width = `${g.vw}px`; picture.style.height = `${g.vh}px`;
      picture.style.left = `${g.cx}px`; picture.style.top = `${g.cy}px`;
      picture.style.transform = `translate(-50%,-50%) rotate(${state.angle}deg)`;
      $('liveAngle').textContent = signed(state.angle, 1);
      $('boundaryHint').hidden = state.error || state.mode === 'lost' || prefs.policy !== 'complete' || Math.abs(target) <= g.safe + .1;
      if (state.gridDirty || lastRenderedAngle === null || Math.abs(lastRenderedAngle - state.angle) > .025) {
        drawGuides(g); state.gridDirty = false; lastRenderedAngle = state.angle;
      }
      if (state.playing && !state.error) {
        playbackRemainder += dt;
        if (playbackRemainder >= 1) {
          state.time = Math.min(state.duration, state.time + Math.floor(playbackRemainder));
          playbackRemainder %= 1;
          if (state.time >= state.duration) state.playing = false;
          syncMedia();
        }
      }
      if (ms - lastSave > 10000 && state.playing) { persist(); lastSave = ms; }
    }
    requestAnimationFrame(frame);
  }
  syncPrefs(); syncMedia(); syncTracking();
  document.querySelectorAll('input[type=range]').forEach(paintRange);
  if (!storageAvailable) $('saveStatus').textContent = '仅本次有效 · 浏览器存储不可用';
  if (location.hash === '#browse') setView('browse');
  if (location.hash === '#first') { $('scenario').value = 'first'; setScenario('first'); }
  requestAnimationFrame(frame);
})();
