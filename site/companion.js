// Brainmerge: the reading companion. The hero creature assembles as the app does at launch (LaunchScene.swift), leaps
// into a corner once the hero scrolls away (the app's leap into the sidebar footer), walks while the page scrolls, and
// answers what is on screen with the app's own repertoire (CreatureLife.swift). Decorative: it never takes the focus,
// never covers text or a button, and with Reduce Motion the hero creature is simply there, still.
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

    // ---------- The walk (Creature.walkFrame, CreatureWalk) ----------

    var WALK = { frame: 0.12, cycle: 4 };
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
    // The walk's frame at t: the passing frame first, so the first scroll shows at once.
    function walkIndex(t, start) { return 1 + Math.floor((t - start) / WALK.frame + 1e-9); }
    // It never stops mid-step: it runs on to its next contact frame after `end`.
    function walkStop(start, end) {
      var k = Math.max(0, Math.ceil((end - start) / WALK.frame - 1e-9));
      if (k % 2 === 0) k += 1;
      return start + k * WALK.frame;
    }

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
    // The long hand-off (GuideExit): its apex a fifth of the way across, less a quarter of the fall, 12 px at least,
    // never closer than 40 px to the top; past 250 px across, the flight takes 0.6 s.
    function exitApex(dx, dy, higherFeetY) {
      var cap = Math.max(LEAP.apex, higherFeetY - 40);
      return Math.min(Math.max(0.2 * Math.abs(dx) - 0.25 * Math.abs(dy), LEAP.apex), cap);
    }
    function exitFlight(dx) { return Math.abs(dx) > LEAP.longWay ? LEAP.longFlight : LEAP.flight; }
    // A leap from `feet` (px, the middle of the feet's bottom edge) and cell `unit`, moving `vy` px/s (negative is up),
    // to `target` {x, y, unit}. Its target may move while it flies (a page that scrolls): every frame reads it.
    function makeLeap(o) {
      var L = {
        start: o.pose || restPose(), feet: { x: o.feet.x, y: o.feet.y }, unit: o.unit, vy: o.vy || 0,
        target: { x: o.target.x, y: o.target.y, unit: o.target.unit, asleep: !!o.target.asleep },
        crouch: Math.max(o.crouch || LEAP.anticipation, LEAP.anticipation), flight: o.flight || LEAP.flight,
        apex: o.apex == null ? LEAP.apex : o.apex
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
      return kept.g >= ground.g / 2 ? kept : ground;
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
        pose.sprites.push({ pattern: pattern, x: 8 + tr[0] * p, y: -H - 0.6 + tr[1] * p,
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
    var Z = { born: 0.2, life: 2.6 };
    function sleepZ(age) {
      if (!(age >= 0 && age < Z.life)) return null;
      var f = age / Z.life, p = Ease.travel(f);
      return { pattern: ZEE, x: 15.8 + 1.8 * p + 0.5 * Math.sin(2 * Math.PI * f), y: -1.3 - 3.5 * p, light: false,
        opacity: Math.min(age / 0.3, 1) * Math.min((Z.life - age) / 0.9, 1) * 0.72 };
    }

    // Once still, the companion lives a little, then holds: a blink at 1.3 s, a glance at the content beside it from
    // 3.1 s for a second, a blink as the eyes come back. After 4.2 s nothing changes until something happens.
    var IDLE = { blinkAt: 1.3, glanceAt: 3.1, hold: 1.0 };
    IDLE.end = IDLE.glanceAt + IDLE.hold + 0.10;
    function idleEyes(d, side) {
      var eyeH = blink(d - IDLE.blinkAt) || blink(d - (IDLE.glanceAt + IDLE.hold - 0.04)) || 1;
      var look = d >= IDLE.glanceAt && d < IDLE.glanceAt + IDLE.hold ? side : 0;
      return { eyeH: eyeH, look: look };
    }
    function idleSteps() {
      var b1 = IDLE.blinkAt, b2 = IDLE.glanceAt + IDLE.hold - 0.04;
      return [b1, b1 + 0.04, b1 + 0.10, b1 + 0.14, IDLE.glanceAt, b2, b2 + 0.04, IDLE.glanceAt + IDLE.hold, b2 + 0.10, b2 + 0.14];
    }
    // A look at a section (Graph, Usage): the eyes on it for 1.2 s, a blink 40 ms before they come back.
    var GLANCE = 1.2;

    // The companion's life at t, from its state:
    //   walk {start, end}   while the page scrolls; face: the scroll's direction (1 down, -1 up)
    //   reaction {kind, at, look}, prev: the one it interrupted (the body blends from it over 120 ms)
    //   idle {at, side}     the short life once still; glance {at, look}: a look at a section
    //   gaze {look, down}   a live look (the pointer, the travelling note, the button under the pointer)
    //   asleep {at}         asleep from `at`, one Z floating up from there
    function freshState() { return { walk: null, face: 0, reaction: null, prev: null, idle: null, glance: null, gaze: null, asleep: null }; }
    function reactionActive(r, t) { return !!r && t >= r.at && t < r.at + REACT[r.kind]; }
    function walkActive(w, t) { return !!w && t >= w.start && (w.end == null || t < walkStop(w.start, w.end)); }
    function reactPose(r, t) {
      var p = restPose();
      react(r.kind, t - r.at, p);
      if (r.look && r.kind === 'hop') p.look = r.look;
      return p;
    }
    function lifeFrame(s, t) {
      var pose = restPose(), shadow = { opacity: 1, inset: 0 };
      var walking = walkActive(s.walk, t);
      if (s.asleep && t >= s.asleep.at) {
        pose.eyeH = 0.35; pose.eyeBottom = 2.35;
        var z = sleepZ(t - s.asleep.at - Z.born);
        if (z) pose.sprites.push(z);
      } else {
        // The eyes: a look at a section first, then a live look, then the way it walks, then the idle.
        if (s.idle) { var e = idleEyes(t - s.idle.at, s.idle.side); pose.eyeH = e.eyeH; pose.look = e.look; }
        if (walking && s.face) pose.look = s.face > 0 ? 1 : -1;
        if (s.gaze) { pose.look = s.gaze.look; pose.lookDown = s.gaze.down || 0; }
        if (s.glance) {
          var dg = t - s.glance.at;
          if (dg >= 0 && dg < GLANCE) pose.look = s.glance.look;
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
        var i = walkIndex(t, s.walk.start), wf = walkFrame(i);
        pose.raise = wf.raise; pose.lifted = wf.lifted; pose.armL = wf.armL; pose.armR = wf.armR;
        shadow.inset = walkShadowInset(i);
      }
      return { pose: pose, shadow: shadow };
    }
    // True while something moves smoothly: a reaction, the walk, the Z floating up. Blinks and looks are stepped: they
    // wait for `nextChange`, never for frames.
    function needsFrames(s, t) {
      if (reactionActive(s.reaction, t) || walkActive(s.walk, t)) return true;
      if (s.asleep && t >= s.asleep.at) { var age = t - s.asleep.at - Z.born; return age >= 0 && age < Z.life; }
      return false;
    }
    // The next time after t the frame changes on its own, or Infinity: the companion then holds still.
    function nextChange(s, t) {
      var c = [];
      if (s.idle) idleSteps().forEach(function (d) { c.push(s.idle.at + d); });
      if (s.glance) [0, GLANCE - 0.04, GLANCE, GLANCE + 0.06, GLANCE + 0.10].forEach(function (d) { c.push(s.glance.at + d); });
      if (s.reaction) c.push(s.reaction.at);
      if (s.walk) c.push(s.walk.start);
      if (s.asleep) c.push(s.asleep.at, s.asleep.at + Z.born);
      var next = Infinity;
      c.forEach(function (x) { if (x > t + 1e-6 && x < next) next = x; });
      return next;
    }

    // ---------- Where it looks, where it sits ----------

    // Toward a point dx, dy px away: one whole cell sideways once past the body, one row down once well below. Never up.
    function gaze(dx, dy, cell) { return { x: dx < -8 * cell ? -1 : dx > 8 * cell ? 1 : 0, y: dy > 7 * cell ? 1 : 0 }; }
    // The travelling note of How it works, followed across the screen: left, middle, right.
    function followLook(x, width) { return x < 0.4 * width ? -1 : x > 0.6 * width ? 1 : 0; }
    // The perch's feet in an anchor box (16 by 12 cells: the grid and its shadow row).
    function perchFeet(rect) { var u = rect.width / COLS; return { x: rect.left + 8 * u, y: rect.top + 11 * u, unit: u }; }
    // The hero creature's feet in its box: its viewBox starts 3 cells above the head.
    function heroFeet(rect) { var u = rect.width / COLS; return { x: rect.left + 8 * u, y: rect.top + 14 * u, unit: u }; }
    // Whether two rectangles overlap.
    function overlaps(a, b) { return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom; }

    // How it works, on the diagram's own clock (script.js, Motion.STORY): three beats of 2.4 s, each note landing 1 s in.
    var FLOW = { beat: 2.4, land: 1.0, beats: 3, end: 7.4 };
    function flowLandings() {
      var out = [];
      for (var b = 0; b < FLOW.beats; b++) out.push(b * FLOW.beat + FLOW.land);
      return out;
    }

    // What each part of the page brings out of it.
    var REACTIONS = { accounts: 'wave', flow: 'hop', graph: 'look', usage: 'look', ram: 'look', safety: 'nod', download: 'hop', footer: 'doze', click: 'wave' };

    return {
      clamp01: clamp01, progress: progress, steps: steps, bezier: bezier, Ease: Ease, springDisp: springDisp,
      springValue: springValue, settleTime: settleTime, hash01: hash01, sign: sign,
      GRID: GRID, PIXELS: PIXELS, LEGS: LEGS, ARMS: ARMS, restPose: restPose, copyPose: copyPose, poseCells: poseCells,
      eyeRects: eyeRects, cellsPath: cellsPath, spritePath: spritePath, SPARKLES: SPARKLES, ZEE: ZEE, sparkle: sparkle,
      WALK: WALK, walkFrame: walkFrame, walkShadowInset: walkShadowInset, walkIndex: walkIndex, walkStop: walkStop,
      LAUNCH: LAUNCH, pixelStates: pixelStates, launchFrame: launchFrame, blinkKeys: blinkKeys,
      LEAP: LEAP, exitApex: exitApex, exitFlight: exitFlight, makeLeap: makeLeap, leapFrame: leapFrame, ballistics: ballistics,
      REACT: REACT, HOP_HEIGHT: HOP_HEIGHT, react: react, blink: blink, Z: Z, sleepZ: sleepZ,
      IDLE: IDLE, idleEyes: idleEyes, idleSteps: idleSteps, GLANCE: GLANCE,
      freshState: freshState, lifeFrame: lifeFrame, needsFrames: needsFrames, nextChange: nextChange,
      reactionActive: reactionActive, walkActive: walkActive,
      gaze: gaze, followLook: followLook, perchFeet: perchFeet, heroFeet: heroFeet, overlaps: overlaps,
      FLOW: FLOW, flowLandings: flowLandings, REACTIONS: REACTIONS
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

  // The companion: a copy of the hero creature in a fixed layer, and two perches it can sit on (companion.css places
  // them in the corners, inside the safe areas). Pointer events on its drawn cells only.
  var layer = document.createElement('div');
  layer.className = 'companion';
  layer.setAttribute('aria-hidden', 'true');
  var twin = hero.cloneNode(true);
  twin.removeAttribute('role'); twin.removeAttribute('aria-label');
  twin.setAttribute('class', 'cm-svg');
  twin.setAttribute('viewBox', '0 0 16 12');
  twin.setAttribute('focusable', 'false');
  layer.appendChild(twin);
  var perches = ['a', 'b'].map(function (name) {
    var el = document.createElement('i');
    el.className = 'cm-perch cm-perch-' + name;
    el.setAttribute('aria-hidden', 'true');
    document.body.appendChild(el);
    return { name: name, el: el };
  });
  document.body.appendChild(layer);
  var drawHero = view(hero), drawTwin = view(twin);

  // Where the creature is: in the hero ('hero'), leaping out ('out'), on its perch ('perched'), or leaping home ('back').
  var where = 'hero';
  var life = C.freshState();
  var intro = null, leap = null, spot = perches[0], shown = false, lastScroll = -1, lastY = window.scrollY;
  var lastFeet = null, lastFeetAt = 0, prevFeet = null, prevFeetAt = 0;
  var raf = 0, timer = 0, settleTimer = 0, dirty = false, story = null, storyTimers = [], off = false, heroInView = true;

  // One loop, running only while something moves; stepped changes (a blink, a look) wake it with a timer.
  function kick() {
    if (off) return;
    if (timer) { clearTimeout(timer); timer = 0; }
    if (!raf) raf = requestAnimationFrame(frame);
  }
  function frame() {
    raf = 0;
    var t = clock(), moving = render(t);
    if (moving) { raf = requestAnimationFrame(frame); return; }
    var next = C.nextChange(life, t);
    if (next < Infinity) timer = setTimeout(kick, Math.max(1, (next - t) * 1000 + 2));
  }

  function place(feet, unit) {
    var u0 = spotUnit();
    layer.style.transform = 'translate(' + r3(feet.x - 8 * u0) + 'px, ' + r3(feet.y - 11 * u0) + 'px)' + (Math.abs(unit - u0) > 1e-3 ? ' scale(' + r3(unit / u0) + ')' : '');
    prevFeet = lastFeet; prevFeetAt = lastFeetAt;
    lastFeet = { x: feet.x, y: feet.y, unit: unit }; lastFeetAt = clock();
  }
  function spotRect(p) { return p.el.getBoundingClientRect(); }
  function spotUnit() { return spotRect(perches[0]).width / 16; }
  function spotFeet(p) { return C.perchFeet(spotRect(p)); }
  function show(on, instant) {
    if (shown === on && !instant) return;
    shown = on;
    layer.classList.toggle('is-instant', !!instant);
    layer.classList.toggle('is-on', on);
  }

  // What must never be covered: words, links and buttons, pictures, the Dock, the cards of the illustrations.
  var SOLID = 'a, button, input, select, textarea, img, picture, video, canvas, svg, code, pre, table, .btn, .mac, .dock, .dock-stage, .card, .window, [role="img"]';
  var TEXT = 'p, h1, h2, h3, h4, h5, li, dt, dd, figcaption, blockquote, label';
  function blocked(rect) {
    var pad = 6, box = { left: rect.left - pad, right: rect.right + pad, top: rect.top - pad, bottom: rect.bottom + pad };
    var seen = [];
    for (var i = 0; i <= 4; i++) {
      for (var j = 0; j <= 2; j++) {
        var x = box.left + (box.right - box.left) * i / 4, y = box.top + (box.bottom - box.top) * j / 2;
        if (x < 0 || y < 0 || x >= window.innerWidth || y >= window.innerHeight) continue;
        var stack = document.elementsFromPoint(x, y);
        var el = null;
        for (var k = 0; k < stack.length; k++) if (!layer.contains(stack[k])) { el = stack[k]; break; }
        if (!el || el === document.body || el === root || seen.indexOf(el) >= 0) continue;
        seen.push(el);
        if (el.closest(SOLID)) return true;
        var text = el.closest(TEXT);
        if (text) {
          var range = document.createRange();
          range.selectNodeContents(text);
          var lines = range.getClientRects();
          for (var m = 0; m < lines.length; m++) if (lines[m].width > 0 && C.overlaps(box, lines[m])) return true;
        }
      }
    }
    return false;
  }
  // The perch it sits on: where it is when that is clear, else the other corner once the page is still, else it fades
  // out of the way until a corner clears.
  function checkPerch(settled) {
    if (where !== 'perched') return;
    if (!blocked(spotRect(spot))) { if (!shown && settled) { placeAtSpot(); show(true); replay(); } return; }
    if (settled) {
      var other = spot === perches[0] ? perches[1] : perches[0];
      if (!blocked(spotRect(other))) {
        show(false);
        spot = other;
        setTimeout(function () { if (where === 'perched' && spot === other) { placeAtSpot(); show(true); replay(); } }, 160);
        return;
      }
    }
    show(false);
  }
  function placeAtSpot() { var f = spotFeet(spot); place(f, f.unit); }
  function landingSpot() {
    if (!blocked(spotRect(spot))) return spot;
    var other = spot === perches[0] ? perches[1] : perches[0];
    return blocked(spotRect(other)) ? spot : other;
  }
  // The content beside the perch: toward the middle of the screen.
  function contentSide() { return lastFeet && lastFeet.x > window.innerWidth / 2 ? -1 : 1; }
  function lookAtEl(el) {
    if (!lastFeet) return 0;
    var r = el.getBoundingClientRect(), dx = r.left + r.width / 2 - lastFeet.x;
    return Math.abs(dx) < 8 * lastFeet.unit ? 0 : dx < 0 ? -1 : 1;
  }

  function render(t) {
    if (intro) {
      var f = C.launchFrame(t - intro);
      drawHero(f.pose, f.shadow);
      if (t - intro < C.LAUNCH.heroTime) return true;
      intro = null;
      life.idle = { at: t, side: -1 };
    }
    if (leap) {
      var tau = t - leap.t0, L = leap.L;
      if (leap.home) { var h = C.heroFeet(hero.getBoundingClientRect()); L.target.x = h.x; L.target.y = h.y; L.target.unit = h.unit; }
      var lf = C.leapFrame(L, tau);
      // The shadow thins out and goes as it lifts off, and comes back under it as it lands.
      var away = C.Ease.out(C.progress(tau, L.takeoff / 2, 0.16)), back = C.Ease.out(C.progress(tau, L.touchdown, 0.16));
      var shade = tau < L.touchdown ? { opacity: 1 - away, inset: 3 * away } : { opacity: back, inset: 3 * (1 - back) };
      if (leap.home && tau >= L.touchdown) {
        // Home: the hero draws the landing, in the page, where it scrolls with it.
        if (where !== 'hero') { where = 'hero'; hero.classList.remove('is-away'); show(false, true); }
        drawHero(lf.pose, { opacity: 1, inset: 0 });
      } else {
        drawTwin(lf.pose, shade);
        place(lf.feet, lf.unit);
      }
      if (tau < L.end) return true;
      var wasHome = leap.home;
      leap = null;
      layer.classList.remove('is-flying');
      life = C.freshState();
      if (wasHome) {
        life.idle = { at: t, side: -1 };
        // Scrolled away again while it came home: straight back out.
        if (!heroInView) { leapOut(); return true; }
        attachGaze();
      }
      else {
        where = 'perched';
        life.idle = { at: t, side: contentSide() };
        checkPerch(true);
        replay();
      }
    }
    if (where !== 'hero' && where !== 'perched') return false;
    // The walk ends a beat after the last scroll, on its next contact frame; then the short idle.
    if (life.walk && life.walk.end == null && t - lastScroll > 0.15) life.walk.end = t;
    if (life.walk && life.walk.end != null && t >= C.walkStop(life.walk.start, life.walk.end)) {
      life.walk = null; life.face = 0;
      if (!life.asleep) life.idle = { at: t, side: contentSide() };
      if (dozeLater && footerIn && shown) { dozeLater = false; startReaction('doze'); }
    }
    var following = false;
    if (story && where === 'perched' && shown) following = follow(t);
    var lf2 = C.lifeFrame(life, t);
    if (where === 'hero') drawHero(lf2.pose, lf2.shadow); else drawTwin(lf2.pose, lf2.shadow);
    if (dirty && where === 'perched') { dirty = false; checkPerch(false); }
    return C.needsFrames(life, t) || following;
  }

  // ---------- The intro, once per visit ----------

  var seen = false;
  try { seen = sessionStorage.getItem('bm-intro') === '1'; sessionStorage.setItem('bm-intro', '1'); } catch (e) { /* private mode: play it */ }
  var heroBox = hero.getBoundingClientRect();
  var heroOnScreen = heroBox.bottom > 60 && heroBox.top < window.innerHeight;
  if (!seen && heroOnScreen) {
    root.classList.add('cm-intro');
    intro = clock();
    drawHero(C.launchFrame(0).pose, C.launchFrame(0).shadow);
    kick();
  } else {
    root.classList.add('cm-no-intro');
    drawHero(C.restPose(), { opacity: 1, inset: 0 });
  }

  // ---------- Leaping out and home ----------

  function currentPose() {
    if (intro) { var f = C.launchFrame(C.LAUNCH.heroTime); intro = null; return f.pose; }
    return C.lifeFrame(life, clock()).pose;
  }
  function leapOut() {
    var t = clock(), r = hero.getBoundingClientRect(), from = C.heroFeet(r);
    var pose = currentPose(), vy = 0;
    // Caught on its way home: it turns in the air, keeping the speed it has.
    if (where === 'back' && leap && lastFeet) {
      pose = C.leapFrame(leap.L, t - leap.t0).pose;
      from = lastFeet;
      if (prevFeet && lastFeetAt > prevFeetAt) vy = (lastFeet.y - prevFeet.y) / (lastFeetAt - prevFeetAt);
    }
    detachGaze();
    spot = landingSpot();
    var to = spotFeet(spot);
    var L = C.makeLeap({
      pose: pose, feet: from, unit: from.unit, vy: vy, target: to, flight: C.exitFlight(to.x - from.x),
      apex: C.exitApex(to.x - from.x, to.y - from.y, Math.min(from.y, to.y))
    });
    life = C.freshState();
    leap = { L: L, t0: t, home: false };
    where = 'out';
    hero.classList.add('is-away');
    layer.classList.add('is-flying');
    show(true, true);
    place(from, from.unit);
    kick();
  }
  function leapHome() {
    var t = clock(), to = C.heroFeet(hero.getBoundingClientRect());
    var from = lastFeet || spotFeet(spot), pose = C.lifeFrame(life, t).pose;
    // Grabbed mid-air: it keeps the speed it has (Leap from the air), no crouch.
    var vy = 0;
    if (where === 'out' && prevFeet && lastFeetAt > prevFeetAt) vy = (lastFeet.y - prevFeet.y) / (lastFeetAt - prevFeetAt);
    if (where === 'out' && leap) pose = C.leapFrame(leap.L, t - leap.t0).pose;
    var L = C.makeLeap({
      pose: pose, feet: from, unit: from.unit, vy: vy, target: to, flight: C.exitFlight(to.x - from.x),
      apex: C.exitApex(to.x - from.x, to.y - from.y, Math.min(from.y, to.y))
    });
    life = C.freshState();
    leap = { L: L, t0: t, home: true };
    where = 'back';
    layer.classList.add('is-flying');
    show(true, true);
    kick();
  }

  var firstLook = true;
  new IntersectionObserver(function (entries) {
    var e = entries[entries.length - 1];
    // It leaves as soon as the nav starts to cover it, and comes home once it is whole again.
    var inView = e.intersectionRatio >= 0.99, gone = e.intersectionRatio < 0.9;
    heroInView = !gone;
    var above = e.rootBounds ? e.boundingClientRect.top < e.rootBounds.top + 1 : e.boundingClientRect.top < 0;
    if (firstLook) {
      firstLook = false;
      if (gone && above) {
        // Opened further down the page: it is already on its perch.
        intro = null;
        drawHero(C.restPose(), { opacity: 1, inset: 0 });
        hero.classList.add('is-away');
        where = 'perched';
        spot = landingSpot();
        placeAtSpot();
        drawTwin(C.restPose(), { opacity: 1, inset: 0 });
        checkPerch(true);
        return;
      }
    }
    if (gone && above && (where === 'hero' || where === 'back')) leapOut();
    else if (inView && (where === 'perched' || where === 'out')) leapHome();
  }, { rootMargin: '-52px 0px 0px 0px', threshold: [0, 0.9, 0.99, 1] }).observe(hero);

  // ---------- Reactions ----------

  function canReact() { return where === 'perched' && shown && !leap; }
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
  // A part of the page that came into view while it was in the air: it answers it once it has landed.
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
    // Seen while it was in the air or out of the way: it answers once it is back, if that part is still on screen.
    if (!canReact()) { if ((leap && !leap.home) || where === 'perched') pending = { key: key, el: el, at: clock() }; return; }
    pending = null;
    var kind = C.REACTIONS[key];
    if (kind !== 'doze') wakeIfAsleep();
    if (kind === 'look') { life.glance = { at: clock(), look: lookAtEl(el) }; life.idle = null; kick(); return; }
    if (kind === 'doze') {
      if (life.asleep) return;
      // It dozes off once the page is still: a scroll would wake it at once.
      if (C.walkActive(life.walk, clock())) { dozeLater = true; return; }
    }
    startReaction(kind, kind === 'hop' ? lookAtEl(el) : 0);
  }
  var targets = [
    ['accounts', '#accounts'], ['graph', '.graph-shot'], ['usage', '.usage-shot'], ['ram', '.scene-ram'],
    ['safety', '#safety'], ['download', '#download .actions']
  ];
  var band = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      for (var i = 0; i < targets.length; i++) if (targets[i][2] === e.target) reactTo(targets[i][0], e.target);
    });
  }, { rootMargin: '-35% 0px -35% 0px', threshold: 0 });
  targets.forEach(function (tg) { var el = document.querySelector(tg[1]); if (el) { tg[2] = el; band.observe(el); } });
  var footer = document.querySelector('.footer');
  if (footer) {
    new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        footerIn = e.isIntersecting;
        if (footerIn) reactTo('footer', e.target); else dozeLater = false;
      });
    }, { threshold: 0.6 }).observe(footer);
  }
  // The download button: it hops again when the pointer or the keyboard reaches it.
  var dlBtn = document.querySelector('#download .btn-primary');
  if (dlBtn) {
    var dlHop = function () { if (canReact()) { wakeIfAsleep(); startReaction('hop', lookAtEl(dlBtn)); } };
    if (fine) dlBtn.addEventListener('pointerenter', dlHop);
    dlBtn.addEventListener('focus', dlHop);
  }
  // A click on it: a wave, in the hero or on its perch.
  function clicked() {
    if (leap || intro) return;
    if (where === 'perched' && !shown) return;
    wakeIfAsleep() || startReaction('wave');
  }
  twin.addEventListener('click', clicked);
  hero.addEventListener('click', clicked);

  // How it works: the diagram tells its clock (script.js). The eyes follow the travelling note; each note that lands
  // in a memory gets a hop with sparkles.
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
    life.gaze = best ? { look: C.followLook(best.left + best.width / 2, window.innerWidth), down: 0 } : null;
    return true;
  }
  Array.prototype.forEach.call(document.querySelectorAll('.flow-fig'), function (fig) {
    fig.addEventListener('flowstate', function (e) {
      storyTimers.forEach(clearTimeout);
      storyTimers = [];
      var d = e.detail || {};
      if (d.state !== 'playing') { if (story && story.fig === fig) { story = null; life.gaze = null; kick(); } return; }
      story = { fig: fig, t0: d.t0 / 1000 };
      C.flowLandings().forEach(function (at) {
        var wait = story.t0 + at - clock();
        if (wait > 0) storyTimers.push(setTimeout(function () { if (canReact()) startReaction('hop'); }, wait * 1000));
      });
      kick();
    });
  });

  // ---------- Scrolling: it walks, facing the way the page goes ----------

  window.addEventListener('scroll', function () {
    var y = window.scrollY, dy = y - lastY;
    lastY = y;
    if (!dy || where !== 'perched') return;
    var t = clock();
    lastScroll = t;
    dirty = true;
    if (shown && life.asleep) wakeIfAsleep();
    life.idle = null;
    if (!C.walkActive(life.walk, t)) life.walk = { start: t, end: null };
    else life.walk.end = null;
    life.face = dy > 0 ? 1 : -1;
    kick();
    clearTimeout(settleTimer);
    settleTimer = setTimeout(function () { checkPerch(true); kick(); }, 220);
  }, { passive: true });
  window.addEventListener('resize', function () {
    if (where === 'perched') { placeAtSpot(); checkPerch(true); }
  }, { passive: true });

  // ---------- In the hero: its eyes follow the reader's pointer, and look down at Download ----------

  var pointerOn = false, pointerQueued = false, lastPointer = null, heroBtnLook = false;
  function applyPointer() {
    pointerQueued = false;
    if (where !== 'hero' || intro || leap || !lastPointer) return;
    var r = hero.getBoundingClientRect(), f = C.heroFeet(r);
    var g = C.gaze(lastPointer.clientX - f.x, lastPointer.clientY - (f.y - 5.5 * f.unit), f.unit);
    var next = { look: g.x, down: heroBtnLook ? 1 : g.y };
    if (!life.gaze || life.gaze.look !== next.look || life.gaze.down !== next.down) { life.gaze = next; life.idle = null; kick(); }
  }
  function onPointer(e) { lastPointer = e; if (!pointerQueued) { pointerQueued = true; requestAnimationFrame(applyPointer); } }
  var heroVisible = false;
  function attachGaze() {
    if (!fine || pointerOn || !heroVisible || where !== 'hero') return;
    pointerOn = true;
    document.addEventListener('pointermove', onPointer, { passive: true });
  }
  function detachGaze() {
    if (!pointerOn) return;
    pointerOn = false;
    document.removeEventListener('pointermove', onPointer);
    life.gaze = null;
  }
  new IntersectionObserver(function (entries) {
    heroVisible = entries[entries.length - 1].isIntersecting;
    if (heroVisible) attachGaze(); else detachGaze();
  }).observe(hero);
  var heroBtn = document.querySelector('.hero .btn-primary');
  if (heroBtn) {
    var btnLook = function (on) {
      heroBtnLook = on;
      if (where !== 'hero' || intro || leap) return;
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
    cancelAnimationFrame(raf); raf = 0; clearTimeout(timer); timer = 0;
    storyTimers.forEach(clearTimeout);
    intro = null; leap = null; story = null; life = C.freshState();
    detachGaze();
    where = 'hero';
    hero.classList.remove('is-away');
    show(false, true);
    drawHero(C.restPose(), { opacity: 1, inset: 0 });
  }
  if (motionQuery.addEventListener) {
    motionQuery.addEventListener('change', function () {
      if (motionQuery.matches) return;
      still();
      layer.parentNode && layer.parentNode.removeChild(layer);
      motion = false;
    });
  }
  window.addEventListener('beforeprint', function () { drawHero(C.restPose(), { opacity: 1, inset: 0 }); hero.classList.remove('is-away'); });
  window.addEventListener('afterprint', function () { if (where !== 'hero') hero.classList.add('is-away'); });
})();
