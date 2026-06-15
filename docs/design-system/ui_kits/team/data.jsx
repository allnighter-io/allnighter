// @ds-adherence-ignore -- UI-kit data + a Glyph helper. Window globals.
const R = window.React;

// The founder's real six-worker panel (MVP README §0).
window.AL_WORKERS = [
  { id: 'opus',     name: 'Opus 4.8',     model: 'via claude-code', brand: 'anthropic',    color: 'FFA630', synth: true },
  { id: 'gpt',      name: 'ChatGPT 5.5',  model: 'via codex-cli',   icon: 'terminal' },
  { id: 'sonnet',   name: 'Sonnet 4.6',   model: 'via claude-code', brand: 'anthropic',    color: 'AEB5C9' },
  { id: 'composer', name: 'Composer 2.5', model: 'via cursor',      icon: 'square' },
  { id: 'gemini',   name: 'Gemini Flash', model: 'via gemini-cli',  brand: 'googlegemini', color: 'E1E5F0' },
  { id: 'grok',     name: 'Grok Build',   model: 'via grok-cli',    brand: 'x',            color: 'E1E5F0' },
];

window.AL_PROMPT = 'Give me three different directions for making this dashboard feel premium.';

// Per-worker simulated run timing + token counts (ms to done).
window.AL_RUN = {
  opus:     { ms: 4200, tok: '2,140' },
  gpt:      { ms: 2600, tok: '1,512' },
  sonnet:   { ms: 3100, tok: '1,884' },
  composer: { ms: 2200, tok: '1,043' },
  gemini:   { ms: 1500, tok: '842',   fail: false },
  grok:     { ms: 2900, tok: '—', fail: true },
};

window.AL_PLAN = {
  consensus: [
    'Lead with typography and spacing, not color — premium reads as restraint.',
    'Replace flat fills with one accent + a calm neutral scale; kill gradient noise.',
    'Add depth through hairline borders and soft shadow, not heavy cards.',
  ],
  conflicts: [
    'Opus & Sonnet want a denser data grid; Gemini argues for more whitespace and fewer KPIs.',
    'ChatGPT proposes a dark theme by default; Composer keeps light primary with a dark mode toggle.',
  ],
  gaps: [
    'No one addressed empty/loading states — premium products feel polished there first.',
    'Motion was mentioned but unspecified; needs an easing + duration system.',
  ],
  plan: [
    'Set a type scale (display 800 / body 400) and an 8px spacing grid; apply to the header + KPI row first.',
    'Collapse the palette to one accent + a 7-step neutral ramp; remove all gradients from tiles.',
    'Rebuild cards as hairline-border + soft-shadow surfaces; unify radius at 10px.',
    'Design the empty, loading, and error states for the main chart before adding features.',
    'Adopt a 160–240ms ease-out motion system for hovers, opens, and value changes.',
  ],
  minority: { who: 'Gemini Flash', text: 'Cut the dashboard to 3 KPIs and one chart. Most “premium” wins come from removing, not styling.' },
};

window.AL_ANSWERS = {
  opus:     'Three directions: (1) Editorial — big type, generous whitespace, one accent. (2) Control-room — dense, mono numerics, dark. (3) Calm-OS — soft surfaces, muted color, motion. I’d ship (1): premium is restraint. Start with the type scale and spacing grid, then strip gradients.',
  gpt:      'Default to a dark theme; it instantly reads as pro. Use a single saturated accent for primary actions and keep every surface near-black with hairline borders. Tighten the KPI row to four metrics and set them in a mono face.',
  sonnet:   'Premium = hierarchy + consistency. Define a 6-step type scale and an 8px grid, then audit every component against it. Add a denser data table with sticky headers; power users equate density with capability.',
  composer: 'Keep light as primary with a polished dark mode. Standardize radius (10px), border (1px hairline), and shadow (one soft step). Replace icon noise with a tighter set. Ship a motion spec: 200ms ease-out.',
  gemini:   'Less is the upgrade. Cut to three KPIs and one chart, double the whitespace, and remove decorative color entirely. A premium dashboard answers one question beautifully, not ten adequately.',
  grok:     '',
};

// Glyph renderer: brand logo when available, else a Lucide icon.
window.Glyph = function Glyph({ worker, size = 18 }) {
  const { BrandIcon, Icon } = window;
  if (worker.brand) return R.createElement(BrandIcon, { slug: worker.brand, color: worker.color, size });
  return R.createElement(Icon, { name: worker.icon || 'terminal', size: size - 2, style: { color: 'var(--text-secondary)' } });
};
