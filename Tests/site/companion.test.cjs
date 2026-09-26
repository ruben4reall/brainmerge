// The reading companion: the pure functions of site/companion.js, checked against the app's own scenes
// (LaunchScene.swift, CreatureLife.swift, CreatureView.swift). Run from the repository root:
// node --test Tests/site/companion.test.cjs
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const SITE = path.join(__dirname, '..', '..', 'site');
const read = name => fs.readFileSync(path.join(SITE, name), 'utf8');
global.location = { hostname: 'localhost' };
const C = require(path.join(SITE, 'companion.js'));
const M = require(path.join(SITE, 'script.js'));
const DESIGN = path.join(__dirname, '..', '..', 'Packages', 'BrainmergeUI', 'Sources', 'BrainmergeUI', 'Design');
const swift = name => fs.readFileSync(path.join(DESIGN, name), 'utf8');
const close = (a, b, e = 1e-3) => assert.ok(Math.abs(a - b) <= e, `${a} != ${b}`);
const rest = () => C.restPose();
const isRest = (p, what) => assert.deepStrictEqual(p, rest(), what);

// ---------- The creature ----------

test('the grid is the app\'s, and the rest pose draws exactly it', () => {
  const rows = swift('CreatureView.swift').match(/"[X.]{16}"/g).map(r => r.slice(1, -1));
  assert.deepStrictEqual(C.GRID, rows);
  const cells = C.poseCells(rest()).map(c => c.join(',')).sort();
  assert.deepStrictEqual(cells, C.PIXELS.map(p => `${p.x},${p.y},1,1`).sort());
  assert.deepStrictEqual(C.eyeRects(rest()), [[4, 1, 1, 1], [11, 1, 1, 1]]);
});

test('the hero creature in the page is the rest grid, so it is whole without the script and with Reduce Motion', () => {
  const html = read('index.html');
  const svg = /<svg class="creature hero-creature"[\s\S]*?<\/svg>/.exec(html)[0];
  assert.ok(svg.includes(`class="cm-cells" d="${C.cellsPath(C.poseCells(rest()))}"`));
  assert.ok(svg.includes('<rect x="4" y="1" width="1" height="1"/><rect x="11" y="1" width="1" height="1"/>'));
  assert.ok(/role="img" aria-label="The Brainmerge creature/.test(svg));
});

test('the die per pixel is the app\'s (Dice.hash01, 64-bit)', () => {
  // Values printed by the app's own function in Swift.
  close(C.hash01(0, 3, 0), 0.7596, 1e-9);
  close(C.hash01(2, 0, 0), 0.5235, 1e-9);
  close(C.hash01(15, 5, 7), 0.8343, 1e-9);
  close(C.hash01(13, 10, 7), 0.6082, 1e-9);
  close(C.hash01(7, 4, 0), 0.4900, 1e-9);
  close(C.hash01(8, 6, 7), 0.6292, 1e-9);
});

test('the timings are the app\'s: Theme.Launch and AssembleScene', () => {
  const theme = swift('Theme.swift'), scene = swift('LaunchScene.swift');
  const L = C.LAUNCH;
  assert.ok(new RegExp(`static let unit: CGFloat = ${L.unit}\\b`).test(theme));
  assert.ok(new RegExp(`gatherSpread = ${L.gatherSpread}\\b`).test(theme));
  assert.ok(new RegExp(`heroTime: TimeInterval = ${L.heroTime}\\b`).test(theme));
  assert.ok(/static let leap: TimeInterval = 0\.50/.test(theme) && C.LEAP.flight === 0.5);
  assert.ok(/leapApex: CGFloat = 12/.test(theme) && C.LEAP.apex === 12);
  assert.ok(/anticipation: TimeInterval = 0\.08/.test(theme) && C.LEAP.anticipation === 0.08);
  assert.ok(scene.includes(`static let clickAt = ${L.clickAt}, clickVelocity = ${L.clickVelocity}, clickSettled = ${L.clickSettled.toFixed(2)}`));
  assert.ok(scene.includes(`static let click = Ease.Spring(response: ${L.click[0].toFixed(2)}, damping: ${L.click[1]})`));
  assert.ok(scene.includes(`static let hopCrouch = ${L.hopCrouch}, hopTakeoff = ${L.hopTakeoff}, hopLand = ${L.hopLand}`));
  assert.ok(scene.includes(`static let pixelSpring = Ease.Spring(response: ${L.pixelSpring[0].toFixed(2)}, damping: ${L.pixelSpring[1]})`));
  assert.ok(scene.includes(`public static let wordmarkIn = ${L.wordmarkIn}, wordmarkDuration = ${L.wordmarkDuration.toFixed(2)}`));
  assert.ok(scene.includes(`static let blinkAt = ${L.blinkAt.toFixed(2)}`));
  // The landing settles where the app's does: 0.3873 s after touchdown.
  close(C.LEAP.settled, 0.3873064864427477, 1e-9);
});

// ---------- 1. The launch ----------

test('the launch ends on the rest grid, whole, eyes open, the wordmark in', () => {
  const end = C.launchFrame(C.LAUNCH.heroTime);
  isRest(end.pose, 'at 1.46 s it is the grid');
  assert.deepStrictEqual(end.shadow, { opacity: 1, inset: 0 });
  assert.deepStrictEqual(end.word, { opacity: 1, rise: 0 });
  // It is already still a little earlier: the landing's ringing is cut at 1.44 s and the blink is over.
  isRest(C.launchFrame(1.445).pose);
});

test('the launch starts from nothing: an invisible, exploded cloud, no eyes, no shadow, no wordmark', () => {
  const f = C.launchFrame(0);
  assert.strictEqual(f.pose.eyeH, 0);
  assert.strictEqual(f.pose.pixels.length, 120);
  f.pose.pixels.forEach(p => { assert.strictEqual(p.o, 0); assert.ok(Math.hypot(p.dx, p.dy) > 0.5); });
  assert.strictEqual(f.shadow.opacity, 0);
  assert.strictEqual(f.word.opacity, 0);
  assert.strictEqual(C.launchFrame(0.519).word.opacity, 0);
  assert.ok(C.launchFrame(0.7).word.opacity > 0.9);
});

test('the gather: inner pixels first, every pixel home by 0.58 s, and the swap to one path is invisible', () => {
  const at = t => C.pixelStates(t);
  const inner = C.PIXELS.findIndex(p => p.x === 7 && p.y === 5), rim = C.PIXELS.findIndex(p => p.x === 0 && p.y === 3);
  assert.ok(Math.hypot(at(0.2)[inner].dx, at(0.2)[inner].dy) < Math.hypot(at(0.2)[rim].dx, at(0.2)[rim].dy));
  assert.strictEqual(at(C.LAUNCH.assembled), null);
  at(C.LAUNCH.assembled - 0.001).forEach(p => { close(p.dx, 0, 0.05); close(p.dy, 0, 0.05); });
  // About 2.4 to 2.8 times as far: the cloud stays within 16 cells sideways, so a phone holds it.
  for (let t = 0; t < C.LAUNCH.assembled; t += 1 / 120) at(t).forEach(p => assert.ok(Math.abs(p.dx) < 15.5 && Math.abs(p.dy) < 10.5));
});

test('the eyes: none on the cloud, asleep from the click, then half, then open', () => {
  const eye = t => C.launchFrame(t).pose;
  assert.strictEqual(eye(0.43).eyeH, 0);
  assert.deepStrictEqual([eye(0.44).eyeH, eye(0.44).eyeBottom], [0.35, 2.35]);
  assert.deepStrictEqual([eye(0.539).eyeH, eye(0.539).eyeBottom], [0.35, 2.35]);
  assert.deepStrictEqual([eye(0.54).eyeH, eye(0.54).eyeBottom], [0.5, 2]);
  assert.strictEqual(eye(0.60).eyeH, 1);
  assert.strictEqual(eye(0.78).eyeH, 0.5, 'squeezed in the crouch');
  assert.strictEqual(eye(1.0).eyeH, 1);
  assert.deepStrictEqual([1.301, 1.341, 1.401, 1.441].map(t => eye(t).eyeH), [0.5, 0.15, 0.5, 1], 'the blink after landing');
});

test('the click at 0.44 s: a squash from the feet, settled by 0.70 s', () => {
  isRest({ ...C.launchFrame(0.439).pose, eyeH: 1, pixels: null }, 'no squash before the click');
  const p = C.launchFrame(0.47).pose;
  assert.ok(p.sy < 0.99 && p.sx > 1.005, `squashed: ${p.sx} ${p.sy}`);
  const s = C.launchFrame(0.70).pose;
  assert.strictEqual(s.sy, 1); assert.strictEqual(s.sx, 1);
});

test('the happy hop: 2.4 cells up at its apex, legs tucked and arms lifted, a squash on landing', () => {
  const apex = C.launchFrame((0.82 + 1.12) / 2).pose;
  close(apex.dy, -2.4);
  assert.ok(apex.tucked); assert.strictEqual(apex.armL, 'lift1'); assert.strictEqual(apex.armR, 'lift1');
  assert.ok(C.launchFrame(0.78).pose.sy < 1, 'the crouch');
  assert.ok(C.launchFrame(1.14).pose.sy < 1, 'the landing squash');
  let prev = 0;
  for (let t = 0.82; t < 1.12; t += 1 / 120) { const dy = C.launchFrame(t).pose.dy; assert.ok(Math.abs(dy - prev) < 0.4); prev = dy; }
});

// ---------- 2. The leap ----------

const perchLeap = () => C.makeLeap({
  pose: rest(), feet: { x: 720, y: 60 }, unit: 7, target: { x: 58, y: 850, unit: 4 },
  flight: C.exitFlight(58 - 720), apex: C.exitApex(58 - 720, 850 - 60, 60)
});

test('the long leap into the perch takes the app\'s long hand-off: 0.6 s, a 12 px apex at least', () => {
  assert.strictEqual(C.exitFlight(-662), 0.6);
  assert.strictEqual(C.exitFlight(200), 0.5);
  assert.strictEqual(C.exitApex(-662, 790, 60), 12);
  assert.strictEqual(C.exitApex(400, 10, 400), 77.5);
  assert.strictEqual(C.exitApex(400, 10, 60), 20, 'never closer than 40 px to the top');
});

test('the leap: a crouch, an arc that rises its apex and falls home, a landing squash, and the rest pose', () => {
  const L = perchLeap();
  assert.ok(L.grounded);
  close(L.takeoff, 0.08); close(L.touchdown, 0.68); close(L.end, 1.18);
  const crouch = C.leapFrame(L, 0.07);
  assert.ok(crouch.pose.sy < 0.9 && crouch.pose.sx > 1.05);
  assert.deepStrictEqual(crouch.feet, { x: 720, y: 60 });
  let top = Infinity;
  for (let tau = L.takeoff; tau < L.touchdown; tau += 1 / 240) {
    const f = C.leapFrame(L, tau);
    top = Math.min(top, f.feet.y);
    assert.ok(Math.abs(f.pose.rot) <= 5 + 1e-9);
    assert.ok(f.unit <= 7 + 1e-9 && f.unit >= 4 - 1e-9);
  }
  close(top, 60 - 12, 0.2);
  const land = C.leapFrame(L, L.touchdown + 0.02);
  assert.deepStrictEqual(land.feet, { x: 58, y: 850 });
  assert.strictEqual(land.unit, 4);
  assert.ok(land.pose.sy < 1, 'squash on landing');
  assert.strictEqual(C.leapFrame(L, L.touchdown + 0.2).pose.look, 0);
  assert.strictEqual(C.leapFrame(L, L.touchdown + 0.05).pose.look, -1, 'it looks back where it came from');
  isRest(C.leapFrame(L, L.end).pose, 'landed, it is the grid');
});

test('the leap home follows a target that moves, and lands on it', () => {
  const L = C.makeLeap({ pose: rest(), feet: { x: 58, y: 850 }, unit: 4, target: { x: 720, y: 300, unit: 7 }, flight: 0.6, apex: 12 });
  for (let tau = 0; tau < L.touchdown; tau += 0.05) { L.target.y = 300 - 200 * tau; C.leapFrame(L, tau); }
  L.target.y = 100;
  assert.deepStrictEqual(C.leapFrame(L, L.touchdown + 0.01).feet, { x: 720, y: 100 });
});

test('caught in the air, it keeps its speed when that carries it home naturally, and never crouches', () => {
  const up = C.makeLeap({ pose: { ...rest(), tucked: true }, feet: { x: 300, y: 500 }, unit: 5, vy: -600, target: { x: 58, y: 850, unit: 4 }, flight: 0.5 });
  assert.ok(!up.grounded);
  assert.strictEqual(up.takeoff, 0);
  const b = C.ballistics(up);
  assert.strictEqual(b.vy, -600, 'the arc keeps the speed it had');
  const f = C.leapFrame(up, 0.01);
  assert.ok(f.feet.y < 500, 'still rising at first');
});

// ---------- 2. On its perch: the walk and the idle ----------

test('the walk is the app\'s: contact, one pair lifted with an arm, contact, the other pair', () => {
  isRest(C.walkFrame(0)); isRest(C.walkFrame(2));
  const a = C.walkFrame(1), b = C.walkFrame(3);
  assert.strictEqual(a.raise, 1); assert.strictEqual(b.raise, 1);
  assert.deepStrictEqual(a.lifted, [true, false, true, false]);
  assert.deepStrictEqual(b.lifted, [false, true, false, true]);
  assert.strictEqual(a.armR, 'lift1'); assert.strictEqual(b.armL, 'lift1');
  // Raised, the body is one row up and the planted legs stretch to the ground: no gap, no lost cell.
  const cells = C.poseCells(a);
  assert.ok(cells.some(c => c[0] === 5 && c[1] === 7 && c[3] === 2), 'a planted leg stretches');
  assert.ok(!cells.some(c => c[0] === 2 && c[1] === 10), 'a lifted foot');
  assert.deepStrictEqual([0, 1, 2, 3].map(C.walkShadowInset), [0, 1, 0, 1]);
  assert.strictEqual(C.WALK.frame, 0.12);
  assert.ok(/frameDuration: TimeInterval = 0\.12/.test(swift('Theme.swift')));
});

test('the walk steps with the page: a passing frame at once, then one frame per 9 cells scrolled', () => {
  const u = 4, stride = C.WALK.stride * u;
  assert.strictEqual(stride, 36);
  let w = C.walkAdvance(null, 5, 10, u);
  assert.strictEqual(w.frame, 1, 'the first move shows the passing frame');
  w = C.walkAdvance(w, 20, 10.1, u);
  assert.strictEqual(w.frame, 1, 'less than a stride: the same frame');
  w = C.walkAdvance(w, 16, 10.2, u);
  assert.strictEqual(w.frame, 2, '36 px: the next frame');
  // 0 px holds the frame.
  assert.strictEqual(C.walkAdvance(w, 0, 11, u).frame, 2);
  // A slow read-scroll (240 px/s) walks slowly; a 2400 px/s flick never goes past 12.5 frames a second.
  const run = (speed, secs) => {
    let v = null, t = 0;
    for (; t < secs; t += 1 / 60) v = C.walkAdvance(v, speed / 60, t, u);
    return v.frame - 1;
  };
  const slow = run(240, 1), fast = run(2400, 1);
  assert.ok(slow >= 5 && slow <= 7, `slow: ${slow} frames`);
  assert.ok(fast <= 13 && fast >= 11, `fast: ${fast} frames`);
});

test('the walk never stops mid-step: 150 ms after the page stops, a contact frame, then it stands', () => {
  for (let at = 0; at < 0.3; at += 0.013) {
    const w = { frame: 3, dist: 0, at: 10 + at, last: 10.2 };
    const end = C.walkEnd(w);
    assert.ok(end >= 10.2 + C.WALK.settle - 1e-9 && end >= w.at + C.WALK.minFrame - 1e-9);
    assert.strictEqual(C.walkFrameAt(w, end) % 2, 0, 'a contact frame');
    assert.strictEqual(C.walkFrameAt(w, end - 0.001), 3);
  }
  const contact = { frame: 2, dist: 0, at: 10, last: 10.2 };
  close(C.walkEnd(contact), 10.35);
  assert.strictEqual(C.walkFrameAt(contact, 11), 2);
});

test('while the page scrolls it walks, facing the way the page goes, with no frame loop', () => {
  const s = C.freshState();
  s.walk = C.walkAdvance(null, 10, 10, 4); s.face = 1;
  const f = C.lifeFrame(s, 10.01);
  assert.strictEqual(f.pose.raise, 1);
  assert.strictEqual(f.pose.look, 1);
  s.face = -1;
  assert.strictEqual(C.lifeFrame(s, 10.05).pose.look, -1);
  assert.ok(!C.needsFrames(s, 10.05), 'stepped by the scroll, never by frames');
  close(C.nextChange(s, 10.05), C.walkEnd(s.walk));
});

test('nothing happening, it holds still: no frames, no timer', () => {
  const s = C.freshState();
  isRest(C.lifeFrame(s, 100).pose);
  assert.ok(!C.needsFrames(s, 100));
  assert.strictEqual(C.nextChange(s, 100), Infinity);
});

test('the idle phrase is the app\'s: its die, its intervals, blinks never within 1 s', () => {
  // Dice.unit(7, index, stream), printed by the app's own function in Swift.
  close(C.diceUnit(7, 0, 1), 0.7274877220719126, 1e-15);
  close(C.diceUnit(7, 3, 2), 0.8267851171268455, 1e-15);
  close(C.diceUnit(7, 5, 3), 0.6388070144322578, 1e-15);
  close(C.diceUnit(7, 8, 4), 0.7423151791671696, 1e-15);
  const life = swift('CreatureLife.swift');
  assert.ok(/companion = LifeProfile\(blinkEvery: 3\.4\.\.\.7\.5, glanceEvery: 9\.\.\.16/.test(life));
  assert.deepStrictEqual([C.LIFE.blinkEvery, C.LIFE.glanceEvery], [[3.4, 7.5], [9, 16]]);
  assert.ok(/blinkLength = 0\.14, doubleBlinkGap = 0\.24, blinkApart = 1\.0/.test(life));
  const b = C.blinks(0, 120);
  assert.ok(b.length > 15);
  for (let i = 1; i < b.length; i++) {
    const gap = b[i] - b[i - 1];
    assert.ok(Math.abs(gap - C.LIFE.doubleGap) < 1e-9 || gap >= 1 - 1e-9, `blinks ${gap.toFixed(3)} s apart`);
  }
});

test('once still, one beat of the phrase on the visit\'s clock, never the same beat after every stop', () => {
  // Ten stops 2.6 s apart: each pause plays at most one event, and the next walk cuts what comes later.
  const stops = Array.from({ length: 10 }, (_, k) => 5 + 2.6 * k);
  const played = [], offsets = new Set();
  stops.forEach((stop, k) => {
    const beat = C.idleBeat(stop, { x: 1, down: 0 });
    if (!beat) return;
    assert.ok(beat.at > stop && beat.at <= stop + C.LIFE.window + 1e-9);
    const next = stops[k + 1] === undefined ? Infinity : stops[k + 1] - 0.4;
    beat.blinks.filter(b => b < next).forEach(b => { played.push(b); offsets.add((b - stop).toFixed(3)); });
  });
  assert.ok(played.length >= 2, 'some blinks play: ' + played.length);
  assert.ok(offsets.size >= 2, 'not the same beat after every stop');
  for (let i = 1; i < played.length; i++) {
    const gap = played[i] - played[i - 1];
    assert.ok(Math.abs(gap - C.LIFE.doubleGap) < 1e-9 || gap >= 1 - 1e-9, 'never within 1 s: ' + gap);
  }
});

test('the idle beat: a blink or a glance toward the content, stepped, then it holds still', () => {
  let glance = null, blinkBeat = null;
  for (let t = 0; t < 200 && !(glance && blinkBeat); t += 0.7) {
    const b = C.idleBeat(t, { x: -1, down: 1 });
    if (b && b.look && !glance) glance = b;
    if (b && !b.look && !blinkBeat) blinkBeat = b;
  }
  assert.ok(glance && blinkBeat);
  const s = C.freshState();
  s.idle = glance;
  const mid = C.lifeFrame(s, glance.look.at + glance.look.hold / 2).pose;
  assert.deepStrictEqual([mid.look, mid.lookDown], [-1, 1], 'it looks at the content, below it in the nav bar');
  s.idle = blinkBeat;
  assert.strictEqual(C.lifeFrame(s, blinkBeat.blinks[0] + 0.05).pose.eyeH, 0.2);
  for (let t = blinkBeat.at - 1; t < blinkBeat.at + 2; t += 0.01) assert.ok(!C.needsFrames(s, t), 'stepped: never a frame loop');
  let t = blinkBeat.at - 1, count = 0;
  while ((t = C.nextChange(s, t)) < Infinity) count++;
  assert.ok(count >= 4 && count <= 8, 'a handful of steps: ' + count);
  isRest(C.lifeFrame(s, blinkBeat.at + 1).pose, 'then it holds still');
});

// ---------- 3. Reactions ----------

test('every reaction is short and ends exactly on the rest pose', () => {
  for (const kind of ['hop', 'wave', 'nod', 'wake']) {
    const s = C.freshState();
    s.reaction = { kind, at: 0, look: 0 };
    assert.ok(C.REACT[kind] < 0.8, kind + ' is short');
    for (let t = 0; t < C.REACT[kind]; t += 1 / 240) {
      const p = C.lifeFrame(s, t).pose;
      assert.ok(p.sy > 0.8 && p.sy < 1.2 && p.sx > 0.85 && p.sx < 1.15, `${kind} squash at ${t}`);
      assert.ok(p.dy <= 0 && p.dy >= -C.HOP_HEIGHT - 1e-9, `${kind} height at ${t}`);
      assert.ok([-1, 0, 1].includes(p.look) && [0, 1].includes(p.lookDown));
    }
    isRest(C.lifeFrame(s, C.REACT[kind]).pose, kind + ' ends at rest');
    assert.ok(!C.needsFrames(s, C.REACT[kind]), kind + ' never loops');
  }
});

test('the reactions are the app\'s: its durations, and the companion\'s hop height', () => {
  const life = swift('CreatureLife.swift');
  assert.ok(/case \.memorySaved: return 0\.74/.test(life) && C.REACT.hop === 0.74);
  assert.ok(/case \.accountOpened: return 0\.62/.test(life) && C.REACT.wave === 0.62);
  assert.ok(/case \.doze: return 0\.70/.test(life) && C.REACT.doze === 0.70);
  assert.ok(/case \.wake: return 0\.46/.test(life) && C.REACT.wake === 0.46);
  assert.ok(/static let companion = LifeProfile\([^)]*hopHeight: 1\.75\)/.test(life) && C.HOP_HEIGHT === 1.75);
});

test('each part of the page brings out its own reaction', () => {
  assert.deepStrictEqual(C.REACTIONS, {
    accounts: 'wave', flow: 'hop', graph: 'look', usage: 'look', ram: 'look', safety: 'nod', footer: 'doze', click: 'wave'
  });
  // The finale is a place it leaps into, not a reaction: one creature answers the Download button.
  const js = read('companion.js');
  assert.ok(!/'#download \.actions'|dlBtn/.test(js));
});

test('memory saved: four sparkles in the air, cream and light, inside the reach of the canvas', () => {
  const s = C.freshState();
  s.reaction = { kind: 'hop', at: 0, look: 1 };
  let n = 0;
  for (let t = 0; t < C.REACT.hop; t += 1 / 240) {
    const p = C.lifeFrame(s, t).pose;
    assert.strictEqual(p.look, 1, 'the hop toward the button keeps its eyes on it');
    p.sprites.forEach(sp => { n++; assert.ok(sp.x > -4 && sp.x < 20 && sp.y > -7 && sp.y < 12); });
  }
  assert.ok(n > 100);
  // On the half-cell grid, like the Z.
  const p = C.lifeFrame(s, 0.4).pose;
  p.sprites.forEach(sp => { assert.strictEqual(sp.x * 2, Math.round(sp.x * 2)); assert.strictEqual(sp.y * 2, Math.round(sp.y * 2)); });
});

test('the wave: a little hop and the right arm swinging up and down, eyes smiling', () => {
  const s = C.freshState();
  s.reaction = { kind: 'wave', at: 0 };
  const arms = new Set();
  for (let t = 0; t < C.REACT.wave; t += 0.01) arms.add(C.lifeFrame(s, t).pose.armR);
  assert.deepStrictEqual([...arms].sort(), ['lift1', 'rest', 'up']);
  assert.strictEqual(C.lifeFrame(s, 0.3).pose.eyeH, 0.5);
  assert.ok(C.lifeFrame(s, 0.1).pose.dy < -1);
});

test('the footer: it dozes off, one Z floats up and fades, then it holds still asleep', () => {
  const s = C.freshState();
  s.reaction = { kind: 'doze', at: 0 };
  s.asleep = { at: C.REACT.doze };
  assert.strictEqual(C.lifeFrame(s, 0.3).pose.eyeH, 0.5);
  const asleep = C.lifeFrame(s, 1.5).pose;
  assert.deepStrictEqual([asleep.eyeH, asleep.eyeBottom], [0.35, 2.35]);
  assert.strictEqual(asleep.sprites.length, 1);
  assert.deepStrictEqual(asleep.sprites[0].pattern, C.ZEE);
  assert.ok(!C.needsFrames(s, 1.5), 'the Z is stepped: timers, not frames');
  assert.ok(C.Z_STEPS.length >= 8 && C.Z_STEPS.length <= 24, 'about a dozen steps: ' + C.Z_STEPS.length);
  // It moves in whole half cells and fades in four steps: it never shimmers between pixels.
  for (let a = 0; a < C.Z.life; a += 0.01) {
    const z = C.sleepZ(a);
    assert.strictEqual(z.x * 2, Math.round(z.x * 2)); assert.strictEqual(z.y * 2, Math.round(z.y * 2));
    assert.ok([0, 0.18, 0.36, 0.54, 0.72].some(o => Math.abs(o - z.opacity) < 1e-9), 'opacity ' + z.opacity);
  }
  const late = C.REACT.doze + C.Z.born + C.Z.life + 0.01;
  assert.strictEqual(C.lifeFrame(s, late).pose.sprites.length, 0);
  assert.ok(!C.needsFrames(s, late));
  assert.strictEqual(C.nextChange(s, late), Infinity);
});

test('a look at a section: the eyes on it for 1.2 s, a blink as they come back, then still', () => {
  const s = C.freshState();
  s.glance = { at: 0, look: -1 };
  assert.strictEqual(C.lifeFrame(s, 0.5).pose.look, -1);
  assert.strictEqual(C.lifeFrame(s, 1.22).pose.eyeH, 0.2);
  isRest(C.lifeFrame(s, 1.4).pose);
  assert.ok(!C.needsFrames(s, 0.5));
  assert.strictEqual(C.nextChange(s, 1.4), Infinity);
});

test('an interrupted reaction blends from where the first left the body, no jump', () => {
  const s = C.freshState();
  s.prev = { kind: 'hop', at: 0 };
  s.reaction = { kind: 'wave', at: 0.25 };
  const before = C.lifeFrame({ ...C.freshState(), reaction: s.prev }, 0.2499).pose;
  const after = C.lifeFrame(s, 0.2501).pose;
  close(after.dy, before.dy, 0.1);
});

// ---------- 3. How it works, on the diagram's own clock ----------

test('How it works: the diagram\'s creature catches each note; the companion hops once, after the story', () => {
  assert.strictEqual(C.FLOW.beat, M.STORY.beat);
  assert.strictEqual(C.FLOW.end, M.STORY.end);
  C.flowLandings().forEach((at, b) => {
    const src = M.STORY.order[b], box = M.memoryOf(src, 'shared');
    const has = t => M.storyFrame(t, 'shared').slots[box].some(sl => sl.acc === src);
    assert.ok(!has(at - 0.01) && has(at + 0.01), 'beat ' + b + ' lands at ' + at);
  });
  const hops = C.storyHops(100);
  assert.ok(hops.length <= 1);
  hops.forEach(h => assert.ok(h >= 100 + C.FLOW.end, 'no hop before the story ends'));
  assert.ok(C.flowLandings().every(at => at < C.FLOW.end));
});

test('the eyes follow the travelling note from where the creature stands', () => {
  assert.strictEqual(C.followLook(100, 54, 4), 1);
  assert.strictEqual(C.followLook(54, 54, 4), 0);
  assert.strictEqual(C.followLook(-100, 400, 4), -1);
  // At 1440 the perch's feet are near x = 54 and the note travels from 384 to 731: always to its right.
  for (let x = 384; x <= 731; x += 10) assert.strictEqual(C.followLook(x, 54, 4), 1);
});

test('the gaze moves one whole cell, never up', () => {
  assert.deepStrictEqual(C.gaze(-500, 0, 7), { x: -1, y: 0 });
  assert.deepStrictEqual(C.gaze(500, 300, 7), { x: 1, y: 1 });
  assert.deepStrictEqual(C.gaze(20, -400, 7), { x: 0, y: 0 });
});

test('the perch, the hero and the finale give the creature\'s feet', () => {
  assert.deepStrictEqual(C.perchFeet({ left: 22, top: 800, width: 64 }), { x: 54, y: 844, unit: 4 });
  assert.deepStrictEqual(C.heroFeet({ left: 664, top: 100, width: 112 }), { x: 720, y: 198, unit: 7 });
  // The finale's box: 20 by 18 cells, from 2 left of the grid and 6 above it (index.html).
  assert.ok(read('index.html').includes('class="creature cv cv-finale" viewBox="-2 -6 20 18"'));
  assert.deepStrictEqual(C.slotFeet({ left: 650, top: 500, width: 140 }, C.FINALE_VB), { x: 720, y: 619, unit: 7 });
  assert.ok(C.overlaps({ left: 0, right: 10, top: 0, bottom: 10 }, { left: 9, right: 20, top: 9, bottom: 20 }));
  assert.ok(!C.overlaps({ left: 0, right: 10, top: 0, bottom: 10 }, { left: 10, right: 20, top: 0, bottom: 10 }));
});

// ---------- The page ----------

test('the page loads the companion from its own files, after the page\'s script', () => {
  const html = read('index.html');
  assert.ok(/<link rel="stylesheet" href="companion\.css">/.test(html));
  const s = html.indexOf('<script src="script.js" defer>'), c = html.indexOf('<script src="companion.js" defer>');
  assert.ok(s > 0 && c > s, 'companion.js runs after script.js, which tells it the diagram\'s clock');
  assert.ok(/new CustomEvent\('flowstate'/.test(read('script.js')));
});

test('the companion keeps to the site\'s rules', () => {
  const js = read('companion.js'), css = read('companion.css');
  for (const s of [js, css]) { assert.ok(!s.includes('\u2014') && !s.includes('\u2013'), 'no em or en dash'); }
  assert.ok(!/https?:\/\//.test(js.replace(/'http:\/\/www\.w3\.org\/2000\/svg'/, '')), 'no other origin');
  assert.ok(/setAttribute\('aria-hidden', 'true'\)/.test(js), 'the companion is hidden from assistive tech');
  assert.ok(!/tabindex|\.focus\(/.test(js), 'it never takes the focus');
  assert.ok(!/setAttribute\('style'/.test(js), 'no style attribute (the CSP)');
  // Every scroll and pointer listener is passive; the frame loop only runs while something moves.
  const re = /addEventListener\('(scroll|pointermove|resize)'/g;
  let m, n = 0;
  while ((m = re.exec(js))) {
    const after = js.slice(m.index + 17), next = after.search(/addEventListener\(/);
    assert.ok(/passive: true/.test(next < 0 ? after : after.slice(0, next)), m[1] + ' listener is passive');
    n++;
  }
  assert.ok(n >= 3);
  // Keyframes move by transform and opacity only.
  (css.match(/@keyframes[^{]+\{((?:[^{}]*\{[^{}]*\})*)[^{}]*\}/g) || []).forEach(k => {
    (k.match(/\{([^{}]*)\}/g) || []).forEach(b => b.slice(1, -1).split(';').map(d => d.trim()).filter(Boolean).forEach(d => {
      assert.ok(/^(opacity|transform)\s*:/.test(d), 'animates ' + d);
    }));
  });
  // Reduce Motion: the script stops before any motion, and the failsafe and wordmark only apply with motion allowed.
  assert.ok(/if \(!motion\) return;/.test(js));
  assert.ok(/@media \(scripting: enabled\) and \(prefers-reduced-motion: no-preference\)/.test(css));
});

// ---------- Where it perches, and when it moves ----------

test('it perches beside the column only where the gutter holds it; else in the nav bar, between the brand and the links', () => {
  assert.strictEqual(C.perchMode(1920, 4), 'corner');
  assert.strictEqual(C.perchMode(1440, 4), 'corner');
  assert.strictEqual(C.perchMode(1296, 4), 'corner');
  for (const w of [1280, 1024, 768, 390]) assert.strictEqual(C.perchMode(w, 4), 'nav', 'at ' + w);
  // The free space of the bar (measured): 148 to 226 at 390, 172 to 325 at 768; the bar is 52 px.
  const phone = C.navPerch(148, 226, 52);
  assert.deepStrictEqual(phone, { x: 187, y: 46, unit: 3 });
  assert.ok(phone.x - 8 * 3 >= 148 + 8 && phone.x + 8 * 3 <= 226 - 8, 'clear of the brand and of GitHub');
  assert.ok(phone.y - 11 * 3 >= 0 && phone.y + 3 <= 52, 'inside the bar, shadow included');
  assert.strictEqual(C.navPerch(148, 196, 52).unit, 2, 'tight: 2 px cells');
  assert.strictEqual(C.navPerch(148, 170, 52), null, 'no room: no perch');
});

test('text or a button between the old sample rows still counts: a perch never covers a line', () => {
  // The perch at 1024 x 768, and the footer's License link that the 5 by 3 samples missed (between rows 696, 726, 756).
  const box = { left: 938 - 6, right: 938 + 64 + 6, top: 702 - 6, bottom: 702 + 44 + 6 };
  assert.ok(C.coverage(box, [{ left: 947, right: 988, top: 730, bottom: 745 }]));
  // A 12 px line between two rows: seen.
  assert.ok(C.coverage(box, [{ left: 900, right: 1100, top: 710, bottom: 722 }]));
  assert.ok(!C.coverage(box, [{ left: 900, right: 1100, top: 760, bottom: 772 }]));
  assert.ok(!C.coverage(box, [{ left: 950, right: 950, top: 700, bottom: 740 }]), 'an empty rect is nothing');
});

// A reader's scroll, and the companion's decisions on it (C.plan), with a 0.6 s flight. Returns the leaps it took.
function simulate(scrollAt, secs, heroGoneAt = 61) {
  let where = 'home', slot = 'hero', flight = null, landedAt = -Infinity, lastScroll = -Infinity, y = 0;
  const leaps = [];
  for (let t = 0; t < secs; t += 1 / 60) {
    const ny = scrollAt(t);
    if (ny !== y) lastScroll = t;
    y = ny;
    if (flight && t >= flight.t0 + 0.6) { landedAt = flight.t0 + 0.6; where = flight.dest === 'perch' ? 'perched' : 'home'; slot = flight.dest === 'perch' ? slot : flight.dest; flight = null; }
    const p = C.plan({
      where: flight ? 'flying' : where, slot, dest: flight && flight.dest, from: flight && flight.from, landed: false,
      heroGone: y > heroGoneAt, finaleIn: false, finaleGone: true, scrollY: y, sinceScroll: t - lastScroll,
      sinceLanding: t - landedAt, mode: 'nav'
    });
    if (p.act) { leaps.push({ t, to: p.act }); flight = { dest: p.act, from: flight ? null : where === 'home' ? slot : 'perch', t0: t }; }
  }
  return leaps;
}

test('a page nudged up and down at the top never sets it flying back and forth', () => {
  // Three nudges of 90 px down and back up, 0.5 s apart (a trackpad reader looking at the screenshot).
  const nudges = t => { const k = t % 1.1; return t < 3.3 && k >= 0.05 && k < 0.55 ? 90 : 0; };
  const leaps = simulate(nudges, 4.5);
  assert.ok(leaps.filter(l => l.to === 'perch').length === 1, JSON.stringify(leaps));
  assert.ok(leaps.filter(l => l.to === 'hero').length <= 1, JSON.stringify(leaps));
  // A steady up-and-down, never resting at the top: it leaves once and waits on its perch.
  const wave = t => Math.round(45 - 45 * Math.cos(2 * Math.PI * t / 1.2));
  assert.deepStrictEqual(simulate(wave, 4.5).map(l => l.to), ['perch']);
});

test('back at the top and still, it comes home once; it leaves only 1.2 s after landing', () => {
  const read = t => (t < 0.1 ? 0 : t < 3 ? 600 : 0);
  const leaps = simulate(read, 6);
  assert.deepStrictEqual(leaps.map(l => l.to), ['perch', 'hero']);
  assert.ok(leaps[1].t >= 3 + C.DWELL.still - 1e-9, 'it waits for the page to be still');
  assert.ok(C.shouldLeave({ gone: true, sinceLanding: 1.3 }) && !C.shouldLeave({ gone: true, sinceLanding: 1.1 }));
  assert.ok(C.shouldGoHome({ scrollY: 0, sinceScroll: 0.3, sinceLanding: 2 }));
  assert.ok(!C.shouldGoHome({ scrollY: 10, sinceScroll: 3, sinceLanding: 9 }), 'only at the very top');
  assert.ok(!C.shouldGoHome({ scrollY: 0, sinceScroll: 0.1, sinceLanding: 9 }), 'only once still');
});

test('the finale is its place too: it leaps in when the finale is in view, and out when it has gone', () => {
  const base = { where: 'perched', slot: 'hero', heroGone: true, finaleIn: true, finaleGone: false, scrollY: 9000, sinceScroll: 0, sinceLanding: 5, mode: 'nav' };
  assert.strictEqual(C.plan(base).act, 'finale');
  assert.strictEqual(C.plan({ ...base, sinceLanding: 0.5 }).act, null);
  close(C.plan({ ...base, sinceLanding: 0.5 }).wait, 0.7);
  assert.strictEqual(C.plan({ ...base, where: 'home', slot: 'finale', finaleIn: false, finaleGone: true }).act, 'perch');
  assert.strictEqual(C.plan({ ...base, where: 'home', slot: 'finale' }).act, null, 'it stays while the finale is on screen');
  // No room for a perch: it only goes between the hero and the finale.
  assert.strictEqual(C.plan({ ...base, where: 'home', slot: 'hero', mode: 'none' }).act, 'finale');
  assert.strictEqual(C.plan({ ...base, where: 'home', slot: 'hero', finaleIn: false, mode: 'none' }).act, null);
});

test('a leap out of the hero never goes under the nav or off the screen', () => {
  // From the hero's feet toward the nav perch at 390: a short hop up into the bar, the head always on screen.
  const from = { x: 195, y: 137 }, to = { x: 187, y: 46, unit: 3 }, ceiling = 11 * 5 + 2;
  const apex = C.exitApex(to.x - from.x, to.y - from.y, Math.min(from.y, to.y), ceiling);
  assert.strictEqual(apex, 4);
  for (const vy of [0, -300, -900, -1500]) {
    const L = C.makeLeap({ pose: rest(), feet: from, unit: 5, vy, target: to, flight: 0.5, apex, ceiling });
    assert.strictEqual(L.takeoff, vy ? 0 : C.LEAP.anticipation, 'carried by the page, no crouch');
    for (let tau = 0; tau <= L.touchdown; tau += 1 / 240) {
      const f = C.leapFrame(L, tau);
      assert.ok(f.feet.y - 11 * f.unit >= -1, `head on screen at ${tau.toFixed(3)} (vy ${vy}): ${f.feet.y}`);
    }
  }
});

test('the launch\'s cloud of pixels stays clear of the nav at every width', () => {
  const css = read('styles.css');
  const num = re => parseFloat(re.exec(css)[1]);
  const nav = num(/\.nav \{[^}]*height: (\d+)px/);
  const wide = { pad: num(/\.hero \{ padding-top: (\d+)px/), margin: num(/\.hero \.creature \{\s*margin: (-?\d+)px/), unit: 112 / 16 };
  const narrow = { pad: num(/@media \(max-width: 734px\)[\s\S]*?\.hero \{ padding-top: (\d+)px/),
    margin: num(/\.hero \.creature \{ width: 80px; height: 75px; margin: (-?\d+)px/), unit: 80 / 16 };
  let top = 0;
  for (let t = 0; t < C.LAUNCH.assembled; t += 1 / 240) {
    C.pixelStates(t).forEach((p, i) => { if (p.o > 0.05) top = Math.min(top, C.PIXELS[i].y + p.dy); });
  }
  for (const w of [wide, narrow]) {
    const head = nav + w.pad + w.margin + 3 * w.unit;
    assert.ok(head + top * w.unit >= nav, `the cloud's top at ${(head + top * w.unit).toFixed(1)} px, the nav ends at ${nav}`);
  }
});

test('the finale waits for the companion, and assembles by itself only without one', () => {
  const js = read('script.js');
  for (const ev of ['cm-arrive', 'cm-depart', 'cm-assemble', 'cm-still']) assert.ok(js.includes(`'${ev}'`), ev);
  assert.ok(/hasAttribute\('data-cm'\)/.test(js));
  const cm = read('companion.js');
  assert.ok(/setAttribute\('data-cm', ''\)/.test(cm));
  for (const ev of ['cm-arrive', 'cm-depart', 'cm-assemble', 'cm-still']) assert.ok(cm.includes(`'${ev}'`), ev);
});

test('Reduce Motion switched on mid-visit: every observer and timer stops, the hero creature is back, still', () => {
  const js = read('companion.js');
  const still = /function still\(\) \{([\s\S]*?)\n  \}/.exec(js)[1];
  assert.ok(/observers\.forEach\(function \(io\) \{ io\.disconnect\(\); \}\)/.test(still));
  assert.ok(/classList\.remove\('is-away'\)/.test(still));
  for (const name of ['leapTo', 'reactTo', 'decide']) assert.ok(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]{0,80}off`).test(js), name + ' checks off');
  const dock = read('dock.js');
  assert.ok(/motionQuery\.addEventListener\('change'/.test(dock), 'the Dock stops too');
});
