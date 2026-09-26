// The website's Dock: the pure functions of site/dock.js (magnification, the launch bounce, the spring, who gets a dot)
// and the markup and styles they rely on.
// Run from the repository root: node --test Tests/site/dock.test.cjs
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const SITE = path.join(__dirname, '..', '..', 'site');
const read = name => fs.readFileSync(path.join(SITE, name), 'utf8');
const D = require(path.join(SITE, 'dock.js'));
const close = (a, b, e = 1e-6) => assert.ok(Math.abs(a - b) <= e, `${a} != ${b}`);

const S = 64;                                   // icon size
const W = [S, S * 0.34, S, S, S, S];            // Brainmerge, the separator, then the four accounts
const center = i => W.slice(0, i).reduce((a, b) => a + b, 0) + W[i] / 2;
const total = W.reduce((a, b) => a + b, 0);

// ---------- The magnification curve ----------

test('the falloff is 1 under the pointer, 0 from RANGE icons away, smooth and even', () => {
  close(D.falloff(0), 1);
  close(D.falloff(1), 0);
  close(D.falloff(1.5), 0);
  close(D.falloff(0.5), 0.5);
  close(D.falloff(-0.3), D.falloff(0.3));
  for (let u = 0; u < 1; u += 0.01) assert.ok(D.falloff(u + 0.01) <= D.falloff(u) + 1e-12);
  // No corner at either end: the slope is flat at 0 and at 1.
  assert.ok(Math.abs(D.falloff(0.001) - 1) < 1e-4);
  assert.ok(D.falloff(0.999) < 1e-4);
});

test('Apple-like values: at most 1.6 times, over about 2.5 icons each side', () => {
  assert.strictEqual(D.MAX, 1.6);
  assert.strictEqual(D.RANGE, 2.5);
});

test('at rest, or with no pointer, nothing moves', () => {
  for (const [x, amp] of [[null, 1], [center(3), 0]]) {
    const m = D.magnify(W, x, amp, { size: S });
    assert.deepStrictEqual(m.scale, W.map(() => 1));
    assert.deepStrictEqual(m.dx, W.map(() => 0));
    assert.strictEqual(m.left, 0); assert.strictEqual(m.right, 0);
  }
});

test('the icon under the pointer grows to the most, its neighbours less and less', () => {
  const m = D.magnify(W, center(3), 1, { size: S });
  close(m.scale[3], D.MAX);
  assert.ok(m.scale[2] < m.scale[3] && m.scale[4] < m.scale[3]);
  close(m.scale[2], m.scale[4]);                 // one icon away on either side
  assert.ok(m.scale[5] < m.scale[4] && m.scale[5] >= 1);
  close(m.scale[4], 1 + 0.6 * D.falloff(1 / 2.5));
  close(m.scale[5], 1 + 0.6 * D.falloff(2 / 2.5));
});

test('the point under the pointer stays under it, and the bar widens on both sides', () => {
  for (let x = 0; x <= total; x += 3) {
    const m = D.magnify(W, x, 1, { size: S });
    assert.ok(m.left <= 1e-9 && m.right >= -1e-9, `ends at ${x}`);
    // Rebuild the grown row: its slot under the pointer covers the pointer at the same fraction.
    const grown = W.map((w, i) => w * m.scale[i]);
    const i = D.slotAt(grown, x - m.left);
    if (x < total) {
      assert.ok(i >= 0, `slot at ${x}`);
      const startRest = W.slice(0, i).reduce((a, b) => a + b, 0);
      const startGrown = m.left + grown.slice(0, i).reduce((a, b) => a + b, 0);
      close((x - startRest) / W[i], (x - startGrown) / grown[i], 1e-9);
    }
    // Growth is all accounted for: the ends moved by what grew.
    close(m.right - m.left, grown.reduce((a, b) => a + b, 0) - total, 1e-9);
  }
});

test('neighbours spread apart: centers keep their order and never overlap', () => {
  for (let x = 0; x <= total; x += 5) {
    const m = D.magnify(W, x, 1, { size: S });
    const c = W.map((w, i) => center(i) + m.dx[i]);
    for (let i = 1; i < W.length; i++) {
      const gap = c[i] - c[i - 1] - (W[i] * m.scale[i] + W[i - 1] * m.scale[i - 1]) / 2;
      close(gap, 0, 1e-9);
    }
  }
});

test('moving the pointer moves everything continuously (no jump between icons)', () => {
  let prev = D.magnify(W, 0, 1, { size: S });
  for (let x = 0.5; x <= total; x += 0.5) {
    const m = D.magnify(W, x, 1, { size: S });
    for (let i = 0; i < W.length; i++) assert.ok(Math.abs(m.dx[i] - prev.dx[i]) < 1.5, `jump at ${x} for ${i}`);
    prev = m;
  }
});

test('amp scales the magnification smoothly, and room caps the widening', () => {
  const half = D.magnify(W, center(3), 0.5, { size: S });
  close(half.scale[3], 1 + 0.6 * 0.5);
  const free = D.magnify(W, center(3), 1, { size: S });
  const capped = D.magnify(W, center(3), 1, { size: S, room: 20 });
  const grow = m => W.reduce((a, w, i) => a + w * (m.scale[i] - 1), 0);
  assert.ok(grow(free) > 20);
  close(grow(capped), 20, 1e-9);
  const none = D.magnify(W, center(3), 1, { size: S, room: 0 });
  assert.deepStrictEqual(none.scale, W.map(() => 1));
});

// ---------- The launch bounce ----------

test('the bounce is a Mac\'s: the same hop again while the app opens, never losing height, landing at rest', () => {
  assert.strictEqual(D.bounce(0), 0);
  assert.strictEqual(D.bounce(-1), 0);
  assert.strictEqual(D.bounce(D.BOUNCE), 0);
  assert.strictEqual(D.bounce(D.BOUNCE + 1), 0);
  assert.ok(D.HOPS.length >= 2);
  close(D.BOUNCE, D.HOPS.length * D.HOP_TIME);
  D.HOPS.forEach((h, i) => {
    const t0 = i * D.HOP_TIME;
    assert.strictEqual(h, D.HOPS[0], 'every hop the same height');
    close(D.bounce(t0 + D.HOP_TIME / 2), h);                // apex halfway through the hop
    close(D.bounce(t0 + D.HOP_TIME * 0.25), h * 0.75);      // a parabola: gravity
    assert.ok(D.bounce(t0 + 1e-6) < 1e-3, 'each hop starts from the ground');
  });
  assert.ok(D.BOUNCE > 0.8 && D.BOUNCE < 1, `bounce lasts ${D.BOUNCE}`);
  for (let t = 0; t < D.BOUNCE; t += 0.005) assert.ok(D.bounce(t) >= 0 && D.bounce(t) <= D.HOPS[0] + 1e-12);
});

// ---------- The spring behind the magnification's arrival and return ----------

test('the spring reaches its target without overshoot when critically damped', () => {
  let x = 0, v = 0, max = 0;
  for (let i = 0; i < 120; i++) { [x, v] = D.springStep(x, v, 1, 1 / 60, 0.2, 1); max = Math.max(max, x); }
  assert.ok(max <= 1 + 1e-6);
  assert.ok(D.settled(x, v, 1));
  // A long frame (a busy tab) stays stable.
  [x, v] = D.springStep(0, 0, 1, 0.05, 0.2, 1);
  assert.ok(x > 0 && x < 1);
});

// ---------- Who bounces, who gets a dot ----------

test('an open app only comes forward; a closed one bounces; the primary hands over to Claude without a dot', () => {
  assert.deepStrictEqual(D.launch({ running: true }), { bounce: false, dot: true });
  assert.deepStrictEqual(D.launch({ running: false }), { bounce: true, dot: true });
  assert.deepStrictEqual(D.launch({ running: false, opener: true }), { bounce: true, dot: false });
});

// ---------- Markup and styles ----------

test('the Dock: Brainmerge, a separator, then the four account apps; Brainmerge and Studio open', () => {
  const html = read('index.html');
  const dock = html.slice(html.indexOf('<div class="mac">'), html.indexOf('<p class="dock-path">'));
  const names = [...dock.matchAll(/data-name="([^"]+)"/g)].map(m => m[1]);
  assert.deepStrictEqual(names, ['Brainmerge', 'Personal', 'Studio', 'Work', 'Client']);
  const running = [...dock.matchAll(/<button[^>]*data-name="([^"]+)"[^>]*data-running/g)].map(m => m[1]);
  assert.deepStrictEqual(running, ['Brainmerge', 'Studio']);
  assert.match(dock, /data-name="Personal" data-opener/);
  // The group says what the Dock is; each app's own label says whether it is open (dock.js keeps it true).
  assert.match(dock, /aria-label="A Mac Dock: [^"]*Choose an app to open it\."/);
  assert.doesNotMatch(dock, /are open\./);
  assert.match(read('dock.js'), /setAttribute\('aria-label', name\(el\) \+ \(on \? ', open' : ''\)\)/);
  // Each icon picks its file from the size it is laid out at, not the largest magnified size.
  assert.match(dock, /sizes="calc\(1\.6 \* clamp\(52px, 4vw \+ 20px, 80px\)\)"/);
  assert.ok(html.includes('<code>~/Applications/Brainmerge</code>'));
  for (const acc of ['personal', 'studio', 'work', 'client']) {
    for (const px of [256, 512]) {
      assert.ok(dock.includes(`assets/dock/${acc}-${px}.webp`));
      assert.ok(fs.existsSync(path.join(SITE, 'assets', 'dock', `${acc}-${px}.webp`)));
    }
  }
  assert.ok(html.includes('<link rel="stylesheet" href="dock.css">'));
  assert.ok(html.includes('<script src="dock.js" defer></script>'));
  assert.doesNotMatch(dock, /style="|on[a-z]+="/);      // the CSP: no inline styles or handlers
});

test('the Dock is one Tab stop, the arrow keys go from app to app', () => {
  const js = read('dock.js');
  assert.match(js, /setAttribute\('role', 'toolbar'\)/);
  assert.match(js, /tabIndex = k === current \? 0 : -1/);
  for (const key of ['ArrowRight', 'ArrowLeft', 'Home', 'End']) assert.ok(js.includes(`'${key}'`), key);
});

test('the first account says it opens Claude, and has no dot of its own', () => {
  const js = read('dock.js');
  assert.ok(js.includes("' \\u00b7 opens Claude'"));
  assert.doesNotMatch(js, /[\u2013\u2014]/);
});

test('the Dock keeps to transforms and opacity, and Reduce Motion keeps it still', () => {
  const css = read('dock.css');
  assert.doesNotMatch(css, /transition:\s*all|transition:[^;]*(width|height|left|top|margin)/);
  assert.match(css, /\.mdock\.is-moving/);
  const js = read('dock.js');
  assert.match(js, /prefers-reduced-motion: no-preference/);
  assert.match(js, /passive: true/);
  assert.doesNotMatch(js, /\.style\.(width|height|left|top|margin)/);
});
