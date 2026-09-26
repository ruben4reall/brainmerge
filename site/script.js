// Brainmerge: the creature waking up, the "How it works" story, gentle reveals and the timeline lighting up.
// Everything is visible without this file. With Reduce Motion it only sets each scene's still.
(function () {
  'use strict';

  // ---------- Pure motion functions (no DOM: tested in Node) ----------

  var Motion = (function () {
    function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }

    // CSS cubic-bezier(x1, y1, x2, y2) as a function of progress 0..1.
    function cubicBezier(x1, y1, x2, y2) {
      function a(p1, p2) { return 1 - 3 * p2 + 3 * p1; }
      function b(p1, p2) { return 3 * p2 - 6 * p1; }
      function c(p1) { return 3 * p1; }
      function at(t, p1, p2) { return ((a(p1, p2) * t + b(p1, p2)) * t + c(p1)) * t; }
      function slope(t, p1, p2) { return 3 * a(p1, p2) * t * t + 2 * b(p1, p2) * t + c(p1); }
      return function (x) {
        x = clamp01(x);
        if (x === 0 || x === 1) return x;
        var t = x;
        for (var i = 0; i < 8; i++) {
          var s = slope(t, x1, x2);
          if (Math.abs(s) < 1e-6) break;
          t -= (at(t, x1, x2) - x) / s;
        }
        if (!(t >= 0 && t <= 1) || Math.abs(at(t, x1, x2) - x) > 1e-5) {
          var lo = 0, hi = 1; t = x;
          for (var j = 0; j < 40; j++) {
            var v = at(t, x1, x2);
            if (Math.abs(v - x) < 1e-7) break;
            if (v < x) lo = t; else hi = t;
            t = (lo + hi) / 2;
          }
        }
        return at(t, y1, y2);
      };
    }

    // The app's tokens (Theme.Motion): arrivals and feedback, then things travelling on screen.
    var easeOut = cubicBezier(0.23, 1, 0.32, 1);
    var easeMove = cubicBezier(0.77, 0, 0.175, 1);

    // What is left of a displacement `t` seconds after release, for a SwiftUI-style spring
    // (response in seconds, damping fraction below 1): 1 at t = 0, settling to 0.
    function spring(t, response, damping) {
      if (t <= 0) return 1;
      var w = 2 * Math.PI / response;
      var wd = w * Math.sqrt(1 - damping * damping);
      return Math.exp(-damping * w * t) * (Math.cos(wd * t) + (damping * w / wd) * Math.sin(wd * t));
    }

    function ramp(t, from, to) { return clamp01((t - from) / (to - from)); }

    // The app's accounts, in their app colors (Theme.color(for: .orange, .pink, .blue)), top to bottom on the page.
    var ACCOUNTS = ['p', 's', 'w'];
    var TINT = { p: '#D97757', s: '#D97A8E', w: '#6FA3D8' };
    // Three beats of 2.4 s, as in the app: Personal saves, then Work, then Studio. Played once, then still.
    var STORY = {
      beat: 2.4,
      order: ['p', 'w', 's'],
      end: 7.4,
      // The still for Reduce Motion and captures: a note has landed, its copies are on their way to the others.
      hero: { shared: 1.7, each: 2.4 + 1.7 }
    };

    function memoryOf(acc, mode) { return mode === 'each' && acc === 'w' ? 'work' : 'shared'; }
    function readers(src, mode) {
      return ACCOUNTS.filter(function (a) { return a !== src && memoryOf(a, mode) === memoryOf(src, mode); });
    }

    // Everything the diagram shows at time t (seconds since the story started) in `mode` ("shared" or "each").
    function storyFrame(t, mode) {
      var f = {
        orbs: { p: 1, s: 1, w: 1 },
        rings: { p: null, s: null, w: null },
        lit: { p: 0, s: 0, w: 0 },
        // Whose note lights each lane: a lit lane takes the writer's tint.
        litBy: { p: null, s: null, w: null },
        notes: [],
        slots: { shared: [], work: [] },
        flash: { shared: 0, work: 0 },
        creature: { look: null, armsUp: false, sx: 1, sy: 1 }
      };
      if (!(t >= 0)) return f;
      function light(acc, value, src) {
        if (value > f.lit[acc]) { f.lit[acc] = value; f.litBy[acc] = src; }
      }
      for (var b = 0; b < STORY.order.length; b++) {
        var tau = t - b * STORY.beat;
        if (tau < 0) break;
        var src = STORY.order[b];
        var box = memoryOf(src, mode);
        // Its bar in the memory: grows as the note lands, then turns from the account's tint to cream.
        if (tau >= 1.0) {
          f.slots[box].push({ acc: src, grow: easeOut(ramp(tau, 1.0, 1.2)), cream: ramp(tau, 1.2, 1.8) });
        }
        if (tau > 2.6) continue;
        var dests = readers(src, mode);
        // The account's Claude Code writes: its orb pops.
        if (tau <= 0.25) f.orbs[src] = 1 + 0.08 * Math.sin(Math.PI * tau / 0.25);
        // The note travels its lane into the memory.
        if (tau >= 0.1 && tau < 1.08) {
          var inOp = Math.min(1, (tau - 0.1) / 0.12) * (tau > 1.0 ? 1 - (tau - 1.0) / 0.08 : 1);
          f.notes.push({ acc: src, lane: src, dir: 'in', p: easeMove(ramp(tau, 0.1, 1.0)), opacity: clamp01(inOp) });
        }
        light(src, ramp(tau, 0.1, 0.25) * (1 - ramp(tau, 1.0, 1.15)), src);
        if (tau >= 1.0 && tau <= 1.3) f.flash[box] = Math.sin(Math.PI * (tau - 1.0) / 0.3);
        // The creature lives on the shared memory: it looks at the writer, lifts its arms and catches the note.
        if (box === 'shared') {
          if (tau >= 0.75 && tau < 1.2) f.creature.armsUp = true;
          if (tau >= 1.0 && tau < 1.8) {
            var d = tau - 1.0, k;
            if (d < 0.09) { k = d / 0.09; } else { k = spring(d - 0.09, 0.28, 0.55); }
            f.creature.sy = 1 - 0.1 * k;
            f.creature.sx = 1 + 0.06 * k;
          }
        }
        if (tau >= 0.35 && tau < 1.25) f.creature.look = src;
        else if (tau >= 1.25 && tau < 2.3 && dests.length) f.creature.look = dests[0];
        // The others read it: a copy of the note reaches each of them, and rings their orb.
        dests.forEach(function (dest, j) {
          var start = 1.25 + 0.1 * j;
          var u = (tau - start) / 0.8;
          if (u >= 0 && u < 1.125) {
            // Opaque, like the note it copies: a see-through page would show its lit lane through it.
            var op = Math.min(1, (tau - start) / 0.1) * (u > 1 ? 1 - (u - 1) / 0.125 : 1);
            f.notes.push({ acc: src, lane: dest, dir: 'out', p: easeMove(clamp01(u)), opacity: clamp01(op) });
          }
          light(dest, ramp(tau, start - 0.05, start + 0.1) * (1 - ramp(tau, start + 0.8, start + 0.95)), src);
          var dd = tau - (start + 0.8);
          // A ping around the reader's orb, 22 to 32 units: wide enough to read, short of the account's name.
          if (dd >= 0 && dd < 0.5) f.rings[dest] = { acc: src, scale: 1 + 0.45 * easeOut(dd / 0.5), opacity: 0.7 * (1 - dd / 0.5) };
        });
      }
      return f;
    }

    // Where the creature's eyes go, one cell at most, toward a point dx, dy away (SVG units).
    function lookAt(dx, dy) {
      // Never up: on row 0 an eye would notch the top edge and change the silhouette.
      return { x: dx < -24 ? -1 : dx > 24 ? 1 : 0, y: dy > 40 ? 1 : 0 };
    }

    // The hero creature's hop on demand (720 ms): crouch, stretch up three cells, fall, land squashed, rebound.
    var HOP = {
      duration: 720,
      body: [
        { offset: 0, transform: 'none', easing: 'cubic-bezier(0.23, 1, 0.32, 1)' },
        { offset: 0.17, transform: 'scale(1.08, 0.9)', easing: 'cubic-bezier(0.23, 1, 0.32, 1)' },
        { offset: 0.39, transform: 'translateY(-3px) scale(0.94, 1.07)', easing: 'cubic-bezier(0.33, 0, 0.67, 1)' },
        { offset: 0.5, transform: 'translateY(-3.2px)', easing: 'cubic-bezier(0.55, 0, 1, 0.45)' },
        { offset: 0.67, transform: 'scale(1.1, 0.88)', easing: 'cubic-bezier(0.23, 1, 0.32, 1)' },
        { offset: 0.83, transform: 'scale(0.97, 1.03)', easing: 'cubic-bezier(0.45, 0, 0.55, 1)' },
        { offset: 1, transform: 'none' }
      ],
      arms: [
        { offset: 0, transform: 'none' },
        { offset: 0.39, transform: 'none' },
        { offset: 0.39, transform: 'translateY(-1px)' },
        { offset: 0.67, transform: 'translateY(-1px)' },
        { offset: 0.67, transform: 'none' },
        { offset: 1, transform: 'none' }
      ],
      shadow: [
        { offset: 0, opacity: 0, transform: 'none' },
        { offset: 0.17, opacity: 1, transform: 'none' },
        { offset: 0.39, opacity: 0.55, transform: 'scaleX(0.75)' },
        { offset: 0.5, opacity: 0.55, transform: 'scaleX(0.75)' },
        { offset: 0.67, opacity: 1, transform: 'scaleX(1.05)' },
        { offset: 1, opacity: 0, transform: 'none' }
      ]
    };

    return {
      clamp01: clamp01, cubicBezier: cubicBezier, easeOut: easeOut, easeMove: easeMove, spring: spring,
      ACCOUNTS: ACCOUNTS, TINT: TINT, STORY: STORY, memoryOf: memoryOf, readers: readers, storyFrame: storyFrame, lookAt: lookAt, HOP: HOP
    };
  })();

  if (typeof window === 'undefined') {
    if (typeof module !== 'undefined') module.exports = Motion;
    return;
  }

  // ---------- The page ----------

  var root = document.documentElement;
  root.classList.add('has-js');
  var reduce = !window.matchMedia || !window.matchMedia('(prefers-reduced-motion: no-preference)').matches;
  var hasIO = 'IntersectionObserver' in window;
  var motionOK = !reduce && hasIO;
  if (motionOK) root.classList.add('js');

  // iOS Safari applies :active (the button press) only when a touch listener exists.
  document.addEventListener('touchstart', function () {}, { passive: true });

  // How it works: runs in every mode, since the toggle works with Reduce Motion too.
  Array.prototype.slice.call(document.querySelectorAll('.flow-fig')).forEach(function (fig) { flow(fig); });

  if (!motionOK) return;

  // Reveals. Anything already on screen, or above it (a deep link), is shown at once; the rest rises in as it arrives.
  // All the rects are read first, then the classes written, so the loop never forces a layout per element.
  var viewport = window.innerHeight || root.clientHeight;
  var reveals = Array.prototype.slice.call(document.querySelectorAll('.reveal, .reveal-group'));
  var seen = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-in');
      seen.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0 });
  var tops = reveals.map(function (el) { return el.getBoundingClientRect().top; });
  reveals.forEach(function (el, i) {
    if (tops[i] < viewport * 0.92) el.classList.add('is-in');
    else seen.observe(el);
  });
  // A deep link can jump past blocks after this ran: anything left above the screen shows at once, never rising later.
  var pending = reveals.filter(function (el) { return !el.classList.contains('is-in'); });
  var queued = false;
  function showAbove() {
    queued = false;
    var above = pending.map(function (el) { return el.getBoundingClientRect().bottom < 0; });
    pending = pending.filter(function (el, i) {
      if (!above[i]) return !el.classList.contains('is-in');
      el.classList.add('is-in'); seen.unobserve(el); return false;
    });
    if (!pending.length) window.removeEventListener('scroll', onScroll);
  }
  function onScroll() { if (!queued) { queued = true; requestAnimationFrame(showAbove); } }
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('load', showAbove);

  // Each remembered sentence lights up in its account's color as it reaches the upper two thirds, and stays lit.
  // A fast scroll can bring several at once: they still light one by one, 180 ms apart, like separate saves.
  var queue = [], busy = false;
  function next() {
    var el = queue.shift();
    if (!el) { busy = false; return; }
    busy = true;
    el.classList.add('lit');
    setTimeout(next, 180);
  }
  var lit = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      queue.push(entry.target);
      lit.unobserve(entry.target);
    });
    if (!busy) next();
  }, { rootMargin: '0px 0px -32% 0px', threshold: 0 });
  Array.prototype.slice.call(document.querySelectorAll('.said li')).forEach(function (el) { lit.observe(el); });

  // The hero creature: it wakes up on its own (styles.css). Here, only what answers the visitor.
  var creature = document.querySelector('.hero .creature');
  if (creature && creature.animate) {
    var hopping = false, lastHop = 0;
    var parts = { body: creature.querySelector('.cr-hop'), arms: creature.querySelector('.cr-arms'), shadow: creature.querySelector('.cr-shadow') };
    var hop = function () {
      var now = Date.now();
      if (hopping || now - lastHop < 900) return;
      hopping = true; lastHop = now;
      var a = parts.body.animate(Motion.HOP.body, { duration: Motion.HOP.duration });
      parts.arms.animate(Motion.HOP.arms, { duration: Motion.HOP.duration });
      parts.shadow.animate(Motion.HOP.shadow, { duration: Motion.HOP.duration });
      a.onfinish = a.oncancel = function () { hopping = false; };
    };
    var finePointer = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
    creature.addEventListener('click', hop);
    if (finePointer) creature.addEventListener('pointerenter', hop);
    var download = document.querySelector('.hero .btn-primary');
    if (download) {
      var look = function () { creature.classList.add('is-looking'); };
      var away = function () { creature.classList.remove('is-looking'); };
      if (finePointer) {
        download.addEventListener('pointerenter', look);
        download.addEventListener('pointerleave', away);
      }
      download.addEventListener('focus', look);
      download.addEventListener('blur', away);
      download.addEventListener('pointerdown', hop);
    }
  }

  // ---------- How it works ----------

  function flow(fig) {
    var TINT = Motion.TINT, ACCOUNTS = Motion.ACCOUNTS;
    var story = Motion.STORY;
    var views = Array.prototype.slice.call(fig.querySelectorAll('svg.flow')).map(view);
    var mode = fig.getAttribute('data-mode') || 'shared';
    var playBtn = fig.querySelector('.flow-play');
    var opts = Array.prototype.slice.call(fig.querySelectorAll('.flow-opt'));
    var t0 = 0, offset = 0, raf = 0, state = 'idle'; // idle, playing, paused, done

    function num(s) { return s.split(/[\s,()a-z]+/i).filter(Boolean).map(Number); }
    function view(svg) {
      var q = function (sel) { return svg.querySelector(sel); };
      var v = { svg: svg, lanes: { shared: {}, each: {} }, lit: { shared: {}, each: {} }, orbs: {}, rings: {}, slots: { shared: [], work: [] }, flash: {}, notes: [] };
      ['shared', 'each'].forEach(function (m) {
        ACCOUNTS.forEach(function (a) {
          var lane = q('.fl-lane[data-mode="' + m + '"][data-acc="' + a + '"]');
          v.lanes[m][a] = { el: lane, len: lane.getTotalLength() };
          v.lit[m][a] = q('.fl-lit[data-mode="' + m + '"][data-acc="' + a + '"]');
        });
      });
      ACCOUNTS.forEach(function (a) {
        var orb = q('.fl-account[data-acc="' + a + '"] .fl-orb');
        var ring = q('.fl-account[data-acc="' + a + '"] .fl-ring');
        v.orbs[a] = { el: orb, at: num(orb.getAttribute('transform')).slice(0, 2) };
        v.rings[a] = { el: ring, circle: ring.querySelector('circle'), at: num(ring.getAttribute('transform')).slice(0, 2) };
      });
      ['shared', 'work'].forEach(function (b) {
        var g = q('.fl-box[data-box="' + b + '"]');
        v.flash[b] = g.querySelector('.fl-flash');
        Array.prototype.slice.call(g.querySelectorAll('.fl-slot')).forEach(function (slot) {
          v.slots[b].push({ el: slot, at: num(slot.getAttribute('transform')).slice(0, 2), tint: slot.querySelector('.fl-bar-tint'), cream: slot.querySelector('.fl-bar-cream') });
        });
      });
      Array.prototype.slice.call(svg.querySelectorAll('.fl-note-slot')).forEach(function (slot) {
        var byAcc = {};
        Array.prototype.slice.call(slot.querySelectorAll('.fl-note')).forEach(function (n) { byAcc[n.getAttribute('data-acc')] = n; });
        v.notes.push({ el: slot, byAcc: byAcc });
      });
      var cr = q('.fl-creature');
      var crAt = num(cr.getAttribute('transform'));
      v.creature = { sprite: q('.fl-cr-sprite'), arms: q('.fl-cr-arms'), eyes: q('.fl-cr-eyes'), cx: crAt[0] + 8 * crAt[2], cy: crAt[1] + 4 * crAt[2] };
      return v;
    }

    function set(el, name, value) { if (el.getAttribute(name) !== value) el.setAttribute(name, value); }
    function r(x) { return Math.round(x * 1000) / 1000; }

    function paint(f) {
      views.forEach(function (v) {
        ACCOUNTS.forEach(function (a) {
          var o = v.orbs[a];
          set(o.el, 'transform', 'translate(' + o.at[0] + ' ' + o.at[1] + ')' + (f.orbs[a] !== 1 ? ' scale(' + r(f.orbs[a]) + ')' : ''));
          var ring = v.rings[a], rf = f.rings[a];
          set(ring.el, 'opacity', rf ? String(r(rf.opacity)) : '0');
          if (rf) {
            set(ring.el, 'transform', 'translate(' + ring.at[0] + ' ' + ring.at[1] + ') scale(' + r(rf.scale) + ')');
            set(ring.circle, 'stroke', TINT[rf.acc]);
          }
          set(v.lit.shared[a], 'opacity', mode === 'shared' ? String(r(f.lit[a])) : '0');
          set(v.lit.each[a], 'opacity', mode === 'each' ? String(r(f.lit[a])) : '0');
          // A lit lane glows in the tint of the account whose note travels it (attributes only: CSP safe).
          if (f.litBy[a]) {
            var litLane = v.lit[mode][a];
            set(litLane, 'stroke', TINT[f.litBy[a]]);
            set(litLane, 'stroke-opacity', '0.85');
          }
        });
        ['shared', 'work'].forEach(function (b) {
          set(v.flash[b], 'opacity', String(r(f.flash[b])));
          v.slots[b].forEach(function (slot, i) {
            var s = f.slots[b][i];
            if (!s) { set(slot.tint, 'opacity', '0'); set(slot.cream, 'opacity', '0'); return; }
            set(slot.el, 'transform', 'translate(' + slot.at[0] + ' ' + slot.at[1] + ') scale(' + r(s.grow) + ' 1)');
            set(slot.tint, 'fill', TINT[s.acc]);
            set(slot.tint, 'opacity', String(r(1 - s.cream)));
            set(slot.cream, 'opacity', String(r(0.35 * s.cream)));
          });
        });
        v.notes.forEach(function (slot, i) {
          var n = f.notes[i];
          set(slot.el, 'opacity', n ? String(r(n.opacity)) : '0');
          if (!n) return;
          ACCOUNTS.forEach(function (a) { set(slot.byAcc[a], 'opacity', a === n.acc ? '1' : '0'); });
          var lane = v.lanes[mode][n.lane];
          var pt = lane.el.getPointAtLength((n.dir === 'in' ? n.p : 1 - n.p) * lane.len);
          set(slot.el, 'transform', 'translate(' + r(pt.x) + ' ' + r(pt.y) + ')');
        });
        var c = v.creature, cf = f.creature;
        set(c.sprite, 'transform', cf.sx === 1 && cf.sy === 1 ? '' : 'translate(8 11) scale(' + r(cf.sx) + ' ' + r(cf.sy) + ') translate(-8 -11)');
        set(c.arms, 'transform', cf.armsUp ? 'translate(0 -1)' : '');
        var eye = { x: 0, y: 0 };
        if (cf.look) { var o2 = v.orbs[cf.look].at; eye = Motion.lookAt(o2[0] - c.cx, o2[1] - c.cy); }
        set(c.eyes, 'transform', eye.x || eye.y ? 'translate(' + eye.x + ' ' + eye.y + ')' : '');
      });
    }

    function label() {
      if (!playBtn) return;
      playBtn.hidden = reduce || state === 'idle';
      playBtn.textContent = state === 'playing' ? 'Pause' : state === 'paused' ? 'Play' : 'Play again';
    }
    function tick() {
      // performance.now(), not the frame's timestamp: both clocks then agree (pause, resume, captures).
      var t = (performance.now() - t0) / 1000;
      if (t >= story.end) { paint(Motion.storyFrame(story.end, mode)); state = 'done'; raf = 0; label(); return; }
      paint(Motion.storyFrame(t, mode));
      raf = requestAnimationFrame(tick);
    }
    function play(from) {
      cancelAnimationFrame(raf);
      t0 = performance.now() - from * 1000;
      state = 'playing'; label();
      raf = requestAnimationFrame(tick);
    }
    function pause() {
      if (state !== 'playing') return;
      cancelAnimationFrame(raf); raf = 0;
      offset = (performance.now() - t0) / 1000;
      state = 'paused'; label();
    }

    function setMode(m) {
      mode = m;
      fig.setAttribute('data-mode', m);
      opts.forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-mode') === m)); });
      if (reduce || !hasIO) { paint(Motion.storyFrame(reduce ? story.hero[m] : story.end, m)); return; }
      // The boxes move for 420 ms; the story starts over once they have settled.
      if (state === 'idle') { paint(Motion.storyFrame(-1, m)); return; }
      play(-0.45);
    }
    opts.forEach(function (b) { b.addEventListener('click', function () { setMode(b.getAttribute('data-mode')); }); });
    if (playBtn) playBtn.addEventListener('click', function () {
      if (state === 'playing') pause();
      else if (state === 'paused') play(offset);
      else play(0);
    });

    if (reduce || !hasIO) { paint(Motion.storyFrame(reduce ? story.hero[mode] : story.end, mode)); label(); return; }
    paint(Motion.storyFrame(-1, mode));
    // It plays once, when 40% of it is on screen, and waits (paused) while it is scrolled away.
    var autoPaused = false;
    new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.intersectionRatio >= 0.4 && state === 'idle') play(0);
        else if (!entry.isIntersecting && state === 'playing') { pause(); autoPaused = true; }
        else if (entry.intersectionRatio >= 0.4 && state === 'paused' && autoPaused) { autoPaused = false; play(offset); }
      });
    }, { threshold: [0, 0.4] }).observe(fig);
  }
})();

// Page views for the owner's own counter: no cookie, no identifier, only the page and where the visit came from.
(function () {
  if (location.hostname !== 'brainmerge.vercel.app') return;
  var endpoint = 'https://ruben-analytics.vercel.app/api/hit';
  var body = JSON.stringify({ site: 'brainmerge', path: location.pathname, ref: document.referrer });
  try {
    if (!navigator.sendBeacon(endpoint, body)) throw new Error('beacon');
  } catch (e) {
    fetch(endpoint, { method: 'POST', body: body, keepalive: true }).catch(function () {});
  }
})();
