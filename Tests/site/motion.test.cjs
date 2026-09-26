// The website's motion: the pure functions of site/script.js, the hero creature's CSS and the How it works diagram.
// Run from the repository root: node --test Tests/site/motion.test.cjs
// It lives outside site/ so Vercel never serves it.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const SITE = path.join(__dirname, '..', '..', 'site');
const read = name => fs.readFileSync(path.join(SITE, name), 'utf8');
global.location = { hostname: 'localhost' }; // the analytics block only runs on the live host
const M = require(path.join(SITE, 'script.js'));
const Flow = require(path.join(__dirname, '..', '..', 'scripts', 'site-flow', 'gen-flow.cjs'));
const close = (a, b, e = 1e-3) => assert.ok(Math.abs(a - b) <= e, `${a} != ${b}`);

// ---------- The story's pure functions ----------

test('easings start at 0, end at 1, and match the CSS curves', () => {
  for (const f of [M.easeOut, M.easeMove]) { close(f(0), 0); close(f(1), 1); }
  close(M.easeMove(0.5), 0.596, 2e-3);         // cubic-bezier(0.77, 0, 0.175, 1) at x = 0.5
  for (let x = 0; x < 1; x += 0.01) assert.ok(M.easeMove(x + 0.01) >= M.easeMove(x) - 1e-9);
  assert.ok(M.easeOut(0.2) > 0.6);             // strong ease-out: most of the way early
  const lin = M.cubicBezier(0, 0, 1, 1); close(lin(0.37), 0.37);
});

test('spring starts displaced and settles', () => {
  close(M.spring(0, 0.28, 0.55), 1);
  assert.ok(Math.abs(M.spring(1, 0.28, 0.55)) < 0.01);
  assert.ok(M.spring(0.2, 0.28, 0.55) < 0);    // underdamped: it overshoots once
});

test('the accounts are the app\'s: Personal, Studio and Work in their app tints', () => {
  assert.deepStrictEqual(M.ACCOUNTS, ['p', 's', 'w']);
  assert.deepStrictEqual(M.TINT, { p: '#D97757', s: '#D97A8E', w: '#6FA3D8' }); // Theme.color(for: .orange, .pink, .blue)
  assert.deepStrictEqual(Flow.TINT, M.TINT);
  assert.deepStrictEqual(Flow.NAME, { p: 'Personal', s: 'Studio', w: 'Work' });
  assert.deepStrictEqual(Flow.ORDER, ['p', 's', 'w']); // Work at the edge, next to its own box in "One each"
});

test('the story plays in the app\'s beat order: Personal, then Work, then Studio', () => {
  assert.deepStrictEqual(M.STORY.order, ['p', 'w', 's']);
});

test('who reads a note: everyone else in shared, nobody for Work in each', () => {
  assert.deepStrictEqual(M.readers('w', 'shared'), ['p', 's']);
  assert.deepStrictEqual(M.readers('w', 'each'), []);
  assert.deepStrictEqual(M.readers('p', 'each'), ['s']);
  assert.strictEqual(M.memoryOf('w', 'each'), 'work');
});

test('before the story, nothing moves and the memory is empty', () => {
  const f = M.storyFrame(-1, 'shared');
  assert.strictEqual(f.notes.length, 0);
  assert.strictEqual(f.slots.shared.length, 0);
  assert.deepStrictEqual(f.creature, { look: null, armsUp: false, sx: 1, sy: 1 });
});

test('the end frame is still: three settled notes, no chip, no ring, creature at rest', () => {
  for (const mode of ['shared', 'each']) {
    const f = M.storyFrame(M.STORY.end, mode);
    assert.strictEqual(f.notes.length, 0);
    const all = f.slots.shared.concat(f.slots.work);
    assert.strictEqual(all.length, 3);
    all.forEach(s => { close(s.grow, 1); close(s.cream, 1); });
    assert.deepStrictEqual(Object.values(f.rings), [null, null, null]);
    assert.deepStrictEqual(Object.values(f.lit), [0, 0, 0]);
    assert.deepStrictEqual(Object.values(f.litBy), [null, null, null]);
    assert.deepStrictEqual(f.creature, { look: null, armsUp: false, sx: 1, sy: 1 });
  }
  assert.strictEqual(M.storyFrame(M.STORY.end, 'each').slots.work.length, 1);
});

test('the hero still in One memory: Personal\'s note landed, its copies on their way to Studio and Work', () => {
  const f = M.storyFrame(M.STORY.hero.shared, 'shared');
  assert.deepStrictEqual(f.slots.shared.map(s => s.acc), ['p']);
  const out = f.notes.filter(n => n.dir === 'out');
  assert.deepStrictEqual(out.map(n => n.lane).sort(), ['s', 'w']);
  out.forEach(n => {
    assert.strictEqual(n.acc, 'p');
    assert.ok(n.p > 0.15 && n.p < 0.85, 'copy mid-way: ' + n.p);
    close(n.opacity, 1); // a page, never see-through: its lit lane would show through it
  });
});

test('the hero still in One each: Work\'s note landed in Work memory, nothing leaves it', () => {
  const f = M.storyFrame(M.STORY.hero.each, 'each');
  assert.strictEqual(f.notes.filter(n => n.dir === 'out').length, 0);
  assert.deepStrictEqual(f.slots.work.map(s => s.acc), ['w']);
  assert.deepStrictEqual(f.slots.shared.map(s => s.acc), ['p']);
});

test('lanes light in the writer\'s tint', () => {
  for (let t = -0.5; t <= M.STORY.end + 0.5; t += 0.01) {
    for (const mode of ['shared', 'each']) {
      const f = M.storyFrame(t, mode);
      const writer = t >= 0 ? M.STORY.order[Math.floor(t / M.STORY.beat)] : undefined;
      for (const a of M.ACCOUNTS) {
        if (f.lit[a] > 0) assert.strictEqual(f.litBy[a], writer, `t=${t.toFixed(2)} ${mode} lane ${a}`);
        else assert.strictEqual(f.litBy[a], null, `t=${t.toFixed(2)} ${mode} lane ${a} is dark`);
      }
    }
  }
  const hero = M.storyFrame(M.STORY.hero.shared, 'shared');
  assert.ok(hero.lit.s > 0 && hero.lit.w > 0);
  assert.strictEqual(hero.litBy.s, 'p');
  assert.strictEqual(hero.litBy.w, 'p');
});

test('a reader\'s ring never runs into its name', () => {
  // Names end 36 units left of the orb's center (wide) or start 35 units below it (tall); the orb's radius is 22.
  let widest = 0;
  for (let t = 0; t <= M.STORY.end; t += 0.005) {
    for (const mode of ['shared', 'each']) {
      Object.values(M.storyFrame(t, mode).rings).forEach(r => { if (r) widest = Math.max(widest, r.scale); });
    }
  }
  assert.ok(widest > 1.3, 'the ring still grows: ' + widest);
  assert.ok(22 * widest + 0.75 <= 34, 'widest ring ' + (22 * widest + 0.75).toFixed(1));
});

test('frames are deterministic and bounded', () => {
  for (let t = -0.5; t <= M.STORY.end + 0.5; t += 0.01) {
    for (const mode of ['shared', 'each']) {
      const a = M.storyFrame(t, mode), b = M.storyFrame(t, mode);
      assert.deepStrictEqual(a, b);
      assert.ok(a.notes.length <= 3, 'at most three notes at once, t=' + t);
      a.notes.forEach(n => { assert.ok(n.opacity >= 0 && n.opacity <= 1); assert.ok(n.p >= 0 && n.p <= 1); });
      Object.values(a.lit).forEach(v => assert.ok(v >= 0 && v <= 1));
      assert.ok(a.creature.sy <= 1.03 && a.creature.sy >= 0.89);
    }
  }
});

test('a note never travels to an account outside its memory', () => {
  for (let t = 0; t < M.STORY.end; t += 0.02) {
    M.storyFrame(t, 'each').notes.forEach(n => {
      assert.strictEqual(M.memoryOf(n.lane, 'each'), M.memoryOf(n.acc, 'each'));
    });
  }
});

test('eyes move one cell at most', () => {
  assert.deepStrictEqual(M.lookAt(-200, 10), { x: -1, y: 0 });
  assert.deepStrictEqual(M.lookAt(0, -150), { x: 0, y: 0 });   // never up: row 0 would notch the silhouette
  assert.deepStrictEqual(M.lookAt(-90, 150), { x: -1, y: 1 });
  assert.deepStrictEqual(M.lookAt(5, 5), { x: 0, y: 0 });
});

test('the hop starts and ends at rest, with offsets in order', () => {
  for (const k of ['body', 'arms', 'shadow']) {
    const fr = M.HOP[k];
    assert.strictEqual(fr[0].offset, 0); assert.strictEqual(fr[fr.length - 1].offset, 1);
    assert.strictEqual(fr[fr.length - 1].transform, 'none');
    for (let i = 1; i < fr.length; i++) assert.ok(fr[i].offset >= fr[i - 1].offset);
  }
  assert.strictEqual(M.HOP.shadow[M.HOP.shadow.length - 1].opacity, 0);
});

// ---------- The pages ----------

test('no text on the site uses an em dash or an en dash', () => {
  for (const name of ['index.html', '404.html', 'script.js']) {
    const s = read(name);
    assert.ok(!s.includes('—'), name + ' has an em dash');
    assert.ok(!s.includes('–'), name + ' has an en dash');
  }
});

// Every `animation` on the hero creature, as { name, duration, delay, iterations } in ms.
function heroAnimations(css) {
  const ms = v => (v.endsWith('ms') ? parseFloat(v) : parseFloat(v) * 1000);
  const out = [];
  const rule = /([^{}]+)\{([^{}]*)\}/g;
  let m;
  while ((m = rule.exec(css))) {
    const selector = m[1].trim();
    if (!/\.hero \.creature/.test(selector)) continue;
    const decl = /(?:^|;)\s*animation\s*:\s*([^;]+)/.exec(m[2]);
    if (!decl) continue;
    const parts = decl[1].trim().replace(/cubic-bezier\([^)]*\)/g, 'curve').split(/\s+/);
    const times = parts.filter(p => /^[\d.]+m?s$/.test(p)).map(ms);
    const count = parts.find(p => /^(\d+(\.\d+)?|infinite)$/.test(p));
    out.push({
      selector, name: parts[0], duration: times[0], delay: times[1] || 0,
      iterations: count === undefined ? 1 : count === 'infinite' ? Infinity : Number(count)
    });
  }
  return out;
}

test('the hero creature is still within 5 s of loading', () => {
  const anims = heroAnimations(read('styles.css'));
  assert.ok(anims.length >= 7, 'the wake-up and the idle are found: ' + anims.length);
  for (const a of anims) {
    const end = a.delay + a.duration * a.iterations;
    assert.ok(end <= 5000, `${a.selector} (${a.name}) ends at ${end} ms`);
  }
});

test('the hero creature never breathes by scale', () => {
  const css = read('styles.css');
  assert.ok(!/cr-breathe/.test(css), 'the scale breath is gone');
  // Whatever plays after the wake-up (it ends at 2.28 s) moves in whole cells or by opacity only.
  for (const a of heroAnimations(css).filter(x => x.delay >= 2280)) {
    const frames = new RegExp('@keyframes\\s+' + a.name + '\\s*\\{((?:[^{}]*\\{[^{}]*\\})*)[^{}]*\\}').exec(css);
    assert.ok(frames, 'keyframes for ' + a.name);
    assert.ok(!/scale/.test(frames[1]), a.name + ' scales the creature');
  }
});

test('the 404 page shows the same version as the home page', () => {
  const version = /Version&nbsp;(\d+\.\d+\.\d+)/;
  const home = version.exec(read('index.html'));
  const lost = version.exec(read('404.html'));
  assert.ok(home && lost);
  assert.strictEqual(lost[1], home[1]);
});

// ---------- The How it works diagram ----------

function flowBlock() {
  const html = read('index.html');
  const start = html.indexOf('<div class="flow-stage">\n') + '<div class="flow-stage">\n'.length;
  const end = html.indexOf('          </div>\n          <div class="flow-bar">');
  assert.ok(start > 30 && end > start, 'the diagram block is found');
  return html.slice(start, end);
}

test('the diagram on the page is the generated one, never edited by hand', () => {
  const generated = Flow.render().split('\n').map(l => (l.trim() ? '        ' + l : l)).join('\n') + '\n';
  assert.strictEqual(flowBlock(), generated);
});

test('the diagram names Personal, Work and Studio, and never Client', () => {
  const block = flowBlock();
  for (const name of ['Personal', 'Work', 'Studio']) assert.ok(block.includes('>' + name + '<'), name);
  assert.ok(!/Client/.test(block));
  assert.ok(!/data-acc="c"/.test(block));
});

test('every note in the diagram is a page with a folded corner', () => {
  const notes = flowBlock().match(/<g class="fl-note" [^>]*>.*?<\/g>/g);
  assert.strictEqual(notes.length, 2 * 3 * 3); // two layouts, three chip slots, one chip per account
  notes.forEach(n => {
    assert.ok(n.includes('class="fl-fold"'), n);
    // As the app draws it: the page's top right corner is cut, and the fold fills the triangle below the cut.
    assert.ok(/<path d="M-4\.5 -8\.5H3L7 -4\.5V6[^"]*z" fill="#[0-9A-F]{6}"\/>/.test(n), 'cut corner: ' + n);
    assert.ok(n.includes('<path class="fl-fold" d="M3 -8.5V-4.5H7z" fill="#000" fill-opacity="0.25"/>'), 'fold: ' + n);
  });
});

// ---------- The page, painting the diagram ----------

// A stand-in for the page, just enough for script.js to find the diagram and paint it: every element remembers the
// attributes written to it. Reduce Motion is on, so the page paints the still once and waits for the toggle.
function fakePage() {
  const made = {};
  function el(key, attrs = {}) {
    const node = {
      key, attrs: { transform: 'translate(10 20) scale(2)', ...attrs }, listeners: {}, hidden: false, textContent: '',
      classList: { add() {}, remove() {}, contains() { return false; } },
      getAttribute(n) { return n in this.attrs ? this.attrs[n] : null; },
      setAttribute(n, v) { this.attrs[n] = String(v); },
      addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); },
      getTotalLength() { return 100; },
      getPointAtLength(d) { return { x: d, y: 0 }; },
      querySelector(sel) { const k = key + ' ' + sel; return made[k] || (made[k] = el(k)); },
      querySelectorAll(sel) {
        if (sel === '.fl-slot') return [0, 1, 2].map(i => this.querySelector(sel + i));
        if (sel === '.fl-note-slot') return [0, 1, 2].map(i => this.querySelector(sel + i));
        if (sel === '.fl-note') return ['p', 's', 'w'].map(a => { const n = this.querySelector(sel + a); n.attrs['data-acc'] = a; return n; });
        return [];
      },
    };
    return node;
  }
  const svg = el('svg');
  const opts = ['shared', 'each'].map(m => el('opt-' + m, { 'data-mode': m }));
  const fig = el('fig', { 'data-mode': 'shared' });
  fig.querySelectorAll = sel => (sel === 'svg.flow' ? [svg] : sel === '.flow-opt' ? opts : []);
  fig.querySelector = sel => (sel === '.flow-play' ? el('play') : null);
  const document = {
    documentElement: el('html'),
    addEventListener() {},
    querySelector() { return null; },
    querySelectorAll(sel) { return sel === '.flow-fig' ? [fig] : []; },
  };
  const window = { matchMedia: () => ({ matches: false }) };
  const sandbox = { window, document, location: { hostname: 'localhost' }, navigator: {}, performance, requestAnimationFrame() {},
    cancelAnimationFrame() {}, setTimeout, console };
  require('node:vm').runInNewContext(read('script.js'), sandbox);
  return { lit: (mode, acc) => made[`svg .fl-lit[data-mode="${mode}"][data-acc="${acc}"]`], opts };
}

test('a lit lane glows in the tint of the account whose note travels it', () => {
  // The still of "One memory": Personal's note has landed, its copies climb the Studio and Work lanes.
  const page = fakePage();
  for (const acc of ['s', 'w']) {
    const lane = page.lit('shared', acc);
    assert.strictEqual(lane.getAttribute('stroke'), M.TINT.p, acc);   // Personal's orange, not the lane's own account
    assert.strictEqual(lane.getAttribute('stroke-opacity'), '0.85', acc);
    assert.strictEqual(lane.getAttribute('opacity'), '1', acc);
  }
  // Personal's own lane is not lit: no tint is written to it.
  assert.strictEqual(page.lit('shared', 'p').getAttribute('stroke'), null);
  assert.strictEqual(page.lit('shared', 'p').getAttribute('opacity'), '0');
});
