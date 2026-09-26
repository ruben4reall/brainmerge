// Generates the two "How it works" SVG compositions (wide and tall) of site/index.html from one geometry table.
// Every coordinate is in SVG user units. Never edit the diagram in index.html by hand: change this file, then run
//   python3 scripts/site-flow/inject-flow.py
// which puts the output of `node scripts/site-flow/gen-flow.cjs` back into the page. Tests/site checks they agree.
// The app's accounts in the app's colors (Theme.color(for: .orange, .pink, .blue)); site/script.js has the same TINT.
const TINT = { p: '#D97757', s: '#D97A8E', w: '#6FA3D8' };
const NAME = { p: 'Personal', s: 'Studio', w: 'Work' };
const INITIAL = { p: 'P', s: 'S', w: 'W' };
// Top to bottom (wide) or left to right (tall): Work stays at the edge, next to its own box in "One each".
const ORDER = ['p', 's', 'w'];

const creature = (cls, x, y, unit) => `
      <g class="fl-creature ${cls}" transform="translate(${x} ${y}) scale(${unit})">
        <g class="fl-cr-sprite">
          <path class="fl-cr-legs" d="M2 8h1v3H2zM5 8h1v3H5zM10 8h1v3h-1zM13 8h1v3h-1z" fill="#A06BE0"/>
          <path d="M2 0h12v8H2z" fill="#A06BE0"/>
          <g class="fl-cr-arms"><path d="M0 3h2v3H0zM14 3h2v3h-2z" fill="#A06BE0"/></g>
          <g class="fl-cr-eyes" fill="#1E1430"><rect x="4" y="1" width="1" height="1"/><rect x="11" y="1" width="1" height="1"/></g>
        </g>
      </g>`;

// A cubic from a to b; `dir` says whether the lane leaves horizontally (wide) or vertically (tall).
function lane(a, b, dir) {
  if (dir === 'h') {
    const mx = (a[0] + b[0]) / 2;
    return `M${a[0]} ${a[1]}C${mx} ${a[1]} ${mx} ${b[1]} ${b[0]} ${b[1]}`;
  }
  if (dir === 'vh') { // down, then into a side
    return `M${a[0]} ${a[1]}C${a[0]} ${b[1]} ${a[0]} ${b[1]} ${b[0]} ${b[1]}`;
  }
  const my = (a[1] + b[1]) / 2;
  return `M${a[0]} ${a[1]}C${a[0]} ${my} ${b[0]} ${my} ${b[0]} ${b[1]}`;
}

function box(cls, g) {
  const bars = g.bars.map((y, i) => `
        <g class="fl-slot" data-slot="${i}" transform="translate(${g.barX} ${y})">
          <rect class="fl-bar-tint" width="${g.barW}" height="4" rx="2" fill="#F4EFE6" opacity="0"/>
          <rect class="fl-bar-cream" width="${g.barW}" height="4" rx="2" fill="#F4EFE6" opacity="0"/>
        </g>`).join('');
  return `
      <rect x="${g.x}" y="${g.y}" width="${g.w}" height="${g.h}" rx="16" fill="#A06BE0" fill-opacity="0.18" stroke="#A06BE0" stroke-width="1.5"/>
      <rect class="fl-flash" x="${g.x}" y="${g.y}" width="${g.w}" height="${g.h}" rx="16" fill="none" stroke="#B487EA" stroke-width="3" opacity="0"/>
      <text class="fl-box-title" x="${g.cx}" y="${g.titleY}" text-anchor="middle">${g.title}</text>
      <text class="fl-box-path" x="${g.cx}" y="${g.pathY}" text-anchor="middle">${g.path}</text>${bars}`;
}

function orb(k, o, labelPos) {
  const [x, y] = o;
  const label = labelPos === 'left'
    ? `<text class="fl-name" x="${x - 36}" y="${y + 5}" text-anchor="end">${NAME[k]}</text>`
    : `<text class="fl-name" x="${x}" y="${y + 46}" text-anchor="middle">${NAME[k]}</text>`;
  return `
      <g class="fl-account" data-acc="${k}">
        <g class="fl-orb" transform="translate(${x} ${y})">
          <circle r="22" fill="${TINT[k]}"/>
          <text class="fl-initial" y="6.5" text-anchor="middle">${INITIAL[k]}</text>
          <g transform="translate(16 16)"><circle r="10" fill="#1A1918" stroke="#FFFFFF" stroke-opacity="0.12"/><text class="fl-cc" y="3" text-anchor="middle">&gt;_</text></g>
        </g>
        <g class="fl-ring" transform="translate(${x} ${y})" opacity="0"><circle r="22" fill="none" stroke="${TINT[k]}" stroke-width="1.5" vector-effect="non-scaling-stroke"/></g>
        ${label}
      </g>`;
}

// A note is a page, 14 by 17, as the app draws it: its top right corner cut, the fold filling the triangle below the cut.
const PAGE = 'M-4.5 -8.5H3L7 -4.5V6A2.5 2.5 0 0 1 4.5 8.5H-4.5A2.5 2.5 0 0 1 -7 6V-6A2.5 2.5 0 0 1 -4.5 -8.5z';

function svg(c) {
  const lanes = mode => ORDER.map(k => {
    const d = lane(c.orbPort[k], c.ports[mode][k], c.dir[mode][k]);
    return `<path class="fl-lane" data-acc="${k}" data-mode="${mode}" d="${d}" fill="none" stroke="#F4EFE6" stroke-opacity="0.22" stroke-width="1.5"/>` +
      `<path class="fl-lit" data-acc="${k}" data-mode="${mode}" d="${d}" fill="none" stroke="#F4EFE6" stroke-opacity="0.6" stroke-width="2" opacity="0"/>`;
  }).join('\n      ');
  const note = k => `<g class="fl-note" data-acc="${k}" opacity="0"><path d="${PAGE}" fill="${TINT[k]}"/><path class="fl-fold" d="M3 -8.5V-4.5H7z" fill="#000" fill-opacity="0.25"/><rect x="-4" y="-4" width="8" height="1.5" rx="0.75" fill="#F4EFE6" fill-opacity="0.55"/><rect x="-4" y="-0.5" width="6" height="1.5" rx="0.75" fill="#F4EFE6" fill-opacity="0.55"/></g>`;
  return `<svg class="flow ${c.cls}" viewBox="${c.vx} 0 ${c.W} ${c.H}" role="img" aria-labelledby="${c.id}-t">
      <title id="${c.id}-t">Personal, Work and Studio, each with its own Claude Code. One account saves a note to the memory, a folder on this Mac, and the other accounts read the same note.</title>
      <rect class="fl-frame" x="${c.vx + 6}" y="6" width="${c.W - 12}" height="${c.H - 12}" rx="20" fill="none" stroke="#FFFFFF" stroke-opacity="0.12"/>
      <text class="fl-frame-label" x="${c.vx + 26}" y="34">On this Mac</text>
      <g class="fl-lanes" data-mode="shared">
      ${lanes('shared')}
      </g>
      <g class="fl-lanes" data-mode="each">
      ${lanes('each')}
      </g>
      <g class="fl-box fl-box-shared" data-box="shared">${box('', c.shared)}${creature('', c.creature[0], c.creature[1], c.unit)}
      </g>
      <g class="fl-box fl-box-work" data-box="work">${box('', c.work)}
      </g>${ORDER.map(k => orb(k, c.orbs[k], c.labelPos)).join('')}
      <g class="fl-notes">
        ${[0, 1, 2].map(i => `<g class="fl-note-slot" data-note="${i}" opacity="0">${ORDER.map(note).join('')}</g>`).join('\n        ')}
      </g>
    </svg>`;
}

// Wide: accounts on the left, the memory on the right.
const wide = {
  cls: 'flow-wide', id: 'flow-wide', vx: 60, W: 640, H: 330, dir: { shared: { p: 'h', s: 'h', w: 'h' }, each: { p: 'h', s: 'h', w: 'h' } },
  labelPos: 'left', unit: 4,
  orbs: { p: [190, 95], s: [190, 170], w: [190, 245] },
  orbPort: { p: [212, 95], s: [212, 170], w: [212, 245] },
  ports: {
    shared: { p: [470, 140], s: [470, 160], w: [470, 180] },
    each: { p: [470, 102], s: [470, 122], w: [470, 262] },
  },
  shared: { x: 470, y: 110, w: 170, h: 100, cx: 555, titleY: 139, pathY: 159, title: 'Memory', path: '~/Brain', barX: 505, barW: 100, bars: [174, 184, 194] },
  work: { x: 470, y: 222, w: 170, h: 80, cx: 555, titleY: 249, pathY: 268, title: 'Work memory', path: '~/Brain-work', barX: 505, barW: 100, bars: [282] },
  creature: [523, 66],
};
// Tall: accounts in a row on top, the memory below.
const tall = {
  cls: 'flow-tall', id: 'flow-tall', vx: 0, W: 360, H: 410, dir: { shared: { p: 'v', s: 'v', w: 'v' }, each: { p: 'v', s: 'v', w: 'v' } },
  labelPos: 'below', unit: 4,
  orbs: { p: [70, 82], s: [180, 82], w: [290, 82] },
  orbPort: { p: [70, 140], s: [180, 140], w: [290, 140] },
  ports: {
    shared: { p: [112, 270], s: [150, 270], w: [262, 270] },
    each: { p: [62, 270], s: [100, 270], w: [290, 282] },
  },
  shared: { x: 95, y: 270, w: 170, h: 100, cx: 180, titleY: 299, pathY: 319, title: 'Memory', path: '~/Brain', barX: 130, barW: 100, bars: [334, 344, 354] },
  work: { x: 228, y: 282, w: 120, h: 80, cx: 288, titleY: 308, pathY: 326, title: 'Work memory', path: '~/Brain-work', barX: 253, barW: 70, bars: [342] },
  creature: [164, 226],
};
// In the tall layout the shared box's creature stands between the Studio lane and the Work lane.
tall.creature = [168, 226];
function render() { return svg(wide) + '\n' + svg(tall); }

module.exports = { TINT, NAME, INITIAL, ORDER, render };
if (require.main === module) console.log(render());
