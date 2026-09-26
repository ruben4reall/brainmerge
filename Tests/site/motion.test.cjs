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

// The motion tokens of :root (--t-page: 320ms...), so a rule written with them reads as its values.
function tokens(css) {
  const root = /:root\s*\{([^}]*)\}/.exec(css)[1];
  const out = {};
  root.replace(/(--[\w-]+)\s*:\s*([^;]+);/g, (_, k, v) => { out[k] = v.trim(); });
  return out;
}
function resolve(value, vars) {
  return value.replace(/var\((--[\w-]+)(?:,\s*([^)]*))?\)/g, (_, k, fallback) => (k in vars ? vars[k] : fallback || ''));
}

// Every `animation` on the hero creature, as { name, duration, delay, iterations } in ms.
function heroAnimations(css) {
  const ms = v => (v.endsWith('ms') ? parseFloat(v) : parseFloat(v) * 1000);
  const vars = tokens(css);
  const out = [];
  const rule = /([^{}]+)\{([^{}]*)\}/g;
  let m;
  while ((m = rule.exec(css))) {
    const selector = m[1].trim();
    if (!/\.hero \.creature/.test(selector)) continue;
    const decl = /(?:^|;)\s*animation\s*:\s*([^;]+)/.exec(m[2]);
    if (!decl) continue;
    const parts = resolve(decl[1], vars).trim().replace(/(cubic-bezier|linear)\([^)]*\)/g, 'curve').split(/\s+/);
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

// ---------- The creature drawn from poses (finale, All set) ----------

test('the page\'s grid is the app\'s grid, and the rest pose is exactly it', () => {
  const swift = fs.readFileSync(path.join(__dirname, '..', '..', 'Packages', 'BrainmergeUI', 'Sources', 'BrainmergeUI', 'Design', 'CreatureView.swift'), 'utf8');
  const rows = swift.match(/"[X.]{16}"/g).map(r => r.slice(1, -1));
  assert.deepStrictEqual(M.GRID, rows);
  const rest = M.poseCells(M.restPose()).map(c => c.join(',')).sort();
  assert.deepStrictEqual(rest, M.bodyPixels().map(p => p.x + ',' + p.y).sort());
});

test('every still creature on the page is drawn from the rest pose', () => {
  const d = M.cellsPath(M.poseCells(M.restPose()));
  const paths = read('index.html').match(/class="cv-cells" d="[^"]*"/g);
  assert.ok(paths.length >= 2, 'the finale and All set creatures');
  paths.forEach(p => assert.strictEqual(p, `class="cv-cells" d="${d}"`));
});

test('the launch gather ends on the rest grid, eyes open, and never jumps', () => {
  const A = M.ASSEMBLE;
  const end = M.assembleFrame(A.end).pose;
  assert.deepStrictEqual({ ...end, sprites: [] }, M.restPose());
  let prev = null;
  for (let t = 0; t <= A.end + 0.01; t += 1 / 120) {
    const f = M.assembleFrame(t), p = f.pose;
    for (const k of ['sx', 'sy', 'dy', 'eyeH']) assert.ok(Number.isFinite(p[k]), k + ' at ' + t);
    if (t >= A.clickAt) assert.ok(p.eyeH > 0, 'never eyeless once whole, t=' + t.toFixed(3));
    if (t >= A.assembled) assert.strictEqual(p.pixels, null);
    else assert.strictEqual(p.pixels.length, 120);
    // About 2.4 to 3 times as far as home: the cloud stays within 16 cells of the body sideways (112 px), so a phone holds it.
    if (p.pixels) p.pixels.forEach(px => assert.ok(Math.abs(px.dx) < 15.5 && Math.abs(px.dy) < 10.5));
    assert.ok(p.sy > 0.8 && p.sy < 1.2 && p.sx > 0.85 && p.sx < 1.15, 'squash in range at ' + t);
    if (prev) assert.ok(Math.abs(p.dy - prev.dy) < 0.4, 'the hop moves under half a cell per 120 Hz frame');
    prev = p;
  }
  // Just before every pixel is home, they are home already: the swap to one path is invisible.
  M.assembleFrame(A.assembled - 0.001).pose.pixels.forEach(px => { close(px.dx, 0, 0.05); close(px.dy, 0, 0.05); });
});

test('memory saved: a hop with sparkles that ends exactly at rest, inside the drawing', () => {
  const H = M.ALLSET.hopHeight;
  assert.deepStrictEqual(M.savedFrame(M.SAVED.duration, H), M.restPose());
  assert.deepStrictEqual(M.savedFrame(0, H).armL, 'rest');
  let sparkles = 0;
  for (let t = 0; t < M.SAVED.duration; t += 1 / 240) {
    const p = M.savedFrame(t, H);
    assert.ok(['rest', 'lift1', 'up'].includes(p.armL) && p.armL === p.armR);
    assert.ok(p.dy <= 0 && p.dy >= -H - 1e-9);
    p.sprites.forEach(s => {
      sparkles++;
      // The viewBox is -2 -6 20 18: sparkles never leave it.
      assert.ok(s.x > -2 && s.x < 18 && s.y > -6 && s.y < 12, `sparkle at ${s.x},${s.y}`);
      assert.ok(s.opacity >= 0 && s.opacity <= 1);
    });
  }
  assert.ok(sparkles > 50, 'the sparkles show');
  const late = M.savedFrame(M.SAVED.duration - 0.001, H);
  close(late.sx, 1, 0.01); close(late.sy, 1, 0.01);
});

test('the hero creature\'s gaze moves one whole cell, never up', () => {
  assert.deepStrictEqual(M.gaze(-500, 0, 7), { x: -1, y: 0 });
  assert.deepStrictEqual(M.gaze(500, 300, 7), { x: 1, y: 1 });
  assert.deepStrictEqual(M.gaze(20, -400, 7), { x: 0, y: 0 });
  for (let dx = -600; dx <= 600; dx += 37) for (let dy = -600; dy <= 600; dy += 41) {
    const g = M.gaze(dx, dy, 5);
    assert.ok([-1, 0, 1].includes(g.x) && [0, 1].includes(g.y));
  }
});

// ---------- The feature scenes ----------

test('the quick opener scene lists what the app would: the name first, then the note', () => {
  const html = read('index.html');
  const names = cls => (html.match(new RegExp(`<ul class="qo-rows ${cls}">(.*?)</ul>`))[1].match(/<span class="qo-nm">(\w+)/g) || []).map(s => s.replace('<span class="qo-nm">', ''));
  assert.deepStrictEqual(names('qo-all'), M.DEMO.map(r => r.name));
  assert.deepStrictEqual(names('qo-found'), M.openerFilter(M.DEMO, 'wo').map(r => r.name));
  assert.deepStrictEqual(M.openerFilter(M.DEMO, 'w').map(r => r.name), ['Work', 'Client']); // Client by its note
  assert.deepStrictEqual(M.openerFilter(M.DEMO, 'stu').map(r => r.name), ['Studio']);
  assert.deepStrictEqual(M.openerFilter(M.DEMO, 'studio').map(r => r.name), ['Studio']);
  assert.deepStrictEqual(M.openerFilter(M.DEMO, '').length, 4);
});

test('every scene plays in order, once, within three seconds, and every beat is styled', () => {
  const css = read('styles.css'), html = read('index.html');
  const onPage = [...html.matchAll(/data-scene="(\w+)"/g)].map(m => m[1]).sort();
  assert.deepStrictEqual(onPage, Object.keys(M.SCENES).sort());
  for (const [name, beats] of Object.entries(M.SCENES)) {
    for (let i = 1; i < beats.length; i++) assert.ok(beats[i][0] > beats[i - 1][0], name + ' beats in order');
    assert.ok(beats[beats.length - 1][0] <= 3000, name + ' ends by 3 s');
    beats.forEach(([, b]) => assert.ok(new RegExp(`\\.scene-${name}[^{,]*\\.${b}\\b`).test(css), `${name} ${b} is styled`));
  }
});

test('All set keeps the app\'s beat: checks 60 ms apart from 0.4 s, the hop after the last', () => {
  const css = read('styles.css');
  const delays = [...css.matchAll(/\.scene-allset\.b-in \.as-checks (?:li:nth-child\((\d)\) )?\.as-ok \{[^}]*animation-delay: (\d+)ms/g)]
    .map(m => [Number(m[1] || 1), Number(m[2])]);
  assert.strictEqual(delays.length, 6);
  delays.forEach(([n, ms]) => assert.strictEqual(ms, 400 + 60 * (n - 1)));
  close(M.ALLSET.hop, 0.91);
  assert.ok(M.ALLSET.hop * 1000 > 700 + 120, 'the creature hops once the last check is in');
});

test('the pop curve in styles.css is the app\'s pop spring', () => {
  const css = read('styles.css');
  const pts = /--ease-pop: linear\(([^)]*)\)/.exec(css)[1].split(',').map(Number);
  assert.strictEqual(pts.length, 21);
  pts.forEach((v, i) => close(v, i === 20 ? 1 : M.springValue(i * 0.03, 0.35, 0.6), 0.002));
});

test('blocks arriving together rise in reading order, never more than 300 ms apart', () => {
  assert.deepStrictEqual(M.batchDelays(3, 0), [0, 60, 120]);
  assert.deepStrictEqual(M.batchDelays(9, 500).slice(-2), [800, 800]);
});

test('the pages hold no inline style or script: the CSP forbids them', () => {
  for (const name of ['index.html', '404.html']) {
    const s = read(name);
    assert.ok(!/\sstyle=/.test(s), name + ' has a style attribute');
    assert.ok(!/<style/.test(s), name + ' has a style element');
    assert.ok(!/<script(?![^>]*\ssrc=)/.test(s), name + ' has an inline script');
    assert.ok(!/\son[a-z]+=/.test(s), name + ' has an inline handler');
  }
});

test('the illustrations\' numbers add up', () => {
  const css = read('styles.css');
  const scale = cls => Number(new RegExp(`\\.${cls} \\{[^}]*scaleX\\(([\\d.]+)\\)`).exec(css)[1]);
  // RAM of a 16 GB Mac: Personal 1.9, Studio 1.2, a terminal session 0.6, other apps 7.5 (11.2 in all, 70%).
  close(scale('seg-p'), 1.9 / 16); close(scale('seg-s'), 3.1 / 16); close(scale('seg-t'), 3.7 / 16); close(scale('seg-o'), 11.2 / 16);
  const html = read('index.html');
  assert.ok(html.includes('RAM: 11.2 GB of 16 GB used (70%)'));
  assert.ok(html.includes('Claude uses 3.7 GB of RAM, 23%. Your accounts take 4.4 GB on&nbsp;disk.'));
  close(Number(/\.lim-a \.bar i \{ transform: scaleX\(([\d.]+)\)/.exec(css)[1]), 0.17);
  close(Number(/\.lim-b \.bar i \{ transform: scaleX\(([\d.]+)\)/.exec(css)[1]), 0.42);
});
