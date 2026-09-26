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

test('the walk starts on a passing frame and stops on a contact frame, never mid-step', () => {
  assert.strictEqual(C.walkIndex(5, 5), 1);
  for (let end = 5; end < 6; end += 0.013) {
    const stop = C.walkStop(5, end);
    assert.ok(stop >= end - 1e-9 && stop - end <= 0.24 + 1e-9);
    assert.strictEqual(C.walkIndex(stop, 5) % 2, 0, 'a contact frame');
  }
});

test('while the page scrolls it walks, facing the way the page goes', () => {
  const s = C.freshState();
  s.walk = { start: 10, end: null }; s.face = 1;
  const f = C.lifeFrame(s, 10.01);
  assert.strictEqual(f.pose.raise, 1);
  assert.strictEqual(f.pose.look, 1);
  s.face = -1;
  assert.strictEqual(C.lifeFrame(s, 10.13).pose.look, -1);
  assert.ok(C.needsFrames(s, 10.5));
  s.walk.end = 10.5;
  const stop = C.walkStop(10, 10.5);
  assert.ok(!C.needsFrames(s, stop));
});

test('nothing happening, it holds still: no frames, no timer', () => {
  const s = C.freshState();
  isRest(C.lifeFrame(s, 100).pose);
  assert.ok(!C.needsFrames(s, 100));
  assert.strictEqual(C.nextChange(s, 100), Infinity);
});

test('once still, a short idle: a blink, a glance at the content beside it, a blink, then nothing', () => {
  const s = C.freshState();
  s.idle = { at: 0, side: 1 };
  assert.strictEqual(C.lifeFrame(s, 1.32).pose.eyeH, 0.5);
  assert.strictEqual(C.lifeFrame(s, 1.36).pose.eyeH, 0.2);
  assert.strictEqual(C.lifeFrame(s, 3.5).pose.look, 1);
  assert.strictEqual(C.lifeFrame(s, 4.11).pose.eyeH, 0.2, 'a blink as the eyes come back');
  isRest(C.lifeFrame(s, C.IDLE.end).pose);
  for (let t = 0; t < 6; t += 0.01) assert.ok(!C.needsFrames(s, t), 'stepped: never a frame loop');
  let t = 0, count = 0;
  while ((t = C.nextChange(s, t)) < Infinity) count++;
  assert.ok(count >= 8 && count <= 12, 'a handful of steps: ' + count);
  assert.strictEqual(C.nextChange(s, C.IDLE.end), Infinity, 'then it holds still');
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
    accounts: 'wave', flow: 'hop', graph: 'look', usage: 'look', ram: 'look', safety: 'nod', download: 'hop', footer: 'doze', click: 'wave'
  });
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
  assert.ok(C.needsFrames(s, 1.5));
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

test('the hops land with the diagram\'s notes: each beat\'s note reaches its memory 1 s in', () => {
  assert.strictEqual(C.FLOW.beat, M.STORY.beat);
  assert.strictEqual(C.FLOW.end, M.STORY.end);
  C.flowLandings().forEach((at, b) => {
    const src = M.STORY.order[b], box = M.memoryOf(src, 'shared');
    const has = t => M.storyFrame(t, 'shared').slots[box].some(sl => sl.acc === src);
    assert.ok(!has(at - 0.01) && has(at + 0.01), 'beat ' + b + ' lands at ' + at);
  });
});

test('the eyes follow the travelling note: left, middle, right of the screen', () => {
  assert.strictEqual(C.followLook(100, 1440), -1);
  assert.strictEqual(C.followLook(720, 1440), 0);
  assert.strictEqual(C.followLook(1200, 1440), 1);
});

test('the gaze moves one whole cell, never up', () => {
  assert.deepStrictEqual(C.gaze(-500, 0, 7), { x: -1, y: 0 });
  assert.deepStrictEqual(C.gaze(500, 300, 7), { x: 1, y: 1 });
  assert.deepStrictEqual(C.gaze(20, -400, 7), { x: 0, y: 0 });
});

test('the perch and the hero give the creature\'s feet', () => {
  assert.deepStrictEqual(C.perchFeet({ left: 22, top: 800, width: 64 }), { x: 54, y: 844, unit: 4 });
  assert.deepStrictEqual(C.heroFeet({ left: 664, top: 100, width: 112 }), { x: 720, y: 198, unit: 7 });
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
