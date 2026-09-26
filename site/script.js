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

    // ---------- The creature as the app draws it: the same 16 by 11 grid, posed ----------

    // The app's grid (CreatureView.swift), never changed: every pose below is built from it and ends on it.
    var GRID = [
      '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..',
      'XXXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXXX',
      '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..',
      '..X..X....X..X..', '..X..X....X..X..', '..X..X....X..X..'
    ];
    function bodyPixels() {
      var out = [];
      GRID.forEach(function (row, y) { for (var x = 0; x < row.length; x++) if (row[x] === 'X') out.push({ x: x, y: y }); });
      return out;
    }
    // The right arm's cells in each pose (the app's ArmPose), mirrored for the left. `up` keeps a column of air by the head.
    var ARMS = {
      rest: [[14, 3], [15, 3], [14, 4], [15, 4], [14, 5], [15, 5]],
      lift1: [[14, 2], [15, 2], [14, 3], [15, 3], [14, 4], [15, 4]],
      up: [[14, 3], [15, 3], [15, 2], [16, 2], [15, 1], [16, 1]]
    };
    function restPose() {
      return { sx: 1, sy: 1, dy: 0, armL: 'rest', armR: 'rest', tucked: false, eyeH: 1, eyeBottom: 2, look: 0, lookDown: 0, pixels: null, sprites: [] };
    }
    // The cells a pose fills, before the body's squash and offset: the grid with its arms and legs placed.
    function poseCells(pose) {
      var cells = [];
      bodyPixels().forEach(function (p) {
        var arm = (p.x < 2 || p.x > 13) && p.y >= 3 && p.y <= 5;
        if (arm || (pose.tucked && p.y === 10)) return;
        cells.push([p.x, p.y]);
      });
      ARMS[pose.armR].forEach(function (c) { cells.push([c[0], c[1]]); });
      ARMS[pose.armL].forEach(function (c) { cells.push([15 - c[0], c[1]]); });
      return cells;
    }
    // One SVG path for a set of cells, each row's runs merged: crisp edges, no seams between cells.
    function cellsPath(cells) {
      var rows = {};
      cells.forEach(function (c) { (rows[c[1]] = rows[c[1]] || []).push(c[0]); });
      var d = '';
      Object.keys(rows).map(Number).sort(function (a, b) { return a - b; }).forEach(function (y) {
        var xs = rows[y].sort(function (a, b) { return a - b; });
        for (var i = 0; i < xs.length; i++) {
          var start = xs[i];
          while (i + 1 < xs.length && xs[i + 1] === xs[i] + 1) i++;
          d += 'M' + start + ' ' + y + 'h' + (xs[i] - start + 1) + 'v1h' + (start - xs[i] - 1) + 'z';
        }
      });
      return d;
    }

    // SwiftUI's spring in closed form: what is left of a displacement x0 (with velocity v0) t seconds later.
    function springDisp(t, response, damping, x0, v0) {
      if (t <= 0) return x0;
      var w = 2 * Math.PI / response, wd = w * Math.sqrt(1 - damping * damping);
      return Math.exp(-damping * w * t) * (x0 * Math.cos(wd * t) + (v0 + damping * w * x0) / wd * Math.sin(wd * t));
    }
    function springValue(t, response, damping) { return 1 + springDisp(t, response, damping, -1, 0); }
    function steps(t, keys, before) {
      var v = before;
      keys.forEach(function (k) { if (t >= k[0]) v = k[1]; });
      return v;
    }
    // A fixed die per cell, so every gather is the same gather.
    function hash01(x, y, salt) {
      var h = Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(salt || 0, 83492791);
      h ^= h >>> 16; h = Math.imul(h, 0x45d9f3b); h ^= h >>> 16; h = Math.imul(h, 0x45d9f3b); h ^= h >>> 16;
      return ((h >>> 0) % 10000) / 10000;
    }

    // The app's launch, "assemble" (LaunchScene.swift, AssembleScene): the exploded grid gathers inner pixels first,
    // clicks together, opens its eyes, hops 2.4 cells for joy and lands. At 1.46 s it is the rest grid, still.
    var ASSEMBLE = { assembled: 0.58, clickAt: 0.44, hopCrouch: 0.74, hopTakeoff: 0.82, hopLand: 1.12, blinkAt: 1.30, end: 1.46, hopHeight: 2.4 };
    var HOMES = bodyPixels();
    var RIM = HOMES.reduce(function (m, p) { return Math.max(m, Math.hypot(p.x + 0.5 - 8, p.y + 0.5 - 5.5)); }, 0);
    function gatherPixels(t) {
      if (t >= ASSEMBLE.assembled) return null;
      var fade = easeOut(ramp(t, 0, 0.12));
      return HOMES.map(function (p) {
        var hx = p.x + 0.5 - 8, hy = p.y + 0.5 - 5.5;
        var local = t - (0.04 + 0.14 * Math.hypot(hx, hy) / RIM + 0.04 * hash01(p.x, p.y));
        if (local >= 0.34) return { x: p.x, y: p.y, dx: 0, dy: 0, o: 1 };
        var k = local <= 0 ? 0 : springValue(local, 0.30, 0.86);
        var spread = 2.4 + 0.25 * hash01(p.x, p.y, 7);
        var m = (spread + (1 - spread) * k) * (1 + 0.12 * (1 - fade));
        var dx = hx * (m - 1), dy = hy * (m - 1);
        if (Math.abs(dx) < 0.03 && Math.abs(dy) < 0.03 && local > 0.2) return { x: p.x, y: p.y, dx: 0, dy: 0, o: 1 };
        return { x: p.x, y: p.y, dx: dx, dy: dy, o: fade };
      });
    }
    function blinkKeys(at) { return [[at, 0.5], [at + 0.04, 0.15], [at + 0.10, 0.5], [at + 0.14, 1]]; }
    function assembleFrame(t) {
      var a = ASSEMBLE, pose = restPose();
      var shadowIn = ramp(t, 0.18, 0.48);
      var f = { pose: pose, shadow: { opacity: shadowIn, inset: 6 * (1 - shadowIn) } };
      if (t >= a.end) return f;
      pose.pixels = gatherPixels(t);
      // Eyes: none on a cloud of pixels, the asleep dash from the click, then half open, then open.
      if (t < a.clickAt) pose.eyeH = 0;
      else if (t < 0.54) { pose.eyeH = 0.35; pose.eyeBottom = 2.35; }
      else pose.eyeH = steps(t, [[0.54, 0.5], [0.60, 1]], 1);
      if (t >= a.clickAt && t < 0.70) {
        var d = springDisp(t - a.clickAt, 0.30, 0.55, 0, -1.1) * (1 - ramp(t, 0.62, 0.70));
        pose.sy = 1 + d; pose.sx = 1 - 0.6 * d;
      }
      if (t >= a.hopCrouch && t < a.hopTakeoff) {
        var k = easeOut(ramp(t, a.hopCrouch, a.hopTakeoff));
        pose.sy = 1 - 0.12 * k; pose.sx = 1 + 0.07 * k; pose.eyeH = 0.5;
      } else if (t >= a.hopTakeoff && t < a.hopLand) {
        var u = (t - a.hopTakeoff) / (a.hopLand - a.hopTakeoff);
        var h = a.hopHeight * 4 * u * (1 - u);
        var stretch = 0.12 * Math.max(0, 1 - u / 0.45) + 0.04 * Math.max(0, (u - 0.7) / 0.3);
        pose.dy = -h; pose.sy = 1 + stretch; pose.sx = 1 - 0.6 * stretch;
        pose.tucked = u > 0.08 && u < 0.92;
        pose.armL = pose.armR = u > 0.05 && u < 0.9 ? 'lift1' : 'rest';
        f.shadow = { opacity: 1 - 0.35 * h / a.hopHeight, inset: h * 0.9 };
      } else if (t >= a.hopLand) {
        var dl = springDisp(t - a.hopLand, 0.34, 0.50, -0.14, 0) * (1 - ramp(t, 1.36, 1.44));
        pose.sy = 1 + dl; pose.sx = 1 - 0.7 * dl;
        pose.eyeH = steps(t, blinkKeys(a.blinkAt), 1);
      }
      return f;
    }

    // Sparkles on half cells: dot, cross, star (CreatureLife.sparkleFrames).
    var SPARKLES = [['X'], ['.X.', 'XXX', '.X.'], ['..X..', '..X..', 'XX.XX', '..X..', '..X..']];
    function sparkle(life) { return SPARKLES[life < 0.16 ? 0 : life < 0.36 ? 1 : life < 0.64 ? 2 : life < 0.84 ? 1 : 0]; }
    function spritePath(pattern, cx, cy) {
      var cells = [], h = pattern.length, w = pattern[0].length;
      pattern.forEach(function (row, j) {
        for (var i = 0; i < row.length; i++) if (row[i] === 'X') cells.push([cx + (i - w / 2) * 0.5, cy + (j - h / 2) * 0.5]);
      });
      return cells.map(function (c) { return 'M' + r3(c[0]) + ' ' + r3(c[1]) + 'h0.5v0.5h-0.5z'; }).join('');
    }
    function r3(x) { return Math.round(x * 1000) / 1000; }

    // Memory saved (CreatureLife.hop, 0.74 s): crouch, hop with the arms up, four sparkles burst at the apex and stay
    // in the air while the body falls, a springy landing, a content squint. Ends exactly on the rest grid.
    var SAVED = { duration: 0.74 };
    function savedFrame(tau, H) {
      var pose = restPose(), sx = 1, sy = 1, y = 0;
      if (tau < 0 || tau >= SAVED.duration) return pose;
      if (tau < 0.08) {
        var p0 = easeOut(tau / 0.08); sy = 1 - 0.14 * p0; sx = 1 + 0.10 * p0; pose.eyeH = 0.5;
      } else if (tau < 0.30) {
        var p1 = (tau - 0.08) / 0.22;
        y = -H * (1 - (1 - p1) * (1 - p1));
        var snap = ramp(tau, 0.08, 0.12), relax = easeOut(ramp(tau, 0.12, 0.28));
        sy = 0.86 + (1.12 - 0.12 * relax - 0.86) * snap; sx = 1.10 + (0.92 + 0.08 * relax - 1.10) * snap;
      } else if (tau < 0.44) {
        var p2 = (tau - 0.30) / 0.14; y = -H * (1 - p2 * p2);
      } else {
        var k = spring(tau - 0.44, 0.30, 0.5) * (1 - ramp(tau, 0.64, 0.74));
        sy = 1 - 0.12 * k; sx = 1 + 0.08 * k;
      }
      pose.dy = y; pose.sx = sx; pose.sy = sy;
      pose.tucked = tau >= 0.11 && tau < 0.44;
      pose.armL = pose.armR = tau < 0.10 ? 'rest' : tau < 0.15 ? 'lift1' : tau < 0.38 ? 'up' : tau < 0.47 ? 'lift1' : 'rest';
      if (tau >= 0.46 && tau < 0.62) pose.eyeH = 0.5;
      var travels = [[-9.5, 0.4], [-4.2, -2.0], [4.4, -2.2], [9.8, 0.6]];
      travels.forEach(function (tr, i) {
        var life = (tau - (0.20 + [1, 0, 2, 3][i] * 0.03)) / 0.46;
        if (life < 0 || life >= 1) return;
        var p = easeOut(life), pattern = sparkle(life);
        pose.sprites.push({ pattern: pattern, x: 8 + tr[0] * p, y: -H - 0.6 + tr[1] * p,
          light: pattern !== SPARKLES[2] && i % 2 === 1, opacity: life < 0.8 ? 1 : (1 - life) / 0.2 });
      });
      return pose;
    }

    // The hero creature's eyes, toward the reader's pointer: one whole cell sideways once the pointer is past the body,
    // one row down once it is well below (the words, the Download button). Never up: row 0 would notch the head.
    function gaze(dx, dy, cell) {
      return { x: dx < -8 * cell ? -1 : dx > 8 * cell ? 1 : 0, y: dy > 7 * cell ? 1 : 0 };
    }

    // The quick opener's search, as the app ranks it (QuickOpenerRanking.filter): the name's start, then a word's start
    // in the name, then the note; the sidebar's order within each.
    function fold(s) { return String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
    function openerRank(name, note, query) {
      var n = fold(name);
      if (n.indexOf(query) === 0) return 0;
      for (var i = 1; i < n.length; i++) {
        if (!/[\p{L}\p{N}]/u.test(n[i - 1]) && /[\p{L}\p{N}]/u.test(n[i]) && n.slice(i).indexOf(query) === 0) return 1;
      }
      if (note && fold(note).indexOf(query) !== -1) return 2;
      return null;
    }
    function openerFilter(rows, query) {
      var q = fold(query.trim());
      if (!q) return rows.slice();
      return rows.map(function (row, i) { return { row: row, rank: openerRank(row.name, row.note, q), i: i }; })
        .filter(function (x) { return x.rank !== null; })
        .sort(function (a, b) { return a.rank - b.rank || a.i - b.i; })
        .map(function (x) { return x.row; });
    }
    // The demo accounts of the page's illustrations, in the sidebar's order, with their notes and the sidebar's word.
    var DEMO = [
      { name: 'Personal', note: 'Primary', word: 'Show' },
      { name: 'Studio', note: 'Design studio', word: 'Show' },
      { name: 'Work', note: 'Day job', word: 'Open' },
      { name: 'Client', note: 'Client work', word: 'Open' }
    ];

    // The small scenes that illustrate a feature: each beat adds one class at its time (ms after the scene is in view).
    // A scene plays once. Its last beat is its still, which is also what Reduce Motion and a page without script show.
    var SCENES = {
      // The menu bar: the icon is clicked, its menu drops, the pointer goes down to Open Work.
      menu: [[0, 'b-press'], [120, 'b-open'], [480, 'b-move'], [700, 'b-h1'], [800, 'b-h2'], [900, 'b-h3']],
      // The quick opener: the shortcut, the panel, "w" then "o", Return: the panel closes and Work's window opens.
      opener: [[0, 'b-keys'], [160, 'b-open'], [760, 'b-w'], [920, 'b-wo'], [1500, 'b-return'], [1640, 'b-closed'], [1760, 'b-window']],
      // RAM and disk: the Mac's meter fills account by account, then the rows come in.
      ram: [[0, 'b-meter'], [420, 'b-rows']],
      // Check limits: the click, Claude Code is asked, its two limits come in as bars, and when.
      limits: [[0, 'b-press'], [180, 'b-asking'], [980, 'b-bars'], [1580, 'b-checked']],
      // All set: six checks pop in 60 ms apart from 0.4 s (AllSetBeat), the creature hops once they are in, then Health.
      allset: [[0, 'b-in'], [2000, 'b-health'], [2900, 'b-healthy']],
      // Connections: the account and its browser profile are paired by a thread, then its buttons show.
      conn: [[0, 'b-line'], [420, 'b-prof'], [620, 'b-btns']],
      // Tidy: File under, the two notes fly into the project's folder, the commit says so.
      tidy: [[0, 'b-press'], [260, 'b-fly'], [1320, 'b-filed']]
    };
    var ALLSET = { checksFrom: 0.4, stagger: 0.06, hop: 0.4 + 6 * 0.06 + 0.15, hopHeight: 2.25 };

    // Blocks that come on screen together rise in reading order, 60 ms apart; a long batch (a fast scroll, a tall
    // screen) never keeps the last one waiting more than 300 ms after the first.
    function batchDelays(count, base) {
      var out = [];
      for (var i = 0; i < count; i++) out.push((base || 0) + Math.min(i * 60, 300));
      return out;
    }

    return {
      clamp01: clamp01, cubicBezier: cubicBezier, easeOut: easeOut, easeMove: easeMove, spring: spring,
      ACCOUNTS: ACCOUNTS, TINT: TINT, STORY: STORY, memoryOf: memoryOf, readers: readers, storyFrame: storyFrame, lookAt: lookAt, HOP: HOP,
      GRID: GRID, bodyPixels: bodyPixels, ARMS: ARMS, restPose: restPose, poseCells: poseCells, cellsPath: cellsPath,
      springDisp: springDisp, springValue: springValue, hash01: hash01, ASSEMBLE: ASSEMBLE, gatherPixels: gatherPixels,
      assembleFrame: assembleFrame, SPARKLES: SPARKLES, spritePath: spritePath, SAVED: SAVED, savedFrame: savedFrame,
      gaze: gaze, openerFilter: openerFilter, DEMO: DEMO, SCENES: SCENES, ALLSET: ALLSET, batchDelays: batchDelays
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

  // The nav: its hairline shows once the page scrolls under it, and the link of the section being read stays lit.
  // A state, not a motion: it runs in every mode (only the underline's slide is reserved to motion).
  var nav = document.querySelector('.nav');
  if (nav) {
    var navQueued = false;
    var navScroll = function () {
      navQueued = false;
      nav.classList.toggle('is-scrolled', (window.scrollY || root.scrollTop) > 4);
    };
    window.addEventListener('scroll', function () { if (!navQueued) { navQueued = true; requestAnimationFrame(navScroll); } }, { passive: true });
    navScroll();
  }
  if (hasIO) {
    var navLinks = Array.prototype.slice.call(document.querySelectorAll('.nav-links a'));
    var here = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var link = navLinks.filter(function (a) { return a.getAttribute('href') === '#' + entry.target.id; })[0];
        if (!link) return;
        if (entry.isIntersecting) navLinks.forEach(function (a) { a.classList.toggle('is-here', a === link); });
        else link.classList.remove('is-here');
      });
    }, { rootMargin: '-40% 0px -55% 0px', threshold: 0 });
    navLinks.forEach(function (a) {
      var section = document.getElementById(a.getAttribute('href').slice(1));
      if (section) here.observe(section);
    });
  }

  if (!motionOK) return;

  // Reveals. Anything already on screen is shown after the hero has arrived; anything above it (a deep link) at once;
  // the rest rises in as it arrives. Blocks that arrive together rise one after the other in reading order, 60 ms apart.
  // All the rects are read first, then the classes written, so the loop never forces a layout per element.
  var viewport = window.innerHeight || root.clientHeight;
  var reveals = Array.prototype.slice.call(document.querySelectorAll('.reveal, .reveal-group'));
  function reveal(batch, base) {
    batch.sort(function (a, b) { return a.compareDocumentPosition(b) & 4 ? -1 : 1; });
    Motion.batchDelays(batch.length, base).forEach(function (d, i) {
      if (d) batch[i].style.setProperty('--d', d + 'ms');
      batch[i].classList.add('is-in');
    });
  }
  var seen = new IntersectionObserver(function (entries) {
    var batch = [];
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      batch.push(entry.target);
      seen.unobserve(entry.target);
    });
    if (batch.length) reveal(batch, 0);
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0 });
  var tops = reveals.map(function (el) { return el.getBoundingClientRect().top; });
  var firstView = [];
  reveals.forEach(function (el, i) {
    if (tops[i] < viewport * 0.92) firstView.push(el);
    else seen.observe(el);
  });
  // A deep link lands mid-page: what is on screen then comes in at once, never behind the hero's timing.
  reveal(firstView, window.scrollY > 40 ? 0 : 520);
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
    scenes = scenes.filter(function (el) {
      if (el.getBoundingClientRect().bottom >= 0) return true;
      finishScene(el); return false;
    });
    if (!pending.length && !scenes.length) window.removeEventListener('scroll', onScroll);
  }
  function onScroll() { if (!queued) { queued = true; requestAnimationFrame(showAbove); } }
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('load', showAbove);

  // ---------- The feature scenes ----------
  // Each plays once, when half of it is on screen, a beat after it has risen in. Its last beat is its still.

  var scenes = Array.prototype.slice.call(document.querySelectorAll('.scene[data-scene]'));
  var sceneHooks = {};
  function finishScene(el) {
    if (el.classList.contains('is-done')) return;
    el.classList.add('is-done');
    (Motion.SCENES[el.getAttribute('data-scene')] || []).forEach(function (b) { el.classList.add(b[1]); });
  }
  function playScene(el) {
    var name = el.getAttribute('data-scene'), beats = Motion.SCENES[name] || [];
    el.classList.add('is-playing');
    beats.forEach(function (b) { setTimeout(function () { el.classList.add(b[1]); }, b[0]); });
    setTimeout(function () { el.classList.add('is-done'); }, beats.length ? beats[beats.length - 1][0] + 1000 : 0);
    if (sceneHooks[name]) sceneHooks[name](el);
  }
  var sceneSeen = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.intersectionRatio < 0.5) return;
      sceneSeen.unobserve(entry.target);
      scenes = scenes.filter(function (el) { return el !== entry.target; });
      setTimeout(function () { playScene(entry.target); }, 220);
    });
  }, { threshold: [0.5] });
  scenes.forEach(function (el) { sceneSeen.observe(el); });

  // ---------- Creatures drawn frame by frame ----------

  var SVGNS = 'http://www.w3.org/2000/svg';
  var CREAM = '#F4EFE6', LIGHT = '#B487EA';
  function r3(x) { return Math.round(x * 1000) / 1000; }
  // Draws a pose into an SVG built like the page's still creatures (.cv-body, .cv-cells, .cv-eyes, .cv-shadow).
  function creatureView(svg) {
    var body = svg.querySelector('.cv-body'), cells = svg.querySelector('.cv-cells');
    var eyes = svg.querySelectorAll('.cv-eyes rect'), shadow = svg.querySelector('.cv-shadow');
    var sprites = document.createElementNS(SVGNS, 'g'), pixels = null, lastD = cells.getAttribute('d');
    sprites.setAttribute('class', 'cv-sprites');
    svg.appendChild(sprites);
    function set(el, name, value) { if (el.getAttribute(name) !== value) el.setAttribute(name, value); }
    return function draw(pose, shade) {
      var still = pose.sx === 1 && pose.sy === 1 && !pose.dy;
      set(body, 'transform', still ? '' : 'translate(0 ' + r3(pose.dy) + ') translate(8 11) scale(' + r3(pose.sx) + ' ' + r3(pose.sy) + ') translate(-8 -11)');
      if (pose.pixels) {
        if (!pixels) {
          pixels = document.createElementNS(SVGNS, 'g');
          pixels.setAttribute('fill', cells.getAttribute('fill'));
          pose.pixels.forEach(function (p) {
            var rect = document.createElementNS(SVGNS, 'rect');
            rect.setAttribute('x', p.x); rect.setAttribute('y', p.y); rect.setAttribute('width', 1); rect.setAttribute('height', 1);
            pixels.appendChild(rect);
          });
          body.insertBefore(pixels, cells);
        }
        set(cells, 'opacity', '0');
        pose.pixels.forEach(function (p, i) {
          var rect = pixels.childNodes[i];
          set(rect, 'transform', p.dx || p.dy ? 'translate(' + r3(p.dx) + ' ' + r3(p.dy) + ')' : '');
          set(rect, 'opacity', String(r3(p.o)));
        });
      } else {
        if (pixels) { pixels.parentNode.removeChild(pixels); pixels = null; }
        set(cells, 'opacity', '1');
        var d = Motion.cellsPath(Motion.poseCells(pose));
        if (d !== lastD) { cells.setAttribute('d', d); lastD = d; }
      }
      Array.prototype.forEach.call(eyes, function (eye, i) {
        set(eye, 'x', String([4, 11][i] + pose.look));
        set(eye, 'y', String(r3(pose.eyeBottom - pose.eyeH + pose.lookDown)));
        set(eye, 'height', String(Math.max(pose.eyeH, 0.01)));
        set(eye, 'opacity', pose.eyeH > 0 ? '1' : '0');
      });
      if (shadow && shade) {
        var inset = Math.min(5.5, Math.max(0, shade.inset));
        set(shadow, 'x', String(r3(2 + inset))); set(shadow, 'width', String(r3(12 - 2 * inset)));
        set(shadow, 'opacity', String(r3(shade.opacity)));
      }
      while (sprites.childNodes.length > pose.sprites.length) sprites.removeChild(sprites.lastChild);
      pose.sprites.forEach(function (s, i) {
        var path = sprites.childNodes[i];
        if (!path) { path = document.createElementNS(SVGNS, 'path'); sprites.appendChild(path); }
        set(path, 'd', Motion.spritePath(s.pattern, s.x, s.y));
        set(path, 'fill', s.light ? LIGHT : CREAM);
        set(path, 'opacity', String(r3(s.opacity)));
      });
    };
  }
  // Plays `frame(t)` (seconds) until `end`, then draws the end once more: every scene stops on its still.
  function run(end, frame, done) {
    var t0 = performance.now(), raf = 0;
    function tick() {
      var t = (performance.now() - t0) / 1000;
      frame(Math.min(t, end));
      if (t < end) raf = requestAnimationFrame(tick);
      else if (done) done();
    }
    raf = requestAnimationFrame(tick);
    return function stop() { cancelAnimationFrame(raf); };
  }
  // The memory-saved hop with sparkles, on demand: a press, or the end of the setup. Never two at once.
  function saver(draw, height, shade) {
    var busy = false;
    return function () {
      if (busy) return;
      busy = true;
      run(Motion.SAVED.duration, function (t) {
        var pose = Motion.savedFrame(t, height);
        pose.lookDown = draw.lookDown || 0;
        var air = -pose.dy / height;
        draw(pose, shade ? { opacity: 1 - 0.35 * air, inset: air * 2 } : null);
      }, function () { busy = false; });
    };
  }

  // All set: the checks pop in (styles.css), then the creature hops for the whole list, as in the app.
  var allsetSvg = document.querySelector('.scene-allset .cv');
  if (allsetSvg) {
    var allsetDraw = creatureView(allsetSvg);
    var allsetHop = saver(allsetDraw, Motion.ALLSET.hopHeight, false);
    sceneHooks.allset = function () { setTimeout(allsetHop, Motion.ALLSET.hop * 1000); };
  }

  // ---------- The download: the page's finale ----------
  // The creature assembles as the app does at launch; "Get Brainmerge." rises as the app's wordmark does; the button
  // rings once as the creature lands. Pointing at the button makes it look down; pressing it makes it hop with sparkles.
  var finale = document.querySelector('.download');
  var finaleSvg = finale && finale.querySelector('.cv');
  if (finaleSvg) {
    var finaleDraw = creatureView(finaleSvg);
    finaleDraw.lookDown = 0;
    finaleDraw(Motion.assembleFrame(0).pose, Motion.assembleFrame(0).shadow);
    var landed = false, assembled = false;
    var goFinale = new IntersectionObserver(function (entries) {
      if (!entries.some(function (e) { return e.isIntersecting; })) return;
      goFinale.disconnect();
      finale.classList.add('b-go');
      run(Motion.ASSEMBLE.end, function (t) {
        var f = Motion.assembleFrame(t);
        if (!landed && t >= Motion.ASSEMBLE.hopLand) { landed = true; finale.classList.add('b-land'); }
        finaleDraw(f.pose, f.shadow);
      }, function () { assembled = true; finale.classList.add('is-done'); });
    }, { rootMargin: '0px 0px -30% 0px', threshold: 0 });
    goFinale.observe(finaleSvg);
    var finaleHop = saver(finaleDraw, Motion.ALLSET.hopHeight, true);
    var finaleBtn = finale.querySelector('.btn-primary');
    var restLook = function (down) {
      finaleDraw.lookDown = down;
      if (assembled) { var p = Motion.restPose(); p.lookDown = down; finaleDraw(p, { opacity: 1, inset: 0 }); }
    };
    if (finaleBtn) {
      if (window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
        finaleBtn.addEventListener('pointerenter', function () { restLook(1); });
        finaleBtn.addEventListener('pointerleave', function () { restLook(0); });
      }
      finaleBtn.addEventListener('focus', function () { restLook(1); });
      finaleBtn.addEventListener('blur', function () { restLook(0); });
      finaleBtn.addEventListener('pointerdown', function () { if (assembled) finaleHop(); });
      finaleBtn.addEventListener('keydown', function (e) { if (assembled && e.key === 'Enter') finaleHop(); });
    }
  }

  // The download arrow drops into its tray once per click: the file is on its way. The download itself never waits.
  Array.prototype.slice.call(document.querySelectorAll('.btn-dl')).forEach(function (btn) {
    btn.addEventListener('click', function () {
      btn.classList.remove('is-going');
      void btn.offsetWidth; // restart the drop on a second click
      btn.classList.add('is-going');
    });
    btn.addEventListener('animationend', function (e) { if (e.animationName === 'dl-drop') btn.classList.remove('is-going'); });
  });

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
    // Once awake, its eyes follow the reader's pointer, a whole cell at a time. The first move ends its idle glance,
    // so the eyes never move twice at once. Only while the hero is on screen, and only for a mouse or a trackpad.
    var cell = function () { return creature.getBoundingClientRect().width / 16; };
    var gazeOn = false, gazeQueued = false, lastEvent = null, gazeKey = '';
    var applyGaze = function () {
      gazeQueued = false;
      if (!lastEvent) return;
      var box = creature.getBoundingClientRect(), c = box.width / 16;
      var g = Motion.gaze(lastEvent.clientX - (box.left + 8 * c), lastEvent.clientY - (box.top + box.height / 2), c);
      var key = g.x + ',' + g.y;
      if (key === gazeKey) return;
      if (!gazeKey) creature.querySelectorAll('.cr-eyes, .cr-blink, .cr-blink-shut').forEach(function (el) {
        el.getAnimations().forEach(function (a) { a.finish(); });
      });
      gazeKey = key;
      creature.classList.toggle('gx-l', g.x < 0);
      creature.classList.toggle('gx-r', g.x > 0);
      creature.classList.toggle('gy-d', g.y > 0);
    };
    var onPointer = function (e) {
      lastEvent = e;
      if (!gazeQueued) { gazeQueued = true; requestAnimationFrame(applyGaze); }
    };
    if (window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
      setTimeout(function () {
        new IntersectionObserver(function (entries) {
          var on = entries[entries.length - 1].isIntersecting;
          if (on === gazeOn) return;
          gazeOn = on;
          if (on) document.addEventListener('pointermove', onPointer, { passive: true });
          else document.removeEventListener('pointermove', onPointer);
        }).observe(creature);
      }, 2300);
    }
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
