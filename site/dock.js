// Brainmerge: the Dock of "Each account is an app of its own", answering like a Mac's.
// The pointer magnifies the icons under it, an app not yet open bounces as it launches, then shows its running dot.
// One Tab stop for the whole Dock, the arrow keys go from app to app (a toolbar). Everything is visible without this
// file; with Reduce Motion nothing moves, the icon under the pointer only lights up.
(function () {
  'use strict';

  // ---------- Pure functions (no DOM: tested in Node) ----------

  var Dock = (function () {
    // The Dock's magnification: the icon under the pointer grows to MAX times its size, its neighbours less and less
    // over RANGE icons on each side, on a cosine, so the curve has no corner anywhere.
    var MAX = 1.6;
    var RANGE = 2.5;

    function falloff(u) {
      u = Math.abs(u);
      return u >= 1 ? 0 : (1 + Math.cos(Math.PI * u)) / 2;
    }

    // Each slot's scale, and where it moves to, for a pointer at `x` (px from the left of the icons at rest).
    // `widths`: the slots at rest, left to right (icons and the separator). `amp`: 0 at rest, 1 fully magnified.
    // The slots grow in place and push their neighbours apart, and the point under the pointer stays under it: the
    // Dock widens on both sides by what grew on each side. `room` caps the total widening (a narrow window).
    // Returns each slot's scale and the shift of its center, and how far the bar's ends move (left <= 0 <= right).
    function magnify(widths, x, amp, opts) {
      var o = opts || {};
      var size = o.size, max = o.max || MAX, range = (o.range || RANGE) * size;
      var n = widths.length, starts = [], total = 0, i;
      for (i = 0; i < n; i++) { starts.push(total); total += widths[i]; }
      var scale = [], dx = [];
      if (x === null || x === undefined || !(amp > 0)) {
        for (i = 0; i < n; i++) { scale.push(1); dx.push(0); }
        return { scale: scale, dx: dx, left: 0, right: 0 };
      }
      var extra = 0;
      for (i = 0; i < n; i++) {
        var s = 1 + (max - 1) * amp * falloff((x - (starts[i] + widths[i] / 2)) / range);
        scale.push(s);
        extra += widths[i] * (s - 1);
      }
      if (o.room !== undefined && extra > o.room) {
        var k = o.room > 0 ? o.room / extra : 0;
        for (i = 0; i < n; i++) scale[i] = 1 + (scale[i] - 1) * k;
      }
      // Where the pointer falls in the grown row: the same fraction of the same slot.
      var px = Math.max(0, Math.min(total, x)), at = 0, grown = 0;
      for (i = 0; i < n; i++) {
        var w = widths[i] * scale[i];
        if (px <= starts[i] + widths[i] || i === n - 1) { at = grown + (widths[i] ? (px - starts[i]) / widths[i] : 0) * w; break; }
        grown += w;
      }
      var shift = px - at, run = 0;
      for (i = 0; i < n; i++) {
        var W = widths[i] * scale[i];
        dx.push(shift + run + W / 2 - (starts[i] + widths[i] / 2));
        run += W;
      }
      return { scale: scale, dx: dx, left: shift, right: shift + run - total };
    }

    // The slot under `x` in the grown row, or -1 outside it.
    function slotAt(widths, x) {
      var run = 0;
      for (var i = 0; i < widths.length; i++) {
        if (x >= run && x < run + widths[i]) return i;
        run += widths[i];
      }
      return -1;
    }

    // The launch bounce: the Mac's, the same hop again while the app opens, never losing height. Each hop is a true
    // parabola (gravity) half the icon high, 0.44 s up and down. Heights are fractions of the icon; times in seconds.
    var HOPS = [0.5, 0.5];
    var HOP_TIME = 0.44;
    var BOUNCE = HOPS.length * HOP_TIME;

    // How high the icon is `t` seconds after the click, as a fraction of its size.
    function bounce(t) {
      if (!(t > 0) || t >= BOUNCE) return 0;
      var i = Math.min(HOPS.length - 1, Math.floor(t / HOP_TIME)), u = (t - i * HOP_TIME) / HOP_TIME;
      return HOPS[i] * 4 * u * (1 - u);
    }

    // One frame of a spring toward `to` (response in seconds; damping 1 is critical, no overshoot), in small steps so
    // a long frame never makes it unstable. Returns [value, velocity].
    function springStep(x, v, to, dt, response, damping) {
      var w = 2 * Math.PI / response, z = damping === undefined ? 1 : damping;
      var steps = Math.max(1, Math.ceil(dt / (1 / 240))), h = dt / steps;
      for (var i = 0; i < steps; i++) {
        v += (-w * w * (x - to) - 2 * z * w * v) * h;
        x += v * h;
      }
      return [x, v];
    }
    function settled(x, v, to) { return Math.abs(x - to) < 1e-3 && Math.abs(v) < 1e-2; }

    // Opening on the Mac: an app already open does not bounce, it only comes forward. The primary account's own app
    // hands over to Claude (it has no Dock tile of its own while it runs), so it bounces but shows no dot of its own.
    function launch(app) {
      if (app.running) return { bounce: false, dot: true };
      return { bounce: true, dot: !app.opener };
    }

    return {
      MAX: MAX, RANGE: RANGE, falloff: falloff, magnify: magnify, slotAt: slotAt,
      HOPS: HOPS, HOP_TIME: HOP_TIME, BOUNCE: BOUNCE, bounce: bounce,
      springStep: springStep, settled: settled, launch: launch
    };
  })();

  if (typeof window === 'undefined') {
    if (typeof module !== 'undefined') module.exports = Dock;
    return;
  }

  // ---------- The page ----------

  var dock = document.querySelector('.mdock');
  if (!dock) return;
  var screen = dock.closest('.mac') || dock.parentNode;
  var row = dock.querySelector('.mdock-row');
  var slots = Array.prototype.slice.call(row.children);
  var apps = slots.filter(function (el) { return el.classList.contains('mdock-app'); });
  var halves = Array.prototype.slice.call(dock.querySelectorAll('.mdock-half > .mdock-bar'));

  var motionQuery = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: no-preference)') : null;
  var reduce = !motionQuery || !motionQuery.matches;
  var fine = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)');
  var canMagnify = function () { return !reduce && !!fine && fine.matches; };

  dock.classList.add('is-live');
  if (!reduce) dock.classList.add('is-moving');

  function name(el) { return el.getAttribute('data-name'); }
  function isRunning(el) { return el.hasAttribute('data-running'); }
  function setRunning(el, on) {
    if (on) el.setAttribute('data-running', ''); else el.removeAttribute('data-running');
    el.setAttribute('aria-label', name(el) + (on ? ', open' : ''));
  }
  apps.forEach(function (el) {
    setRunning(el, isRunning(el));
    el._icon = el.querySelector('.mdock-icon');
    el._name = el.querySelector('.mdock-name');
    el._label = el._name.textContent;
  });

  // ---------- Geometry, read once and again on resize ----------

  var size = 0, widths = [], room = 0;
  function measure() {
    size = apps[0].offsetWidth;
    widths = slots.map(function (el) { return el.offsetWidth; });
    var bar = dock.offsetWidth;
    // The Dock stays inside the screen: whatever it may widen by, on the side it widens most.
    room = Math.max(0, (screen.clientWidth - bar) / 2 - size * 0.25);
  }
  measure();

  // ---------- State and the frame loop (runs only while something moves) ----------

  var amp = 0, ampV = 0, ampTo = 0, px = null, hovered = -1;
  var hops = new Map(); // app element -> start time (ms)
  var named = new Set(); // apps showing their name for a touch, a key or the launch on arrival
  var frame = 0, last = 0;

  function kick() { if (!frame) { last = 0; frame = requestAnimationFrame(tick); } }

  function tick(now) {
    frame = 0;
    var dt = last ? Math.min(0.05, (now - last) / 1000) : 1 / 60;
    last = now;
    var busy = false;

    if (amp !== ampTo || ampV !== 0) {
      // In fast, out a touch slower: the Dock settles back as the pointer leaves.
      var r = Dock.springStep(amp, ampV, ampTo, dt, ampTo > amp ? 0.2 : 0.28, 1);
      amp = Math.max(0, Math.min(1, r[0])); ampV = r[1];
      if (Dock.settled(amp, ampV, ampTo)) { amp = ampTo; ampV = 0; } else busy = true;
    }

    var m = Dock.magnify(widths, px, amp, { size: size, room: room });
    halves[0].style.transform = 'translateX(' + m.left.toFixed(2) + 'px)';
    halves[1].style.transform = 'translateX(' + m.right.toFixed(2) + 'px)';

    slots.forEach(function (el, i) {
      var sc = m.scale[i];
      el.style.transform = m.dx[i] ? 'translateX(' + m.dx[i].toFixed(2) + 'px)' : '';
      if (!el.classList.contains('mdock-app')) return;
      var lift = 0, t0 = hops.get(el);
      if (t0 !== undefined) {
        var t = (now - t0) / 1000;
        if (t < Dock.BOUNCE) { lift = Dock.bounce(t) * size * sc; busy = true; } else land(el);
      }
      el._icon.style.transform = 'translateY(' + (-lift).toFixed(2) + 'px) scale(' + (sc / Dock.MAX).toFixed(4) + ')';
      // The name rides on top of the grown icon (the squircle's top is 90% up the image), and on its bounce.
      el._name.style.transform = 'translate(-50%, ' + (-(sc - 1) * 0.9 * size - lift).toFixed(2) + 'px)';
    });

    var under = amp > 0.02 && px !== null && ampTo > 0 ? Dock.slotAt(widths.map(function (w, i) { return w * m.scale[i]; }), px - m.left) : -1;
    if (under !== hovered) {
      if (hovered >= 0) slots[hovered].classList.remove('is-hover');
      hovered = under >= 0 && slots[under].classList.contains('mdock-app') ? under : -1;
      if (hovered >= 0) slots[hovered].classList.add('is-hover');
    }

    if (busy) kick();
  }

  function land(el) {
    hops.delete(el);
    var plan = el._plan;
    if (plan && plan.dot) setRunning(el, true);
    else if (plan) { opensClaude(el); return; }
    named.delete(el);
    el.classList.remove('is-named');
  }

  // ---------- Pointer: magnification (mouse and trackpad only) ----------

  function onMove(e) {
    if (!canMagnify() || e.pointerType === 'touch') return;
    // Far from the Dock with nothing magnified or bouncing: nothing to do (a page scrolling under a resting mouse sends
    // these too).
    if (ampTo === 0 && amp === 0 && !hops.size) {
      var b0 = dock.getBoundingClientRect();
      if (e.clientY < b0.top - size * (Dock.MAX - 1) || e.clientY > b0.bottom || e.clientX < b0.left || e.clientX > b0.right) return;
    }
    var r = row.getBoundingClientRect();
    var x = e.clientX - r.left;
    var bar = dock.getBoundingClientRect();
    var m = Dock.magnify(widths, px, amp, { size: size, room: room });
    // Enter over the bar; once magnified, the grown icons above it still count.
    var top = bar.top - (ampTo > 0 ? size * (Dock.MAX - 1) : 0);
    var inside = e.clientY >= top && e.clientY <= bar.bottom &&
      e.clientX >= bar.left + m.left && e.clientX <= bar.right + m.right;
    if (inside) { px = x; ampTo = 1; } else ampTo = 0;
    kick();
  }
  function onLeave() { ampTo = 0; kick(); }
  screen.addEventListener('pointermove', onMove, { passive: true });
  screen.addEventListener('pointerleave', onLeave, { passive: true });

  // ---------- Opening an app: a click, a tap, Enter or Space ----------

  var lastPointer = '';
  row.addEventListener('pointerdown', function (e) { lastPointer = e.pointerType; }, { passive: true });

  function showName(el, ms) {
    named.add(el);
    el.classList.add('is-named');
    clearTimeout(el._nameTimer);
    if (ms) el._nameTimer = setTimeout(function () { if (!hops.has(el)) { named.delete(el); el.classList.remove('is-named'); } }, ms);
  }

  // The first account hands over to Claude itself: no dot of its own, so its name says where it went, for a moment.
  function opensClaude(el) {
    clearTimeout(el._restore);
    el._name.textContent = el._label + ' \u00b7 opens Claude';
    showName(el, 1400);
    el._restore = setTimeout(function () { el._name.textContent = el._label; }, 1400 + 200);
  }

  function open(el, how) {
    var plan = Dock.launch({ running: isRunning(el), opener: el.hasAttribute('data-opener') });
    el._plan = plan;
    // With a mouse the name is already there, under the pointer; a touch or a key shows it while the app opens.
    var showsName = how !== 'mouse' && how !== 'pen';
    if (!plan.bounce) { if (showsName) showName(el, 1200); return; }
    if (reduce) {
      if (plan.dot) setRunning(el, true); else { opensClaude(el); return; }
      if (showsName) showName(el, 1200);
      return;
    }
    if (hops.has(el)) return;
    clearTimeout(el._restore); el._name.textContent = el._label;
    if (showsName) showName(el, 0);
    hops.set(el, performance.now());
    kick();
  }

  apps.forEach(function (el) {
    el.addEventListener('click', function (e) {
      open(el, e.detail === 0 ? 'key' : lastPointer || 'mouse');
      lastPointer = '';
    });
    el.addEventListener('blur', function () { if (!hops.has(el)) { named.delete(el); el.classList.remove('is-named'); } });
  });

  // ---------- The keyboard: one Tab stop, the arrow keys from app to app ----------

  var current = 0;
  function rove(i, focus) {
    current = (i + apps.length) % apps.length;
    apps.forEach(function (el, k) { el.tabIndex = k === current ? 0 : -1; });
    if (focus) apps[current].focus();
  }
  rove(0, false);
  dock.setAttribute('role', 'toolbar');
  apps.forEach(function (el, k) {
    el.addEventListener('focus', function () { if (current !== k) rove(k, false); });
    el.addEventListener('keydown', function (e) {
      var to = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? k + 1 : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? k - 1 :
        e.key === 'Home' ? 0 : e.key === 'End' ? apps.length - 1 : null;
      if (to === null) return;
      e.preventDefault();
      rove(to, true);
    });
  });

  // ---------- Reduce Motion switched on mid-visit: everything lands where it rests, and stays ----------

  if (motionQuery && motionQuery.addEventListener) {
    motionQuery.addEventListener('change', function () {
      if (motionQuery.matches || reduce) return;
      reduce = true;
      amp = ampTo = ampV = 0; px = null;
      Array.from(hops.keys()).forEach(land);
      dock.classList.remove('is-moving');
      if (frame) { cancelAnimationFrame(frame); frame = 0; }
      tick(performance.now());
    });
  }

  // ---------- Arrival: Studio opens once, as the Dock comes into view ----------

  var studio = apps.filter(function (el) { return name(el) === 'Studio'; })[0];
  if (!reduce && 'IntersectionObserver' in window && studio) {
    var r0 = dock.getBoundingClientRect();
    var onScreen = r0.top < (window.innerHeight || 0) && r0.bottom > 0;
    if (!onScreen) {
      setRunning(studio, false);
      var io = new IntersectionObserver(function (entries) {
        if (!entries.some(function (en) { return en.isIntersecting; })) return;
        io.disconnect();
        // After the section's own rise has mostly landed.
        setTimeout(function () { if (!isRunning(studio)) open(studio, 'arrival'); }, 520);
      }, { threshold: 1, rootMargin: '0px 0px -12% 0px' });
      io.observe(dock);
    }
  }

  // ---------- Resize: measure again, from rest ----------

  if ('ResizeObserver' in window) {
    var queued = false;
    new ResizeObserver(function () {
      if (queued) return;
      queued = true;
      requestAnimationFrame(function () { queued = false; measure(); px = null; amp = 0; ampV = 0; ampTo = 0; kick(); });
    }).observe(screen);
  }
})();
