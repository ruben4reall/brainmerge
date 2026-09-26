// Brainmerge: the reading companion. The hero creature assembles as the app does at launch (LaunchScene.swift), leaps
// onto its perch once the hero scrolls away (the app's leap into the sidebar footer): in the nav bar, or beside the
// column on wide screens. It walks as the page moves under it, answers what is on screen with the app's own repertoire
// (CreatureLife.swift), and leaps into the finale to stand above Download. There is only ever one creature. Decorative:
// it never takes the focus, never covers text or a button, and with Reduce Motion the hero creature is simply there.
(function () {
  'use strict';

  // ---------- Pure functions (no DOM: tested in Node) ----------

  var C = (function () {
    function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
    function lerp(a, b, p) { return a + (b - a) * p; }
    // 0 before `from`, 1 after `from + over`, linear in between (Ease.progress).
    function progress(t, from, over) { return over <= 0 ? (t >= from ? 1 : 0) : clamp01((t - from) / over); }
    // Stepped values for pixel art: the value of the last key at or before t (Ease.steps).
    function steps(t, keys, before) {
      var v = before;
      for (var i = 0; i < keys.length; i++) if (t >= keys[i][0]) v = keys[i][1];
      return v;
    }
    function sign(x) { return x > 0 ? 1 : x < 0 ? -1 : 0; }
    // On the half-cell grid of the sprites: a pixel sprite never lands between pixels, so it never shimmers.
    function half(v) { return Math.round(v * 2) / 2; }

    // CSS cubic-bezier, solved for x with Newton's method, then bisection (Ease.Bezier, the WebKit approach).
    function bezier(x1, y1, x2, y2) {
      function sample(a1, a2, s) { var u = 1 - s; return 3 * u * u * s * a1 + 3 * u * s * s * a2 + s * s * s; }
      function slope(s) { var u = 1 - s; return 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2); }
      return function (x) {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        var s = x;
        for (var i = 0; i < 8; i++) {
          var err = sample(x1, x2, s) - x;
          if (Math.abs(err) < 1e-7) return sample(y1, y2, s);
          var d = slope(s);
          if (Math.abs(d) < 1e-6) break;
          s = Math.min(1, Math.max(0, s - err / d));
        }
        var lo = 0, hi = 1;
        s = x;
        for (var j = 0; j < 50; j++) {
          var v = sample(x1, x2, s);
          if (Math.abs(v - x) < 1e-9) break;
          if (v < x) lo = s; else hi = s;
          s = (lo + hi) / 2;
        }
        return sample(y1, y2, s);
      };
    }
    // The app's curves (Motion.swift).
    var Ease = {
      out: bezier(0.23, 1, 0.32, 1),
      inOut: bezier(0.77, 0, 0.175, 1),
      breath: bezier(0.45, 0, 0.55, 1),
      shrink: bezier(0.45, 0, 0.25, 1),
      travel: bezier(0.33, 0.33, 0.55, 1)
    };

    // A damped spring in SwiftUI's terms (Ease.Spring): what is left of a displacement x0, with a velocity v0, t seconds on.
    function springDisp(t, response, damping, x0, v0) {
      v0 = v0 || 0;
      if (t <= 0) return x0;
      var w = 2 * Math.PI / response, z = damping;
      if (z < 1) {
        var wd = w * Math.sqrt(1 - z * z);
        return Math.exp(-z * w * t) * (x0 * Math.cos(wd * t) + (v0 + z * w * x0) / wd * Math.sin(wd * t));
      }
      return (x0 + (v0 + w * x0) * t) * Math.exp(-w * t);
    }
    function springValue(t, response, damping) { return 1 + springDisp(t, response, damping, -1, 0); }
    // 1 at the start, ringing down to 0 (Ease.ringDown).
    function ringDown(t, response, damping) { return 1 - springValue(t, response, damping); }
    // When the ringing stays within `band` for good (Ease.Spring.settleTime, under-damped).
    function settleTime(response, damping, x0, v0, band) {
      var w = 2 * Math.PI / response, z = damping, wd = w * Math.sqrt(1 - z * z);
      var amp = Math.sqrt(x0 * x0 + Math.pow((v0 + z * w * x0) / wd, 2));
      return amp > band ? Math.log(amp / band) / (z * w) : 0;
    }

    // The app's die per pixel (Dice.hash01), in 64-bit integers: every gather is the app's gather.
    function hash01(x, y, salt) {
      salt = salt || 0;
      if (typeof BigInt !== 'function') {
        var k = Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(salt, 83492791);
        k ^= k >>> 16; k = Math.imul(k, 0x45d9f3b); k ^= k >>> 16;
        return ((k >>> 0) % 10000) / 10000;
      }
      var B = BigInt, s33 = B(33);
      var h = B.asUintN(64, B.asIntN(64, B(x) * B(73856093)) ^ B.asIntN(64, B(y) * B(19349663)) ^ B.asIntN(64, B(salt) * B(83492791)));
      h ^= h >> s33; h = B.asUintN(64, h * B('0xff51afd7ed558ccd'));
      h ^= h >> s33; h = B.asUintN(64, h * B('0xc4ceb9fe1a85ec53'));
      h ^= h >> s33;
      return Number(h % B(10000)) / 10000;
    }

    // ---------- The creature: the app's 16 by 11 grid (CreatureView.swift), never changed ----------

    var GRID = [
      '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..',
      'XXXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXXX',
      '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..',
      '..X..X....X..X..', '..X..X....X..X..', '..X..X....X..X..'
    ];
    var COLS = 16, ROWS = 11;
    function bodyPixels() {
      var out = [];
      GRID.forEach(function (row, y) { for (var x = 0; x < row.length; x++) if (row[x] === 'X') out.push({ x: x, y: y }); });
      return out;
    }
    var PIXELS = bodyPixels();
    // The legs (the last row's filled columns), where they start (8), the arms (outside the head's columns).
    var LEGS = [2, 5, 10, 13], LEG_TOP = 8, LAST = ROWS - 1;
    function isArmColumn(x) { return x < 2 || x > 13; }
    // The right arm's cells in each pose (ArmPose); the left arm is the mirror (x to 15 - x).
    var ARMS = {
      rest: [[14, 3], [15, 3], [14, 4], [15, 4], [14, 5], [15, 5]],
      lift1: [[14, 2], [15, 2], [14, 3], [15, 3], [14, 4], [15, 4]],
      up: [[14, 3], [15, 3], [15, 2], [16, 2], [15, 1], [16, 1]]
    };
    // Everything a frame can vary (Creature.Pose). At its defaults it draws exactly the grid. Offsets in cells, rot in
    // degrees, squash about the middle of the feet (8, 11).
    function restPose() {
      return {
        dx: 0, dy: 0, sx: 1, sy: 1, rot: 0, raise: 0, lifted: [false, false, false, false], tucked: false,
        armL: 'rest', armR: 'rest', eyeH: 1, eyeBottom: 2, look: 0, lookDown: 0, opacity: 1, pixels: null, sprites: []
      };
    }
    function copyPose(p) {
      var q = {};
      for (var k in p) q[k] = p[k];
      q.lifted = p.lifted.slice();
      q.sprites = p.sprites.slice();
      return q;
    }
    // The cells a pose fills, [x, y, width, height] in grid cells (Creature.parts): the walk raises the body whole rows
    // and stretches the top leg row to the ground; a lifted or tucked leg loses its bottom row; a raised arm leaves the grid.
    function poseCells(pose) {
      var out = [], raise = pose.raise;
      PIXELS.forEach(function (p) {
        if (p.y >= LEG_TOP) {
          var leg = LEGS.indexOf(p.x);
          if (leg < 0) return;
          if (p.y === LAST && (pose.tucked || pose.lifted[leg])) return;
          if (p.y === LEG_TOP) { if (1 + raise > 0) out.push([p.x, LEG_TOP - raise, 1, 1 + raise]); return; }
          out.push([p.x, p.y, 1, 1]);
          return;
        }
        if (isArmColumn(p.x) && (p.x < 8 ? pose.armL : pose.armR) !== 'rest') return;
        out.push([p.x, p.y - raise, 1, 1]);
      });
      if (pose.armR !== 'rest') ARMS[pose.armR].forEach(function (c) { out.push([c[0], c[1] - raise, 1, 1]); });
      if (pose.armL !== 'rest') ARMS[pose.armL].forEach(function (c) { out.push([15 - c[0], c[1] - raise, 1, 1]); });
      return out;
    }
    // The eyes (Creature.eyeRects), none at a height of 0 (the gathering cloud). Horizontal looks only: row 0 is never an eye.
    function eyeRects(pose) {
      if (!(pose.eyeH > 0)) return [];
      var bottom = pose.eyeBottom - pose.raise + pose.lookDown;
      return [4, 11].map(function (x) { return [x + pose.look, bottom - pose.eyeH, 1, pose.eyeH]; });
    }
    function r3(x) { return Math.round(x * 1000) / 1000; }
    // One path for all the cells, each row's runs of same-height cells merged: one fill, no seams between cells.
    function cellsPath(cells) {
      var rows = {};
      cells.forEach(function (c) { var k = c[1] + ':' + c[3]; (rows[k] = rows[k] || []).push(c[0]); });
      var d = '';
      Object.keys(rows).sort(function (a, b) { return parseFloat(a) - parseFloat(b); }).forEach(function (k) {
        var y = parseFloat(k), h = parseFloat(k.split(':')[1]);
        var xs = rows[k].sort(function (a, b) { return a - b; });
        for (var i = 0; i < xs.length; i++) {
          var start = xs[i];
          while (i + 1 < xs.length && xs[i + 1] <= xs[i] + 1) i++;
          var w = xs[i] - start + 1;
          d += 'M' + start + ' ' + y + 'h' + w + 'v' + h + 'h' + -w + 'z';
        }
      });
      return d;
    }
    // Sprites on half cells, in the world's cells (never following the body's offset): dot, cross, star; the Z.
    var SPARKLES = [['X'], ['.X.', 'XXX', '.X.'], ['..X..', '..X..', 'XX.XX', '..X..', '..X..']];
    var ZEE = ['XXXXX', '...X.', '..X..', '.X...', 'XXXXX'];
    function sparkle(life) { return SPARKLES[life < 0.16 ? 0 : life < 0.36 ? 1 : life < 0.64 ? 2 : life < 0.84 ? 1 : 0]; }
    function spritePath(pattern, cx, cy) {
      var d = '', h = pattern.length, w = pattern[0].length;
      pattern.forEach(function (row, j) {
        for (var i = 0; i < row.length; i++) {
          if (row[i] === 'X') d += 'M' + r3(cx + (i - w / 2) * 0.5) + ' ' + r3(cy + (j - h / 2) * 0.5) + 'h0.5v0.5h-0.5z';
        }
      });
      return d;
    }

    // ---------- The walk (Creature.walkFrame, CreatureWalk), stepped by the page moving under it ----------

    // The app's frame (0.12 s) is its pace on the Mac; here a step is tied to the scroll: one frame for every 9 cells the
    // page moves, never faster than one frame per 80 ms, and a still page holds the frame.
    var WALK = { frame: 0.12, cycle: 4, stride: 9, minFrame: 0.08, settle: 0.15 };
    // Frame `i` of one step: contact (the rest pose), first legs lifted, contact, the other legs lifted. On a passing
    // frame the body is up one row and the arm on the side of the lifted front leg swings up one row.
    function walkFrame(i) {
      var phase = ((i % WALK.cycle) + WALK.cycle) % WALK.cycle, pose = restPose();
      if (phase % 2 === 0) return pose;
      pose.raise = 1;
      pose.lifted = LEGS.map(function (_, k) { return (k % 2 === 0) === (phase === 1); });
      if (phase === 1) pose.armR = 'lift1'; else pose.armL = 'lift1';
      return pose;
    }
    // The shadow, one column narrower on each side while the body is up.
    function walkShadowInset(i) { return ((i % 2) + 2) % 2 === 1 ? 1 : 0; }
    // The walk after the page moved `dy` px at t, with cells of `unit` px. The first move shows a passing frame at once.
    // {frame, dist: px not yet walked, at: when the frame began, last: the last move}.
    function walkAdvance(w, dy, t, unit) {
      var stride = WALK.stride * unit;
      if (!w) return { frame: 1, dist: 0, at: t, last: t };
      var dist = w.dist + Math.abs(dy), next = { frame: w.frame, dist: Math.min(dist, 2 * stride), at: w.at, last: dy ? t : w.last };
      if (dist >= stride && t - w.at >= WALK.minFrame - 1e-9) { next.frame = w.frame + 1; next.dist = Math.min(dist - stride, stride); next.at = t; }
      return next;
    }
    // It never stops mid-step: 150 ms after the last move it takes its next contact frame (80 ms after the last frame at
    // the soonest), and stands.
    function walkEnd(w) { var e = w.last + WALK.settle; return w.frame % 2 ? Math.max(e, w.at + WALK.minFrame) : e; }
    function walkFrameAt(w, t) { return w.frame % 2 && t >= walkEnd(w) - 1e-9 ? w.frame + 1 : w.frame; }

    // ---------- The launch: AssembleScene (LaunchScene.swift, Theme.Launch) ----------

    var LAUNCH = {
      unit: 7, fadeIn: 0.12, settleIn: 0.12, gather: 0.04, staggerSpan: 0.14, staggerJitter: 0.04, spreadJitter: 0.25,
      gatherSpread: 2.4, pixelSpring: [0.30, 0.86], pixelSnap: 0.34, assembled: 0.58,
      clickAt: 0.44, clickVelocity: -1.1, clickSettled: 0.70, click: [0.30, 0.55], eyesOpen: [[0.54, 0.5], [0.60, 1]],
      shadowIn: 0.18, shadowOver: 0.30, wordmarkIn: 0.52, wordmarkDuration: 0.40, wordmarkRise: 8,
      hopCrouch: 0.74, hopTakeoff: 0.82, hopLand: 1.12, hopHeight: 2.4, landSpring: [0.34, 0.50], landSettled: 1.44,
      blinkAt: 1.30, heroTime: 1.46
    };
    var CENTER = { x: COLS / 2, y: ROWS / 2 };
    // Each pixel's ray, delay and spread, worked out once (the app's are functions of the pixel alone).
    var HOMES = PIXELS.map(function (p) {
      var hx = p.x + 0.5 - CENTER.x, hy = p.y + 0.5 - CENTER.y;
      return { x: p.x, y: p.y, hx: hx, hy: hy, jitter: hash01(p.x, p.y), spread: hash01(p.x, p.y, 7) };
    });
    var RIM = HOMES.reduce(function (m, p) { return Math.max(m, Math.hypot(p.hx, p.hy)); }, 0);
    // The grid, exploded: every pixel on its own ray about 2.4 times as far, springing home, inner ones first.
    // Offsets in cells from home; null once every pixel is home.
    function pixelStates(t) {
      var L = LAUNCH;
      if (t >= L.assembled) return null;
      var fade = Ease.out(progress(t, 0, L.fadeIn));
      return HOMES.map(function (p) {
        var local = t - (L.gather + L.staggerSpan * Math.hypot(p.hx, p.hy) / RIM + L.staggerJitter * p.jitter);
        if (local >= L.pixelSnap) return { dx: 0, dy: 0, o: 1 };
        var k = local <= 0 ? 0 : springValue(local, L.pixelSpring[0], L.pixelSpring[1]);
        var spread = L.gatherSpread + L.spreadJitter * p.spread;
        var m = (spread + (1 - spread) * k) * (1 + L.settleIn * (1 - fade));
        var dx = p.hx * (m - 1), dy = p.hy * (m - 1);
        if (Math.abs(dx) < 0.03 && Math.abs(dy) < 0.03 && local > 0.2) return { dx: 0, dy: 0, o: 1 };
        return { dx: dx, dy: dy, o: fade };
      });
    }
    // The blink after a landing: half, slit, half, open (Leap.blink).
    function blinkKeys(at) { return [[at, 0.5], [at + 0.04, 0.15], [at + 0.10, 0.5], [at + 0.14, 1]]; }
    // The splash at t (AssembleScene.beat and the wordmark of LaunchDirector.splash): the pose, its shadow (inset in
    // cells), and "Brainmerge" under it rising 8 px as it comes in. At 1.46 s (Theme.Launch.heroTime) it is the rest grid.
    function launchFrame(t) {
      var L = LAUNCH, pose = restPose();
      var shade = progress(t, L.shadowIn, L.shadowOver);
      var f = { pose: pose, shadow: { opacity: shade, inset: 6 * (1 - shade) }, word: { opacity: 0, rise: L.wordmarkRise } };
      var w = Ease.out(progress(t, L.wordmarkIn, L.wordmarkDuration));
      f.word = { opacity: w, rise: L.wordmarkRise * (1 - w) };
      if (t >= L.heroTime) return f;
      pose.pixels = pixelStates(t);
      // Eyes: none on a cloud of pixels, the asleep dash from the click, then half, then open.
      if (t < L.clickAt) pose.eyeH = 0;
      else if (t < L.eyesOpen[0][0]) { pose.eyeH = 0.35; pose.eyeBottom = 2.35; }
      else pose.eyeH = steps(t, L.eyesOpen, 1);
      // The click when the rim lands: a whole-body squash from the feet.
      if (t >= L.clickAt && t < L.clickSettled) {
        var d = springDisp(t - L.clickAt, L.click[0], L.click[1], 0, L.clickVelocity) * (1 - progress(t, L.clickSettled - 0.08, 0.08));
        pose.sy = 1 + d; pose.sx = 1 - 0.6 * d;
      }
      // The hop for joy: crouch, 2.4 cells up, land.
      if (t >= L.hopCrouch && t < L.hopTakeoff) {
        var k = Ease.out(progress(t, L.hopCrouch, L.hopTakeoff - L.hopCrouch));
        pose.sy = 1 - 0.12 * k; pose.sx = 1 + 0.07 * k; pose.eyeH = 0.5;
      } else if (t >= L.hopTakeoff && t < L.hopLand) {
        var u = (t - L.hopTakeoff) / (L.hopLand - L.hopTakeoff);
        var h = L.hopHeight * 4 * u * (1 - u);
        var stretch = 0.12 * Math.max(0, 1 - u / 0.45) + 0.04 * Math.max(0, (u - 0.7) / 0.3);
        pose.dy = -h; pose.sy = 1 + stretch; pose.sx = 1 - 0.6 * stretch;
        pose.tucked = u > 0.08 && u < 0.92;
        pose.armL = pose.armR = u > 0.05 && u < 0.9 ? 'lift1' : 'rest';
        f.shadow = { opacity: 1 - 0.35 * h / L.hopHeight, inset: h * 0.9 };
      } else if (t >= L.hopLand) {
        var dl = springDisp(t - L.hopLand, L.landSpring[0], L.landSpring[1], -0.14, 0) * (1 - progress(t, L.landSettled - 0.08, 0.08));
        pose.sy = 1 + dl; pose.sx = 1 - 0.7 * dl;
        pose.eyeH = steps(t, blinkKeys(L.blinkAt), 1);
      }
      return f;
    }

    // ---------- The leap (Leap in LaunchScene.swift) ----------

    var LEAP = {
      anticipation: 0.08, flight: 0.50, apex: 12, landing: [0.30, 0.50], squash: 0.20,
      lookBack: 0.18, blinkAt: 0.30, dozeAt: 0.62, dozeDash: 0.16, longWay: 250, longFlight: 0.6
    };
    // After touchdown the squash is exactly rest once its ringing stays under 0.004.
    LEAP.settled = settleTime(LEAP.landing[0], LEAP.landing[1], -LEAP.squash, 0, 0.004);
    // The long hand-off (GuideExit): its apex a fifth of the way across, less a quarter of the fall, 12 px at least;
    // the feet never rise above `ceiling` (40 px from the top by default, and never less than a 4 px hop). Past 250 px
    // across, the flight takes 0.6 s.
    function exitApex(dx, dy, higherFeetY, ceiling) {
      var cap = higherFeetY - (ceiling == null ? 40 : ceiling);
      return Math.max(4, Math.min(Math.max(0.2 * Math.abs(dx) - 0.25 * Math.abs(dy), LEAP.apex), cap));
    }
    function exitFlight(dx) { return Math.abs(dx) > LEAP.longWay ? LEAP.longFlight : LEAP.flight; }
    // A leap from `feet` (px, the middle of the feet's bottom edge) and cell `unit`, moving `vy` px/s (negative is up),
    // to `target` {x, y, unit}. Its target may move while it flies (a page that scrolls): every frame reads it. Taking
    // off with a speed (caught in the air, or carried by the page) it skips the crouch; `ceiling` is the highest its
    // feet may go.
    function makeLeap(o) {
      var L = {
        start: o.pose || restPose(), feet: { x: o.feet.x, y: o.feet.y }, unit: o.unit, vy: o.vy || 0,
        target: { x: o.target.x, y: o.target.y, unit: o.target.unit, asleep: !!o.target.asleep },
        crouch: Math.max(o.crouch || LEAP.anticipation, LEAP.anticipation), flight: o.flight || LEAP.flight,
        apex: o.apex == null ? LEAP.apex : o.apex, ceiling: o.ceiling == null ? -Infinity : o.ceiling
      };
      L.grounded = Math.abs(L.vy) < 1 && !L.start.tucked;
      L.takeoff = L.grounded ? L.crouch : 0;
      L.touchdown = L.takeoff + L.flight;
      L.end = L.touchdown + (L.target.asleep ? 0.86 : 0.50);
      return L;
    }
    function leapDirection(L) { var dx = L.target.x - L.feet.x; return Math.abs(dx) < 1 ? 0 : dx < 0 ? -1 : 1; }
    // From the ground: the arc with its apex `apex` above the higher end. From the air: the arc that keeps the speed it
    // has, while that needs at least half the ground arc's gravity.
    function ballistics(L) {
      var T = L.flight, D = L.target.y - L.feet.y;
      var H = L.apex + Math.max(0, -D);
      var s = (Math.sqrt(2 * H) + Math.sqrt(Math.max(0, 2 * H + 2 * D))) / T;
      var ground = { vy: -s * Math.sqrt(2 * H), g: s * s };
      if (L.grounded) return ground;
      var kept = { vy: L.vy, g: 2 * (D - L.vy * T) / (T * T) };
      // Kept only while it falls naturally and stays below the ceiling (a flick of the page must not throw it away).
      var top = L.vy < 0 && kept.g > 0 ? L.feet.y - L.vy * L.vy / (2 * kept.g) : L.feet.y;
      return kept.g >= ground.g / 2 && top >= L.ceiling ? kept : ground;
    }
    // The creature at `tau` seconds into the leap: its pose, its feet and its cell. The crouch, the arc (stretched at
    // takeoff, leaning 5 degrees toward home, shrinking to the target's cell), the landing squash, a look back, a blink.
    function leapFrame(L, tau) {
      var pose = copyPose(L.start), dir = leapDirection(L);
      pose.pixels = null; pose.sprites = [];
      if (tau < L.takeoff) {
        var k = Ease.out(progress(tau, 0, LEAP.anticipation));
        pose.sy = L.start.sy + (0.86 - L.start.sy) * k;
        pose.sx = L.start.sx + (1.08 - L.start.sx) * k;
        if (tau > 0.03) { pose.eyeH = 0.5; pose.eyeBottom = 2; }
        return { pose: pose, feet: { x: L.feet.x, y: L.feet.y }, unit: L.unit };
      }
      pose.raise = 0; pose.dx = 0; pose.dy = 0; pose.lifted = [false, false, false, false]; pose.eyeBottom = 2; pose.lookDown = 0;
      if (tau < L.touchdown) {
        var u = clamp01((tau - L.takeoff) / L.flight), tf = Math.max(0, tau - L.takeoff);
        var b = ballistics(L);
        var x = L.feet.x + (L.target.x - L.feet.x) * Ease.travel(u);
        var y = L.feet.y + b.vy * tf + b.g * tf * tf / 2;
        var cell = L.unit + (L.target.unit - L.unit) * Ease.shrink(u);
        var stretch = 0.14 * Math.max(0, 1 - u / 0.3) + 0.05 * Math.max(0, (u - 0.7) / 0.3);
        var sy = 1 + stretch, sx = 1 - 0.6 * stretch;
        if (!L.grounded) {
          var q = progress(tau, 0, 0.12), p = q * q * (3 - 2 * q);
          sy = L.start.sy + (sy - L.start.sy) * p; sx = L.start.sx + (sx - L.start.sx) * p;
        }
        pose.sy = sy; pose.sx = sx; pose.rot = 5 * Math.sin(Math.PI * u) * dir;
        var air = u > 0.03 || !L.grounded;
        pose.tucked = u < 0.94 && air;
        pose.armL = pose.armR = u < 0.86 && air ? 'lift1' : 'rest';
        pose.eyeH = 1;
        pose.look = u > 0.08 ? dir : 0;
        return { pose: pose, feet: { x: x, y: y }, unit: cell };
      }
      var tl = tau - L.touchdown;
      var d = springDisp(tl, LEAP.landing[0], LEAP.landing[1], -LEAP.squash, 0), settled = tl >= LEAP.settled;
      pose.sy = settled ? 1 : 1 + d; pose.sx = settled ? 1 : 1 - 0.7 * d;
      pose.rot = 0; pose.tucked = false; pose.armL = pose.armR = 'rest';
      pose.look = tl < LEAP.lookBack ? dir : 0;
      pose.eyeH = steps(tl, blinkKeys(LEAP.blinkAt), 1);
      return { pose: pose, feet: { x: L.target.x, y: L.target.y }, unit: L.target.unit };
    }

    // ---------- Reactions (CreatureLife.swift), each short and ending exactly on the rest pose ----------

    var REACT = { hop: 0.74, wave: 0.62, doze: 0.70, wake: 0.46, nod: 0.44 };
    // The companion's hop (LifeProfile.companion): 1.75 cells.
    var HOP_HEIGHT = 1.75;
    // Memory saved: crouch, hop with the arms up, four sparkles burst at the apex and stay in the air, a springy landing.
    function hop(tau, pose, H) {
      var sx = 1, sy = 1, y = 0;
      pose.look = 0; pose.eyeH = 1; pose.eyeBottom = 2;
      if (tau < 0.08) {
        var p0 = Ease.out(tau / 0.08); sy = 1 - 0.14 * p0; sx = 1 + 0.10 * p0; pose.eyeH = 0.5;
      } else if (tau < 0.30) {
        var p1 = (tau - 0.08) / 0.22;
        y = -H * (1 - (1 - p1) * (1 - p1));
        var snap = progress(tau, 0.08, 0.04), relax = Ease.out(progress(tau, 0.12, 0.16));
        sy = lerp(0.86, 1.12 - 0.12 * relax, snap); sx = lerp(1.10, 0.92 + 0.08 * relax, snap);
      } else if (tau < 0.44) {
        var p2 = (tau - 0.30) / 0.14; y = -H * (1 - p2 * p2);
      } else {
        var k = ringDown(tau - 0.44, 0.30, 0.5) * (1 - progress(tau, 0.64, 0.10));
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
        var p = Ease.out(life), pattern = sparkle(life);
        pose.sprites.push({ pattern: pattern, x: half(8 + tr[0] * p), y: half(-H - 0.6 + tr[1] * p),
          light: pattern !== SPARKLES[2] && i % 2 === 1, opacity: life < 0.8 ? 1 : (1 - life) / 0.2 });
      });
    }
    // Account opened: a happy little hop and a wave of the right arm, eyes smiling.
    function wave(tau, pose) {
      pose.look = 0;
      var swings = [[0.05, 'lift1'], [0.17, 'up'], [0.27, 'lift1'], [0.37, 'up'], [0.47, 'lift1'], [0.53, 'up'], [0.58, 'lift1']];
      pose.armR = 'rest';
      for (var i = 0; i < swings.length; i++) if (tau < swings[i][0]) { pose.armR = swings[i][1]; break; }
      if (tau < 0.10) pose.dy = -1.25 * Ease.out(tau / 0.10);
      else if (tau < 0.20) { var p = (tau - 0.10) / 0.10; pose.dy = -1.25 * (1 - p * p); }
      else if (tau < 0.26) { var k = Math.sin(Math.PI * (tau - 0.20) / 0.06); pose.sy = 1 - 0.08 * k; pose.sx = 1 + 0.05 * k; }
      pose.tucked = tau > 0.04 && tau < 0.18;
      pose.eyeH = tau >= 0.04 && tau < 0.50 ? 0.5 : 1;
      pose.eyeBottom = 2;
    }
    // Awake to asleep: heavy lids, then the asleep dash. No scale.
    function doze(tau, pose) {
      pose.look = 0; pose.lookDown = 0;
      if (tau < 0.18) { pose.eyeH = 1; pose.eyeBottom = 2; }
      else if (tau < 0.46) { pose.eyeH = 0.5; pose.eyeBottom = 2; }
      else { pose.eyeH = 0.35; pose.eyeBottom = 2.35; }
    }
    // Asleep to awake: the eyes open in two steps, a stretch with the arms up, a springy settle.
    function wake(tau, pose) {
      pose.look = 0; pose.lookDown = 0;
      if (tau < 0.06) { pose.eyeH = 0.35; pose.eyeBottom = 2.35; }
      else { pose.eyeH = tau < 0.14 ? 0.5 : 1; pose.eyeBottom = 2; }
      var k = tau < 0.14 ? Ease.out(tau / 0.14) : ringDown(tau - 0.14, 0.32, 0.6) * (1 - progress(tau, REACT.wake - 0.08, 0.08));
      pose.sy = 1 + 0.08 * k; pose.sx = 1 - 0.05 * k;
      pose.armL = pose.armR = tau < 0.06 ? 'rest' : tau < 0.10 ? 'lift1' : tau < 0.26 ? 'up' : tau < 0.30 ? 'lift1' : 'rest';
    }
    // A small nod, from the hop's own crouch: down with the eyes lowered and half closed, a springy settle.
    function nod(tau, pose) {
      pose.look = 0;
      var k = tau < 0.10 ? Ease.out(tau / 0.10) : ringDown(tau - 0.10, 0.30, 0.6) * (1 - progress(tau, REACT.nod - 0.08, 0.08));
      pose.sy = 1 - 0.1 * k; pose.sx = 1 + 0.06 * k;
      pose.lookDown = tau >= 0.02 && tau < 0.30 ? 1 : 0;
      pose.eyeH = tau >= 0.02 && tau < 0.30 ? 0.5 : 1;
      pose.eyeBottom = 2;
    }
    function react(kind, tau, pose) {
      if (kind === 'hop') hop(tau, pose, HOP_HEIGHT);
      else if (kind === 'wave') wave(tau, pose);
      else if (kind === 'doze') doze(tau, pose);
      else if (kind === 'wake') wake(tau, pose);
      else if (kind === 'nod') nod(tau, pose);
    }

    // A blink started d seconds ago (stepped), or null when not blinking (CreatureLife.blink).
    function blink(d) {
      d += 1e-9;
      return d >= 0 && d < 0.04 ? 0.5 : d >= 0.04 && d < 0.10 ? 0.2 : d >= 0.10 && d < 0.14 ? 0.5 : null;
    }
    // One Z, floating up 3.5 cells and to the right, swaying half a cell, fading over its last 0.9 s (CreatureLife.sleepZ).
    // Stepped like the app's pixel art: it moves in whole half cells and fades in four steps, so it wakes the page about
    // a dozen times, never every frame.
    var Z = { born: 0.2, life: 2.6 };
    function sleepZ(age) {
      if (!(age >= 0 && age < Z.life)) return null;
      var f = age / Z.life, p = Ease.travel(f);
      var fade = Math.min(age / 0.3, 1) * Math.min((Z.life - age) / 0.9, 1);
      return { pattern: ZEE, x: half(15.8 + 1.8 * p + 0.5 * Math.sin(2 * Math.PI * f)), y: half(-1.3 - 3.5 * p), light: false,
        opacity: Math.ceil(fade * 4 - 1e-9) / 4 * 0.72 };
    }
    // The ages at which the Z changes, worked out once.
    var Z_STEPS = (function () {
      var out = [], prev = '';
      for (var i = 0; i <= Z.life * 240; i++) {
        var age = i / 240, z = sleepZ(age), key = z ? z.x + ':' + z.y + ':' + z.opacity : '';
        if (key !== prev) { out.push(age); prev = key; }
      }
      return out;
    })();

    // ---------- The idle life: the app's phrase of blinks and glances (CreatureLife, LifeProfile.companion) ----------

    // SplitMix64 of a seed, an index and a stream, in 0..<1 (Dice.unit), in 64-bit integers.
    function diceUnit(seed, index, stream) {
      if (typeof BigInt !== 'function') return hash01(index, stream, seed);
      var B = BigInt, U = function (v) { return B.asUintN(64, v); };
      var z = U(B(seed) + U(B(index) * B('0x9E3779B97F4A7C15')) + U(B(stream) * B('0xD1B54A32D192ED03')));
      z = U((z ^ (z >> B(30))) * B('0xBF58476D1CE4E5B9'));
      z = U((z ^ (z >> B(27))) * B('0x94D049BB133111EB'));
      z = z ^ (z >> B(31));
      return Number(z >> B(11)) / 9007199254740992;
    }
    var LIFE = { seed: 7, blinkEvery: [3.4, 7.5], glanceEvery: [9, 16], blinkCount: 14, glanceCount: 9, firstBlink: 1.3,
      firstGlance: 3.1, doubleGap: 0.24, apart: 1.0, blinkLength: 0.14, window: 4 };
    // A fixed phrase of intervals (CreatureLife.Phrase): irregular to the eye, the same on every visit, then repeating.
    function phrase(stream, count, range, first) {
      var starts = [], t = first;
      for (var k = 0; k < count; k++) { starts.push(t); t += lerp(range[0], range[1], diceUnit(LIFE.seed, k, stream)); }
      return { starts: starts, loop: t - first };
    }
    function occurrences(ph, a, b) {
      var out = [], first = ph.starts[0];
      if (!(b >= a) || !(ph.loop > 0)) return out;
      for (var n = Math.max(0, Math.floor((a - first) / ph.loop) - 1); first + n * ph.loop <= b; n++) {
        for (var k = 0; k < ph.starts.length; k++) {
          var at = ph.starts[k] + n * ph.loop;
          if (at >= a && at <= b) out.push({ i: k, at: at });
        }
      }
      return out;
    }
    var BLINKS = phrase(1, LIFE.blinkCount, LIFE.blinkEvery, LIFE.firstBlink);
    var GLANCES = phrase(3, LIFE.glanceCount, LIFE.glanceEvery, LIFE.firstGlance);
    // The glances in [a, b]: a side, a hold of 0.7 to 1.4 s, and most end on a blink.
    function glances(a, b) {
      return occurrences(GLANCES, a, b).map(function (o) {
        return { at: o.at, side: diceUnit(LIFE.seed, o.i, 5) < 0.5 ? -1 : 1, hold: lerp(0.7, 1.4, diceUnit(LIFE.seed, o.i, 4)),
          back: diceUnit(LIFE.seed, o.i, 7) < 0.55 };
      });
    }
    // The blinks in [a, b] (CreatureLife.blinks): one in five doubled 0.24 s later, one as the eyes come back from most
    // glances, and never two within 1 s (a partner goes with its blink).
    function blinks(a, b) {
      var cand = [], kept = [], last = -Infinity, lead = 8;
      occurrences(BLINKS, a - lead, b).forEach(function (o) {
        cand.push({ at: o.at, of: null });
        if (diceUnit(LIFE.seed, o.i, 2) < 0.2) cand.push({ at: o.at + LIFE.doubleGap, of: o.at });
      });
      glances(a - lead - 2, b).forEach(function (g) { if (g.back) cand.push({ at: g.at + g.hold - 0.04, of: null }); });
      cand.sort(function (x, y) { return x.at - y.at; });
      cand.forEach(function (c) {
        if (c.at > b) return;
        if (c.of != null) {
          if (kept.some(function (k) { return Math.abs(k - c.of) < 1e-9; })) { kept.push(c.at); last = c.at; }
        } else if (c.at - last >= LIFE.apart) { kept.push(c.at); last = c.at; }
      });
      return kept.filter(function (k) { return k >= a - LIFE.blinkLength; });
    }
    // Once still, one beat of that phrase on the visit's clock, then it holds: the next blink (with its partner) or
    // glance (with its blink) within 4 s of the stop, or nothing. `side` {x, down} points a glance at the content.
    function idleBeat(stop, side) {
      var end = stop + LIFE.window;
      var bl = blinks(stop, end + 2).filter(function (x) { return x > stop; });
      var g = glances(stop, end).filter(function (x) { return x.at > stop; })[0];
      if (g && !(bl[0] < g.at)) {
        var back = g.at + g.hold - 0.04;
        return { at: g.at, look: { at: g.at, hold: g.hold, x: side ? side.x : g.side, down: side ? side.down || 0 : 0 },
          blinks: bl.filter(function (x) { return Math.abs(x - back) < 1e-9; }) };
      }
      if (bl[0] != null && bl[0] <= end) {
        var first = bl[0];
        return { at: first, look: null, blinks: bl.filter(function (x) { return x - first < LIFE.doubleGap + 0.01; }) };
      }
      return null;
    }
    function idleEyes(idle, t) {
      var out = { eyeH: 1, look: 0, down: 0 };
      if (!idle) return out;
      idle.blinks.forEach(function (b) { var h = blink(t - b); if (h) out.eyeH = h; });
      var l = idle.look;
      if (l && t >= l.at - 1e-9 && t < l.at + l.hold - 1e-9) { out.look = l.x; out.down = l.down; }
      return out;
    }
    function idleSteps(idle) {
      var c = [];
      if (!idle) return c;
      idle.blinks.forEach(function (b) { c.push(b, b + 0.04, b + 0.10, b + 0.14); });
      if (idle.look) c.push(idle.look.at, idle.look.at + idle.look.hold);
      return c;
    }
    // A look at a section (Graph, Usage): the eyes on it for 1.2 s, a blink 40 ms before they come back.
    var GLANCE = 1.2;

    // The companion's life at t, from its state:
    //   walk {frame, dist, at, last}  while the page moves under it (walkAdvance); face: the way it goes (1 down, -1 up)
    //   reaction {kind, at, look}, prev: the one it interrupted (the body blends from it over 120 ms)
    //   idle (idleBeat)     the one beat once still; glance {at, look, down}: a look at a section
    //   gaze {look, down}   a live look (the pointer, the travelling note, the button under the pointer)
    //   asleep {at}         asleep from `at`, one Z floating up from there
    function freshState() { return { walk: null, face: 0, reaction: null, prev: null, idle: null, glance: null, gaze: null, asleep: null }; }
    function reactionActive(r, t) { return !!r && t >= r.at && t < r.at + REACT[r.kind]; }
    function walkActive(w, t) { return !!w && t < walkEnd(w); }
    function reactPose(r, t) {
      var p = restPose();
      react(r.kind, t - r.at, p);
      if (r.look && r.kind === 'hop') p.look = r.look;
      return p;
    }
    function lifeFrame(s, t) {
      var pose = restPose(), shadow = { opacity: 1, inset: 0 };
      var walking = !!s.walk;
      if (s.asleep && t >= s.asleep.at) {
        pose.eyeH = 0.35; pose.eyeBottom = 2.35;
        var z = sleepZ(t - s.asleep.at - Z.born);
        if (z) pose.sprites.push(z);
      } else {
        // The eyes: a look at a section first, then a live look, then the way it walks, then the idle.
        if (s.idle) { var e = idleEyes(s.idle, t); pose.eyeH = e.eyeH; pose.look = e.look; pose.lookDown = e.down; }
        if (walking && s.face) { pose.look = s.face > 0 ? 1 : -1; pose.lookDown = 0; }
        if (s.gaze) { pose.look = s.gaze.look; pose.lookDown = s.gaze.down || 0; }
        if (s.glance) {
          var dg = t - s.glance.at;
          if (dg >= 0 && dg < GLANCE) { pose.look = s.glance.look; pose.lookDown = s.glance.down || 0; }
          var bh = blink(dg - (GLANCE - 0.04));
          if (bh) pose.eyeH = bh;
        }
      }
      if (reactionActive(s.reaction, t)) {
        var r = reactPose(s.reaction, t), keep = pose.sprites;
        // Interrupted: the body blends from where the previous reaction left it, over 120 ms (smoothstep).
        if (s.prev && reactionActive(s.prev, s.reaction.at)) {
          var from = reactPose(s.prev, s.reaction.at);
          var q = progress(t - s.reaction.at, 0, 0.12), m = q * q * (3 - 2 * q);
          r.dx = lerp(from.dx, r.dx, m); r.dy = lerp(from.dy, r.dy, m);
          r.sx = lerp(from.sx, r.sx, m); r.sy = lerp(from.sy, r.sy, m);
        }
        if (s.reaction.kind === 'doze' || s.reaction.kind === 'wake') r.sprites = r.sprites.concat(keep);
        pose = r;
        var air = Math.max(0, -pose.dy) / HOP_HEIGHT;
        shadow = { opacity: 1 - 0.35 * Math.min(1, air), inset: Math.min(1, air) * 2 };
      } else if (walking) {
        var i = walkFrameAt(s.walk, t), wf = walkFrame(i);
        pose.raise = wf.raise; pose.lifted = wf.lifted; pose.armL = wf.armL; pose.armR = wf.armR;
        shadow.inset = walkShadowInset(i);
      }
      return { pose: pose, shadow: shadow };
    }
    // True while something moves smoothly: a reaction. The walk steps with the page, and blinks, looks and the Z are
    // stepped: they wait for `nextChange`, never for frames.
    function needsFrames(s, t) { return reactionActive(s.reaction, t); }
    // The next time after t the frame changes on its own, or Infinity: the companion then holds still.
    function nextChange(s, t) {
      var c = idleSteps(s.idle);
      if (s.glance) [0, GLANCE - 0.04, GLANCE, GLANCE + 0.06, GLANCE + 0.10].forEach(function (d) { c.push(s.glance.at + d); });
      if (s.reaction) c.push(s.reaction.at);
      if (s.walk) c.push(walkEnd(s.walk));
      if (s.asleep) { c.push(s.asleep.at); Z_STEPS.forEach(function (d) { c.push(s.asleep.at + Z.born + d); }); c.push(s.asleep.at + Z.born + Z.life); }
      var next = Infinity;
      c.forEach(function (x) { if (x > t + 1e-6 && x < next) next = x; });
      return next;
    }

    // ---------- Where it looks, where it sits, when it moves ----------

    // Toward a point dx, dy px away: one whole cell sideways once past the body, one row down once well below. Never up.
    function gaze(dx, dy, cell) { return { x: dx < -8 * cell ? -1 : dx > 8 * cell ? 1 : 0, y: dy > 7 * cell ? 1 : 0 }; }
    // The travelling note of How it works, followed from where the creature stands (the same rule as any look).
    function followLook(x, feetX, unit) { return gaze(x - feetX, 0, unit).x; }
    // The feet in a box drawn with viewBox `vb` [x, y, width, height] in cells: the middle of the feet's bottom edge.
    function slotFeet(rect, vb) { var u = rect.width / vb[2]; return { x: rect.left + (8 - vb[0]) * u, y: rect.top + (11 - vb[1]) * u, unit: u }; }
    var HERO_VB = [0, -3, 16, 15], FINALE_VB = [-2, -6, 20, 18], PERCH_VB = [0, 0, 16, 12];
    // The perch's feet in an anchor box (16 by 12 cells: the grid and its shadow row).
    function perchFeet(rect) { return slotFeet(rect, PERCH_VB); }
    // The hero creature's feet in its box: its viewBox starts 3 cells above the head.
    function heroFeet(rect) { return slotFeet(rect, HERO_VB); }
    // Whether two rectangles overlap, and whether any of `rects` overlaps `box` (lines of text, buttons, pictures).
    function overlaps(a, b) { return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom; }
    function coverage(box, rects) {
      for (var i = 0; i < rects.length; i++) if (rects[i].right > rects[i].left && overlaps(box, rects[i])) return true;
      return false;
    }
    // Where it perches: beside the column when the gutter holds it with 22 px on each side, else in the nav bar.
    var COLUMN = 1080, GUTTER = 40;
    function perchMode(width, unit) {
      var column = Math.min(COLUMN, width - 2 * GUTTER), side = (width - column) / 2;
      return side >= 16 * unit + 44 ? 'corner' : 'nav';
    }
    // In the nav bar, in the free space between the brand and what follows it: 3 px cells, 2 px when that is tight,
    // standing 3 px above the bar's bottom edge. Null when there is no room.
    function navPerch(left, right, barHeight) {
      var gap = right - left, u = gap >= 16 * 3 + 16 ? 3 : gap >= 16 * 2 + 12 ? 2 : 0;
      if (!u) return null;
      return { x: Math.round((left + right) / 2), y: barHeight - 3 - u, unit: u };
    }

    // When it moves between the page and its perch. It leaves its place in the page (the hero, the finale) once that
    // scrolls away, and comes home to the hero only when the reader is back at the top and has stopped: at the very
    // top, 250 ms after the last scroll. Whatever it does, it stays 1.2 s where it landed first: a nudge of the page
    // can never set it flying back and forth.
    var DWELL = { landing: 1.2, still: 0.25, top: 4 };
    function shouldLeave(o) { return !!o.gone && o.sinceLanding >= DWELL.landing; }
    function shouldGoHome(o) { return o.scrollY <= DWELL.top && o.sinceScroll >= DWELL.still && o.sinceLanding >= DWELL.landing; }
    // What to do now: {act: 'perch' | 'hero' | 'finale' | null, wait: seconds until it is worth asking again}.
    //   where: 'home' (in the hero or the finale: `slot`), 'perched', or 'flying' (to `dest`, from `from`, `landed`
    //   once it touched down); heroGone, finaleIn (the finale well in view), finaleGone; scrollY, sinceScroll,
    //   sinceLanding; mode: 'corner', 'nav' or 'none' (no room for a perch: it stays in the hero).
    function plan(s) {
      var none = { act: null, wait: Infinity }, dwell = DWELL.landing - s.sinceLanding;
      var atTop = s.scrollY <= DWELL.top, calm = s.sinceScroll >= DWELL.still;
      if (s.where === 'flying') {
        // Caught on its way out by a reader back at the top, and still: it turns in the air.
        if (s.dest === 'perch' && s.from === 'hero' && !s.landed && !s.heroGone && atTop) return calm ? { act: 'hero', wait: Infinity } : { act: null, wait: DWELL.still - s.sinceScroll };
        // Its finale gone before it got there: on to the perch.
        if (s.dest === 'finale' && s.finaleGone && !s.landed) return { act: 'perch', wait: Infinity };
        return none;
      }
      if (s.mode === 'none') {
        // No room for a perch: it only goes between the hero and the finale.
        if (s.where === 'perched') return { act: 'hero', wait: Infinity };
        var there = s.slot === 'finale' ? s.finaleGone && !s.heroGone && atTop : s.heroGone && s.finaleIn;
        if (!there) return none;
        return dwell <= 0 ? { act: s.slot === 'finale' ? 'hero' : 'finale', wait: Infinity } : { act: null, wait: dwell };
      }
      if (s.where === 'home') {
        var gone = s.slot === 'finale' ? s.finaleGone : s.heroGone;
        if (!gone) return none;
        var to = s.slot !== 'finale' && s.finaleIn ? 'finale' : 'perch';
        return shouldLeave({ gone: gone, sinceLanding: s.sinceLanding }) ? { act: to, wait: Infinity } : { act: null, wait: dwell };
      }
      if (s.finaleIn) return dwell <= 0 ? { act: 'finale', wait: Infinity } : { act: null, wait: dwell };
      if (!atTop || s.heroGone) return none;
      if (shouldGoHome(s)) return { act: 'hero', wait: Infinity };
      return { act: null, wait: Math.max(dwell, DWELL.still - s.sinceScroll) };
    }

    // How it works, on the diagram's own clock (script.js, Motion.STORY): three beats of 2.4 s, each note landing 1 s in.
    // The diagram's own creature catches every note; the companion only watches, and hops once, when the story is over.
    var FLOW = { beat: 2.4, land: 1.0, beats: 3, end: 7.4 };
    function flowLandings() {
      var out = [];
      for (var b = 0; b < FLOW.beats; b++) out.push(b * FLOW.beat + FLOW.land);
      return out;
    }
    function storyHops(t0) { return [t0 + FLOW.end]; }

    // What each part of the page brings out of it. The finale is not here: it leaps into it.
    var REACTIONS = { accounts: 'wave', flow: 'hop', graph: 'look', usage: 'look', ram: 'look', safety: 'nod', footer: 'doze', click: 'wave' };

    return {
      clamp01: clamp01, progress: progress, steps: steps, bezier: bezier, Ease: Ease, springDisp: springDisp,
      springValue: springValue, settleTime: settleTime, hash01: hash01, sign: sign,
      GRID: GRID, PIXELS: PIXELS, LEGS: LEGS, ARMS: ARMS, restPose: restPose, copyPose: copyPose, poseCells: poseCells,
      eyeRects: eyeRects, cellsPath: cellsPath, spritePath: spritePath, SPARKLES: SPARKLES, ZEE: ZEE, sparkle: sparkle,
      WALK: WALK, walkFrame: walkFrame, walkShadowInset: walkShadowInset, walkAdvance: walkAdvance, walkEnd: walkEnd,
      walkFrameAt: walkFrameAt,
      LAUNCH: LAUNCH, pixelStates: pixelStates, launchFrame: launchFrame, blinkKeys: blinkKeys,
      LEAP: LEAP, exitApex: exitApex, exitFlight: exitFlight, makeLeap: makeLeap, leapFrame: leapFrame, ballistics: ballistics,
      REACT: REACT, HOP_HEIGHT: HOP_HEIGHT, react: react, blink: blink, Z: Z, sleepZ: sleepZ, Z_STEPS: Z_STEPS, half: half,
      diceUnit: diceUnit, LIFE: LIFE, phrase: phrase, glances: glances, blinks: blinks, idleBeat: idleBeat,
      idleEyes: idleEyes, idleSteps: idleSteps, GLANCE: GLANCE,
      freshState: freshState, lifeFrame: lifeFrame, needsFrames: needsFrames, nextChange: nextChange,
      reactionActive: reactionActive, walkActive: walkActive,
      gaze: gaze, followLook: followLook, slotFeet: slotFeet, HERO_VB: HERO_VB, FINALE_VB: FINALE_VB, perchFeet: perchFeet,
      heroFeet: heroFeet, overlaps: overlaps, coverage: coverage, perchMode: perchMode, navPerch: navPerch,
      DWELL: DWELL, shouldLeave: shouldLeave, shouldGoHome: shouldGoHome, plan: plan,
      FLOW: FLOW, flowLandings: flowLandings, storyHops: storyHops, REACTIONS: REACTIONS
    };
  })();

  if (typeof window === 'undefined' || typeof document === 'undefined') {
    if (typeof module !== 'undefined') module.exports = C;
    return;
  }

  // ---------- The page ----------

  var hero = document.querySelector('.hero-creature');
  if (!hero) return;
  var root = document.documentElement;
  var SVGNS = 'http://www.w3.org/2000/svg';
  var CREAM = '#F4EFE6', LIGHT = '#B487EA';
  var motionQuery = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: no-preference)') : null;
  var fine = !!(window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches);
  var motion = !!(motionQuery && motionQuery.matches) && 'IntersectionObserver' in window && !!window.requestAnimationFrame;
  // A script that came late (a slow network): the failsafe has already shown the creature and its name. No intro then:
  // it would take the creature apart again.
  var late = motion && window.getComputedStyle(hero).opacity !== '0';

  root.classList.add('cm-ready');
  hero.classList.add('is-live');
  // Reduce Motion (or no observer): the hero creature is the still grid of the markup. No intro, no leap, no companion.
  if (!motion) return;

  var clock = function () { return performance.now() / 1000; };
  function set(el, name, value) { if (el.getAttribute(name) !== value) el.setAttribute(name, value); }
  function unset(el, name) { if (el.hasAttribute(name)) el.removeAttribute(name); }
  var r3 = function (x) { return Math.round(x * 1000) / 1000; };

  // Draws a pose into an SVG built like the hero creature (.cm-shadow, .cm-body, .cm-cells, .cm-eyes).
  function view(svg) {
    var body = svg.querySelector('.cm-body'), cells = svg.querySelector('.cm-cells');
    var eyes = svg.querySelectorAll('.cm-eyes rect'), shadow = svg.querySelector('.cm-shadow');
    var sprites = document.createElementNS(SVGNS, 'g'), pixels = null, lastD = cells.getAttribute('d');
    sprites.setAttribute('class', 'cm-sprites');
    svg.appendChild(sprites);
    return function draw(pose, shade) {
      var tr = '';
      if (pose.dx || pose.dy) tr += 'translate(' + r3(pose.dx) + ' ' + r3(pose.dy) + ')';
      if (pose.rot || pose.sx !== 1 || pose.sy !== 1) {
        tr += ' translate(8 11)' + (pose.rot ? ' rotate(' + r3(pose.rot) + ')' : '') + ' scale(' + r3(pose.sx) + ' ' + r3(pose.sy) + ') translate(-8 -11)';
      }
      if (tr) set(body, 'transform', tr.trim()); else unset(body, 'transform');
      if (pose.opacity < 1) set(body, 'opacity', String(r3(pose.opacity))); else unset(body, 'opacity');
      if (pose.pixels) {
        if (!pixels) {
          pixels = document.createElementNS(SVGNS, 'g');
          pixels.setAttribute('fill', cells.getAttribute('fill'));
          C.PIXELS.forEach(function (p) {
            var rect = document.createElementNS(SVGNS, 'rect');
            rect.setAttribute('x', p.x); rect.setAttribute('y', p.y); rect.setAttribute('width', 1); rect.setAttribute('height', 1);
            pixels.appendChild(rect);
          });
          body.insertBefore(pixels, cells);
        }
        set(cells, 'opacity', '0');
        pose.pixels.forEach(function (p, i) {
          var rect = pixels.childNodes[i];
          if (p.dx || p.dy) set(rect, 'transform', 'translate(' + r3(p.dx) + ' ' + r3(p.dy) + ')'); else unset(rect, 'transform');
          set(rect, 'opacity', String(r3(p.o)));
        });
      } else {
        if (pixels) { pixels.parentNode.removeChild(pixels); pixels = null; }
        unset(cells, 'opacity');
        var d = C.cellsPath(C.poseCells(pose));
        if (d !== lastD) { cells.setAttribute('d', d); lastD = d; }
      }
      var rects = C.eyeRects(pose);
      Array.prototype.forEach.call(eyes, function (eye, i) {
        var r = rects[i];
        if (!r) { set(eye, 'opacity', '0'); return; }
        unset(eye, 'opacity');
        set(eye, 'x', String(r3(r[0]))); set(eye, 'y', String(r3(r[1]))); set(eye, 'height', String(r3(r[3])));
      });
      if (shadow && shade) {
        var inset = Math.min(5.5, Math.max(0, shade.inset));
        set(shadow, 'x', String(r3(2 + inset))); set(shadow, 'width', String(r3(12 - 2 * inset)));
        if (shade.opacity < 1) set(shadow, 'opacity', String(r3(Math.max(0, shade.opacity)))); else unset(shadow, 'opacity');
      }
      while (sprites.childNodes.length > pose.sprites.length) sprites.removeChild(sprites.lastChild);
      pose.sprites.forEach(function (s, i) {
        var path = sprites.childNodes[i];
        if (!path) { path = document.createElementNS(SVGNS, 'path'); sprites.appendChild(path); }
        set(path, 'd', C.spritePath(s.pattern, s.x, s.y));
        set(path, 'fill', s.light ? LIGHT : CREAM);
        set(path, 'opacity', String(r3(s.opacity * pose.opacity)));
      });
    };
  }

  // The companion: a copy of the hero creature in a fixed layer above the nav, a perch beside the column for wide
  // screens (companion.css), and the finale, where it stands above Download. Pointer events on its drawn cells only.
  var layer = document.createElement('div');
  layer.className = 'companion';
  layer.setAttribute('aria-hidden', 'true');
  var twin = hero.cloneNode(true);
  twin.removeAttribute('role'); twin.removeAttribute('aria-label');
  twin.setAttribute('class', 'cm-svg');
  twin.setAttribute('viewBox', '0 0 16 12');
  twin.setAttribute('focusable', 'false');
  layer.appendChild(twin);
  var corner = document.createElement('i');
  corner.className = 'cm-perch';
  corner.setAttribute('aria-hidden', 'true');
  document.body.appendChild(corner);
  document.body.appendChild(layer);
  var drawHero = view(hero), drawTwin = view(twin);
  var navEl = document.querySelector('.nav'), brand = document.querySelector('.nav-brand');
  var finale = document.querySelector('#download'), finaleSvg = finale && finale.querySelector('.cv-finale');
  if (!finaleSvg) finale = null;
  // The finale is the companion's to land in: script.js waits for it (cm-arrive, cm-depart, cm-assemble).
  if (finale) finale.setAttribute('data-cm', '');
  function tell(name, detail) { if (finale) finale.dispatchEvent(new CustomEvent(name, { detail: detail || {} })); }

  // Where the creature is: 'home' in a place of the page (`slot`: the hero or the finale), 'flying' (a leap), or
  // 'perched'. It is only ever in one of them.
  var where = 'home', slot = 'hero';
  var life = C.freshState();
  var intro = null, leap = null, shown = false, landedAt = -Infinity;
  var lastScroll = -Infinity, lastY = window.scrollY, scrollVel = 0;
  var lastFeet = null, lastFeetAt = 0, prevFeet = null, prevFeetAt = 0;
  var raf = 0, timer = 0, settleTimer = 0, decideTimer = 0, showTimer = 0, storyTimer = 0, resizeTimer = 0;
  var story = null, off = false, heroGone = false, finaleIn = false, finaleGone = true, observers = [];
  var bootAt = clock();
  var NAV = navEl ? navEl.getBoundingClientRect().height : 52, LEAVE_Y = NAV + 16;

  // ---------- The perch: in the nav bar, or beside the column ----------

  var mode = 'corner', unit = 4, navSpot = null;
  function measureMode() {
    var m = C.perchMode(window.innerWidth, 4);
    if (m === 'nav') {
      navSpot = null;
      var next = brand && brand.nextElementSibling;
      while (next && !next.getClientRects().length) next = next.nextElementSibling;
      if (next) navSpot = C.navPerch(brand.getBoundingClientRect().right, next.getBoundingClientRect().left, NAV);
      if (!navSpot) m = 'none';
    }
    mode = m;
    unit = m === 'nav' ? navSpot.unit : 4;
    layer.style.setProperty('--cm-u', unit + 'px');
    root.classList.toggle('cm-nav', m === 'nav');
  }
  measureMode();
  function spotFeet() {
    if (mode === 'nav') return { x: navSpot.x, y: navSpot.y, unit: unit };
    return C.perchFeet(corner.getBoundingClientRect());
  }
  function slotFeet(name) {
    return name === 'finale' ? C.slotFeet(finaleSvg.getBoundingClientRect(), C.FINALE_VB) : C.heroFeet(hero.getBoundingClientRect());
  }

  // One loop, running only while something moves; stepped changes (a blink, a look, a step) wake it with a timer.
  function kick() {
    if (off) return;
    if (timer) { clearTimeout(timer); timer = 0; }
    if (!raf) raf = requestAnimationFrame(frame);
  }
  function frame() {
    raf = 0;
    var t = clock(), moving = render(t);
    if (moving) { if (!raf) raf = requestAnimationFrame(frame); return; }
    if (raf || off) return;
    var next = C.nextChange(life, t);
    if (next < Infinity) timer = setTimeout(kick, Math.max(1, (next - t) * 1000 + 2));
  }

  function place(feet, u) {
    var s = u / unit, x = feet.x - 8 * unit, y = feet.y - 11 * unit;
    var scaled = Math.abs(s - 1) > 1e-3;
    // On whole pixels when it stands at its own size: crisp cells.
    if (!scaled) { x = Math.round(x); y = Math.round(y); }
    layer.style.transform = 'translate(' + r3(x) + 'px, ' + r3(y) + 'px)' + (scaled ? ' scale(' + r3(s) + ')' : '');
    prevFeet = lastFeet; prevFeetAt = lastFeetAt;
    lastFeet = { x: feet.x, y: feet.y, unit: u }; lastFeetAt = clock();
  }
  function placeAtSpot() { var f = spotFeet(); place(f, f.unit); }
  var hiddenAt = -Infinity;
  // Beside the column it steps out of the way at once when something to read comes under it, and comes back once the
  // page is still and the spot has been clear, never sooner than 1.5 s after it went: it cannot flicker.
  function show(on, instant) {
    clearTimeout(showTimer); showTimer = 0;
    if (on && !instant && !shown) {
      var wait = 1.5 - (clock() - hiddenAt);
      if (wait > 0) { showTimer = setTimeout(function () { showTimer = 0; checkPerch(true); }, wait * 1000 + 10); return; }
    }
    if (shown === on && !instant) return;
    if (shown && !on && !instant) hiddenAt = clock();
    shown = on;
    layer.classList.toggle('is-instant', !!instant);
    layer.classList.toggle('is-on', on);
  }

  // What must never be covered: words, links and buttons, pictures, the Dock, the cards of the illustrations. Their
  // boxes are read once the page is still and kept in page coordinates, so a scroll only compares numbers.
  var SOLID = 'a, button, input, select, textarea, img, picture, video, canvas, svg, code, pre, table, .btn, .mac, .dock-stage, .card, .window, [role="img"]';
  var TEXT = 'p, h1, h2, h3, h4, h5, li, dt, dd, figcaption, blockquote, label';
  var obstacles = null;
  function collect() {
    var sy = window.scrollY, list = [];
    Array.prototype.forEach.call(document.querySelectorAll(SOLID + ', ' + TEXT), function (el) {
      if (el.closest('.nav, .companion')) return;
      var r = el.getBoundingClientRect();
      if (!(r.width > 0 && r.height > 0)) return;
      list.push({ el: el, text: !el.matches(SOLID), left: r.left, right: r.right, top: r.top + sy, bottom: r.bottom + sy });
    });
    obstacles = list;
  }
  function perchBox() {
    var f = spotFeet(), u = f.unit, pad = 6;
    return { left: f.x - 8 * u - pad, right: f.x + 8 * u + pad, top: f.y - 11 * u - pad, bottom: f.y + u + pad };
  }
  function shifted(o, sy) { return { left: o.left, right: o.right, top: o.top - sy, bottom: o.bottom - sy }; }
  // While the page scrolls: the boxes only.
  function blockedQuick() {
    if (!obstacles) return false;
    var box = perchBox(), sy = window.scrollY;
    for (var i = 0; i < obstacles.length; i++) if (C.overlaps(box, shifted(obstacles[i], sy))) return true;
    return false;
  }
  // Once still: the boxes again, then each line of a text that comes near (a paragraph's box is wider than its words).
  function blockedNow() {
    collect();
    var box = perchBox(), sy = window.scrollY;
    for (var i = 0; i < obstacles.length; i++) {
      var o = obstacles[i];
      if (!C.overlaps(box, shifted(o, sy))) continue;
      if (!o.text) {
        var cs = window.getComputedStyle(o.el);
        if (cs.visibility !== 'hidden' && parseFloat(cs.opacity) > 0.05) return true;
        continue;
      }
      var range = document.createRange();
      range.selectNodeContents(o.el);
      if (C.coverage(box, range.getClientRects())) return true;
    }
    return false;
  }
  // In the nav bar it is always there. Beside the column it is there when nothing is under it.
  function checkPerch(settled) {
    if (where !== 'perched' || off) return;
    if (mode !== 'corner') { if (!shown) { placeAtSpot(); show(true); replay(); } return; }
    if (!settled) { if (shown && blockedQuick()) show(false); return; }
    if (blockedNow()) { show(false); return; }
    if (!shown) { placeAtSpot(); show(true); if (shown) replay(); }
  }
  // The content beside it: below it in the nav bar, toward the middle of the screen beside the column.
  function contentSide() {
    if (mode === 'nav') return { x: 0, down: 1 };
    return { x: lastFeet && lastFeet.x > window.innerWidth / 2 ? -1 : 1, down: 0 };
  }
  function lookAtEl(el) {
    if (!lastFeet) return { x: 0, y: 0 };
    var r = el.getBoundingClientRect(), u = lastFeet.unit;
    return C.gaze(r.left + r.width / 2 - lastFeet.x, r.top + r.height / 2 - (lastFeet.y - 5.5 * u), u);
  }

  function render(t) {
    if (intro) {
      var f = C.launchFrame(t - intro);
      drawHero(f.pose, f.shadow);
      if (t - intro < C.LAUNCH.heroTime) return true;
      intro = null;
      life.idle = C.idleBeat(t, null);
      decide();
      if (leap) return true;
    }
    if (leap) {
      var tau = t - leap.t0, L = leap.L;
      // Until it takes off it stands in its place in the page, which may be moving.
      if (leap.src && tau < L.takeoff) { var f0 = takeoffFeet(leap.src); L.feet.x = f0.x; L.feet.y = f0.y; }
      if (leap.dest !== 'perch') { var h = slotFeet(leap.dest); L.target.x = h.x; L.target.y = h.y; L.target.unit = h.unit; }
      var lf = C.leapFrame(L, tau);
      if (tau >= L.touchdown && !leap.down) {
        leap.down = true;
        landedAt = leap.t0 + L.touchdown;
        if (leap.dest === 'finale') {
          // The finale draws its own landing, in the page, and rings its button: the companion is the finale's creature.
          show(false, true);
          tell('cm-arrive', { end: L.end - L.touchdown, frame: function (s) { return C.leapFrame(L, L.touchdown + s).pose; } });
          finishLeap(t);
          return false;
        }
        if (leap.dest === 'hero') { hero.classList.remove('is-away'); show(false, true); }
      }
      // The shadow thins out and goes as it lifts off, and comes back under it as it lands.
      var away = C.Ease.out(C.progress(tau, L.takeoff / 2, 0.16)), back = C.Ease.out(C.progress(tau, L.touchdown, 0.16));
      var shade = tau < L.touchdown ? { opacity: 1 - away, inset: 3 * away } : { opacity: back, inset: 3 * (1 - back) };
      if (leap.dest === 'hero' && leap.down) drawHero(lf.pose, { opacity: 1, inset: 0 });
      else { drawTwin(lf.pose, shade); place(lf.feet, lf.unit); }
      if (tau < L.end) return true;
      finishLeap(t);
      if (leap) return true;
    }
    if (where !== 'home' && where !== 'perched') return false;
    if (where === 'home' && slot === 'finale') return false;
    // The walk ends on a contact frame, 150 ms after the page stopped; then one beat of idle life.
    if (life.walk && t >= C.walkEnd(life.walk) - 1e-6) {
      life.walk = null; life.face = 0;
      if (!life.asleep) life.idle = C.idleBeat(t, contentSide());
      if (dozeLater && footerIn && shown) { dozeLater = false; startReaction('doze'); }
    }
    var following = false;
    if (story && where === 'perched' && shown) following = follow(t);
    var lf2 = C.lifeFrame(life, t);
    if (where === 'home') drawHero(lf2.pose, lf2.shadow); else drawTwin(lf2.pose, lf2.shadow);
    return C.needsFrames(life, t) || following;
  }
  function finishLeap(t) {
    var dest = leap.dest;
    leap = null;
    life = C.freshState();
    if (dest === 'perch') {
      where = 'perched';
      life.idle = C.idleBeat(t, contentSide());
      checkPerch(true);
      replay();
    } else {
      where = 'home'; slot = dest;
      if (dest === 'hero') { life.idle = C.idleBeat(t, null); attachGaze(); }
    }
    decide();
  }

  // ---------- Leaping between the page and the perch ----------

  function currentPose() {
    if (intro) { var f = C.launchFrame(C.LAUNCH.heroTime); intro = null; return f.pose; }
    return C.lifeFrame(life, clock()).pose;
  }
  // Where it takes off from its place in the page: whole, below the nav, on screen.
  function takeoffFeet(name) {
    var f = slotFeet(name);
    f.y = Math.min(Math.max(f.y, NAV + 11 * f.unit + 4), window.innerHeight - 4);
    return f;
  }
  // The page's own speed on screen while it scrolls (px/s, negative going up), which a creature standing in it has.
  function pageVelocity() { return clock() - lastScroll < 0.1 ? Math.max(-1500, Math.min(1500, -scrollVel)) : 0; }
  function leaveSlot(name) {
    if (name === 'hero') hero.classList.add('is-away');
    else tell('cm-depart');
  }
  // Straight there, no leap: the first moments of a visit that opens further down the page.
  function placeInstant(dest) {
    if (where === 'home' && dest !== slot) leaveSlot(slot);
    intro = null; leap = null; life = C.freshState();
    landedAt = -Infinity;
    if (dest === 'perch') {
      where = 'perched';
      placeAtSpot(); drawTwin(C.restPose(), { opacity: 1, inset: 0 });
      checkPerch(true);
    } else {
      where = 'home'; slot = dest;
      show(false, true);
      if (dest === 'hero') { hero.classList.remove('is-away'); drawHero(C.restPose(), { opacity: 1, inset: 0 }); attachGaze(); }
      else { landedAt = clock() + C.LAUNCH.heroTime; tell('cm-assemble'); }
    }
    kick();
  }
  function leapTo(dest) {
    if (off) return;
    if (clock() - bootAt < 0.6) { placeInstant(dest); return; }
    var t = clock(), from, pose, vy = 0, src = null;
    if (leap) {
      // Caught in the air: it turns, keeping the speed it has, no crouch.
      pose = C.leapFrame(leap.L, t - leap.t0).pose;
      from = lastFeet;
      if (prevFeet && lastFeetAt > prevFeetAt) vy = (lastFeet.y - prevFeet.y) / (lastFeetAt - prevFeetAt);
    } else if (where === 'home') {
      src = slot;
      pose = currentPose();
      from = takeoffFeet(slot);
      // Carried by a scrolling page, it leaves at once with the page's speed; on a still page it crouches first.
      vy = pageVelocity();
      leaveSlot(slot);
    } else {
      pose = C.lifeFrame(life, t).pose;
      from = lastFeet || spotFeet();
    }
    detachGaze();
    var to = dest === 'perch' ? spotFeet() : slotFeet(dest);
    // Its head stays below the nav, unless the nav is where it is going; then on the screen.
    var head = 11 * Math.max(from.unit, to.unit), ceiling = dest === 'perch' && mode === 'nav' ? head + 2 : NAV + head + 4;
    var L = C.makeLeap({
      pose: pose, feet: from, unit: from.unit, vy: vy, target: to, flight: C.exitFlight(to.x - from.x),
      apex: C.exitApex(to.x - from.x, to.y - from.y, Math.min(from.y, to.y), ceiling), ceiling: ceiling
    });
    life = C.freshState();
    leap = { L: L, t0: t, dest: dest, src: src, down: false };
    where = 'flying';
    show(true, true);
    place(from, from.unit);
    kick();
  }

  // One place decides when it moves (C.plan), asked whenever something it depends on changes.
  function decide() {
    clearTimeout(decideTimer); decideTimer = 0;
    if (off || intro) return;
    var t = clock();
    var p = C.plan({
      where: where, slot: slot, dest: leap && leap.dest, from: leap && leap.src, landed: !!(leap && leap.down),
      heroGone: heroGone, finaleIn: finaleIn, finaleGone: finaleGone, scrollY: window.scrollY,
      sinceScroll: t - lastScroll, sinceLanding: t - landedAt, mode: mode
    });
    if (p.act) leapTo(p.act);
    else if (p.wait < Infinity) decideTimer = setTimeout(decide, Math.max(0, p.wait) * 1000 + 20);
  }

  // ---------- The intro, once per visit, and where it starts ----------

  var hb = hero.getBoundingClientRect(), headOffset = 3 * hb.width / 16;
  heroGone = hb.top + headOffset < LEAVE_Y;
  var seen = false;
  try { seen = sessionStorage.getItem('bm-intro') === '1'; } catch (e) { /* private mode: play it */ }
  if (!heroGone && hb.top < window.innerHeight && !seen && !late) {
    try { sessionStorage.setItem('bm-intro', '1'); } catch (e) { /* private mode */ }
    root.classList.add('cm-intro');
    intro = clock();
    drawHero(C.launchFrame(0).pose, C.launchFrame(0).shadow);
    kick();
  } else {
    root.classList.add(late ? 'cm-shown' : 'cm-no-intro');
    drawHero(C.restPose(), { opacity: 1, inset: 0 });
    if (heroGone) {
      // Opened further down the page: it is already in the finale, or on its perch.
      var fr = finaleSvg && finaleSvg.getBoundingClientRect();
      finaleIn = !!fr && fr.bottom > NAV && fr.top < window.innerHeight * 0.7;
      finaleGone = !finaleIn;
      bootAt = -Infinity;
      placeInstant(finaleIn ? 'finale' : 'perch');
      bootAt = clock();
    }
  }

  function observe(el, cb, opts) {
    var io = new IntersectionObserver(cb, opts);
    io.observe(el);
    observers.push(io);
  }
  // The hero: it leaves as soon as its head comes within 16 px of the nav (a fast flick moves 40 px a frame).
  observe(hero, function (entries) {
    var e = entries[entries.length - 1];
    heroGone = e.boundingClientRect.top + headOffset < LEAVE_Y;
    decide();
  }, { rootMargin: '-' + Math.max(0, Math.round(LEAVE_Y - headOffset)) + 'px 0px 0px 0px', threshold: [0, 1] });
  if (finale) {
    // The finale: it leaps in once the finale is well in view, and out once it has left the screen.
    observe(finaleSvg, function (entries) { finaleIn = entries[entries.length - 1].isIntersecting; decide(); },
      { rootMargin: '-' + Math.round(NAV) + 'px 0px -30% 0px', threshold: 0 });
    observe(finaleSvg, function (entries) { finaleGone = !entries[entries.length - 1].isIntersecting; decide(); },
      { rootMargin: '-' + Math.round(NAV) + 'px 0px 0px 0px', threshold: 0 });
  }

  // ---------- Reactions ----------

  function canReact() { return where === 'perched' && shown && !leap && !off; }
  function startReaction(kind, look) {
    var t = clock();
    life.prev = C.reactionActive(life.reaction, t) ? life.reaction : null;
    life.reaction = { kind: kind, at: t, look: look || 0 };
    life.idle = null; life.glance = null;
    if (kind === 'doze') life.asleep = { at: t + C.REACT.doze };
    else if (life.asleep) life.asleep = null;
    kick();
  }
  function wakeIfAsleep() {
    if (!life.asleep) return false;
    life.asleep = null;
    startReaction('wake');
    return true;
  }
  // A part of the page that came into view while it was in the air or out of the way: it answers it once it is back.
  var pending = null, dozeLater = false, footerIn = false;
  function replay() {
    var p = pending;
    pending = null;
    if (!p || !canReact()) return;
    var r = p.el.getBoundingClientRect();
    var onScreen = r.bottom > 0 && r.top < window.innerHeight;
    if (onScreen && (clock() - p.at < 2 || (p.key === 'footer' && footerIn))) reactTo(p.key, p.el);
  }
  function reactTo(key, el) {
    if (off) return;
    if (!canReact()) { if ((leap && leap.dest === 'perch') || where === 'perched') pending = { key: key, el: el, at: clock() }; return; }
    pending = null;
    var kind = C.REACTIONS[key];
    if (kind !== 'doze') wakeIfAsleep();
    if (kind === 'look') { var g = lookAtEl(el); life.glance = { at: clock(), look: g.x, down: g.y }; life.idle = null; kick(); return; }
    if (kind === 'doze') {
      if (life.asleep) return;
      // It dozes off once the page is still: a scroll would wake it at once.
      if (C.walkActive(life.walk, clock())) { dozeLater = true; return; }
    }
    startReaction(kind, kind === 'hop' ? lookAtEl(el).x : 0);
  }
  var targets = [['accounts', '#accounts'], ['graph', '.graph-shot'], ['usage', '.usage-shot'], ['ram', '.scene-ram'], ['safety', '#safety']];
  targets.forEach(function (tg) { tg[2] = document.querySelector(tg[1]); });
  var bandTargets = targets.filter(function (tg) { return tg[2]; });
  if (bandTargets.length) {
    var band = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        for (var i = 0; i < bandTargets.length; i++) if (bandTargets[i][2] === e.target) reactTo(bandTargets[i][0], e.target);
      });
    }, { rootMargin: '-35% 0px -35% 0px', threshold: 0 });
    bandTargets.forEach(function (tg) { band.observe(tg[2]); });
    observers.push(band);
  }
  var footer = document.querySelector('.footer');
  if (footer) {
    observe(footer, function (entries) {
      entries.forEach(function (e) {
        footerIn = e.isIntersecting;
        if (footerIn) reactTo('footer', e.target); else dozeLater = false;
      });
    }, { threshold: 0.6 });
  }
  // A click on it: a wave, in the hero or on its perch.
  function clicked() {
    if (off || leap || intro) return;
    if (where === 'perched' && !shown) return;
    if (where === 'home' && slot !== 'hero') return;
    wakeIfAsleep() || startReaction('wave');
  }
  twin.addEventListener('click', clicked);
  hero.addEventListener('click', clicked);

  // How it works: the diagram tells its clock (script.js). The diagram's own creature catches each note; the companion
  // follows the travelling note with its eyes, and hops once when the story is over and nothing else moves.
  function follow(t) {
    if (t > story.t0 + C.FLOW.end) { story = null; life.gaze = null; return false; }
    var notes = story.fig.querySelectorAll('svg.flow .fl-note-slot'), best = null;
    for (var i = 0; i < notes.length; i++) {
      var op = parseFloat(notes[i].getAttribute('opacity') || '0');
      if (op > 0.05) {
        var r = notes[i].getBoundingClientRect();
        if (r.width > 0) { best = r; break; }
      }
    }
    if (best && lastFeet) {
      var u = lastFeet.unit, cy = best.top + best.height / 2;
      life.gaze = { look: C.followLook(best.left + best.width / 2, lastFeet.x, u), down: C.gaze(0, cy - (lastFeet.y - 5.5 * u), u).y };
    } else life.gaze = null;
    return true;
  }
  Array.prototype.forEach.call(document.querySelectorAll('.flow-fig'), function (fig) {
    fig.addEventListener('flowstate', function (e) {
      if (off) return;
      clearTimeout(storyTimer); storyTimer = 0;
      obstacles = null;
      var d = e.detail || {};
      if (d.state !== 'playing') { if (story && story.fig === fig) { story = null; life.gaze = null; kick(); } return; }
      story = { fig: fig, t0: d.t0 / 1000 };
      var wait = C.storyHops(story.t0)[0] + 0.1 - clock();
      storyTimer = setTimeout(function () {
        var r = fig.getBoundingClientRect();
        if (canReact() && r.bottom > 0 && r.top < window.innerHeight) startReaction('hop', lookAtEl(fig).x);
      }, Math.max(0, wait) * 1000);
      kick();
    });
  });

  // ---------- Scrolling: it walks as the page moves under it, facing the way it goes ----------

  function settle() {
    settleTimer = 0;
    if (off) return;
    checkPerch(true);
    decide();
    kick();
  }
  window.addEventListener('scroll', function () {
    var y = window.scrollY, dy = y - lastY, t = clock();
    lastY = y;
    if (!dy || off) return;
    var dt = t - lastScroll;
    scrollVel = dt > 0 && dt < 0.12 ? 0.5 * scrollVel + 0.5 * dy / dt : 0;
    lastScroll = t;
    clearTimeout(settleTimer);
    settleTimer = setTimeout(settle, 260);
    if (where !== 'perched' || !shown) return;
    if (mode === 'corner' && blockedQuick()) { show(false); return; }
    if (life.asleep) wakeIfAsleep();
    life.idle = null;
    life.walk = C.walkAdvance(life.walk, dy, t, unit);
    life.face = dy > 0 ? 1 : -1;
    kick();
  }, { passive: true });
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      if (off) return;
      measureMode();
      obstacles = null;
      if (where === 'perched') { placeAtSpot(); checkPerch(true); }
      decide();
    }, 150);
  }, { passive: true });

  // ---------- In the hero: its eyes follow the reader's pointer, and look down at Download ----------

  var pointerOn = false, pointerQueued = false, lastPointer = null, heroBtnLook = false;
  function inHero() { return where === 'home' && slot === 'hero' && !intro && !leap && !off; }
  function applyPointer() {
    pointerQueued = false;
    if (!inHero() || !lastPointer) return;
    var f = C.heroFeet(hero.getBoundingClientRect());
    var g = C.gaze(lastPointer.clientX - f.x, lastPointer.clientY - (f.y - 5.5 * f.unit), f.unit);
    var next = { look: g.x, down: heroBtnLook ? 1 : g.y };
    if (!life.gaze || life.gaze.look !== next.look || life.gaze.down !== next.down) { life.gaze = next; life.idle = null; kick(); }
  }
  function onPointer(e) { lastPointer = e; if (!pointerQueued) { pointerQueued = true; requestAnimationFrame(applyPointer); } }
  var heroVisible = false;
  function attachGaze() {
    if (!fine || pointerOn || !heroVisible || !(where === 'home' && slot === 'hero') || off) return;
    pointerOn = true;
    document.addEventListener('pointermove', onPointer, { passive: true });
  }
  function detachGaze() {
    if (!pointerOn) return;
    pointerOn = false;
    document.removeEventListener('pointermove', onPointer);
    life.gaze = null;
  }
  observe(hero, function (entries) {
    heroVisible = entries[entries.length - 1].isIntersecting;
    if (heroVisible) attachGaze(); else detachGaze();
  });
  var heroBtn = document.querySelector('.hero .btn-primary');
  if (heroBtn) {
    var btnLook = function (on) {
      heroBtnLook = on;
      if (!inHero()) return;
      life.gaze = on ? { look: 0, down: 1 } : null;
      kick();
    };
    if (fine) {
      heroBtn.addEventListener('pointerenter', function () { btnLook(true); });
      heroBtn.addEventListener('pointerleave', function () { btnLook(false); });
    }
    heroBtn.addEventListener('focus', function () { btnLook(true); });
    heroBtn.addEventListener('blur', function () { btnLook(false); });
  }

  // ---------- Reduce Motion switched on mid-visit, and paper ----------

  function still() {
    off = true;
    observers.forEach(function (io) { io.disconnect(); });
    cancelAnimationFrame(raf); raf = 0;
    [timer, settleTimer, decideTimer, showTimer, storyTimer, resizeTimer].forEach(clearTimeout);
    timer = settleTimer = decideTimer = showTimer = storyTimer = resizeTimer = 0;
    intro = null; leap = null; story = null; life = C.freshState();
    detachGaze();
    where = 'home'; slot = 'hero';
    hero.classList.remove('is-away');
    show(false, true);
    drawHero(C.restPose(), { opacity: 1, inset: 0 });
    tell('cm-still');
    [layer, corner].forEach(function (el) { if (el.parentNode) el.parentNode.removeChild(el); });
    root.classList.remove('cm-nav');
  }
  if (motionQuery.addEventListener) {
    motionQuery.addEventListener('change', function () { if (!motionQuery.matches && !off) still(); });
  }
  window.addEventListener('beforeprint', function () { drawHero(C.restPose(), { opacity: 1, inset: 0 }); hero.classList.remove('is-away'); });
  window.addEventListener('afterprint', function () { if (!off && !(where === 'home' && slot === 'hero')) hero.classList.add('is-away'); });
})();
