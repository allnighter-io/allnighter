// @ds-adherence-ignore -- Team command-center sample data + glyph helpers. Window globals.
const R = window.React;

window.TEAM_SOURCES = [
  {
    id: 'claude',
    name: 'Claude Code',
    command: 'claude',
    version: 'v2.1.0',
    path: '~/.local/bin/claude',
    status: 'ready',
    invocation: 'direct',
    lastProbe: 'smoke 2m ago',
    models: ['Opus 4.8', 'Sonnet 4.6'],
    lanes: ['Build', 'Copy', 'Review'],
    brand: 'anthropic',
    color: 'FFA630',
  },
  {
    id: 'codex',
    name: 'Codex CLI',
    command: 'codex',
    version: 'v1.4.2',
    path: '~/.volta/bin/codex',
    status: 'ready',
    invocation: 'shim',
    lastProbe: 'smoke 9m ago',
    models: ['ChatGPT 5.5'],
    lanes: ['Build', 'Copy'],
    icon: 'terminal',
  },
  {
    id: 'grok',
    name: 'Grok CLI',
    command: 'grok',
    version: 'v0.9.1',
    path: '/opt/homebrew/bin/grok',
    status: 'ready',
    invocation: 'direct',
    lastProbe: 'smoke 18m ago',
    models: ['Grok Build', 'Grok Imagine'],
    lanes: ['Build', 'Design'],
    brand: 'x',
    color: 'E1E5F0',
  },
  {
    id: 'agy',
    name: 'Antigravity CLI',
    command: 'agy',
    version: 'v0.7.0',
    path: '/Applications/Antigravity.app/.../agy',
    status: 'ready',
    invocation: 'app bundle',
    lastProbe: 'image smoke 31m ago',
    models: ['Gemini image', 'Gemini Flash'],
    lanes: ['Design', 'Build'],
    brand: 'googlegemini',
    color: 'E1E5F0',
  },
  {
    id: 'cursor',
    name: 'Cursor',
    command: 'cursor-agent',
    version: 'v0.46.3',
    path: '/Applications/Cursor.app/.../cursor-agent',
    status: 'ready',
    invocation: 'login shell',
    lastProbe: 'smoke 1h ago',
    models: ['Composer 2.5'],
    lanes: ['Build'],
    icon: 'square',
  },
];

window.TEAM_MODELS = [
  { id: 'opus', name: 'Opus 4.8', source: 'claude', caps: ['build', 'copy', 'review'], week: '42 runs', status: 'ready' },
  { id: 'sonnet', name: 'Sonnet 4.6', source: 'claude', caps: ['build', 'copy', 'review'], week: '38 runs', status: 'ready' },
  { id: 'gpt', name: 'ChatGPT 5.5', source: 'codex', caps: ['build', 'copy'], week: '31 runs', status: 'ready' },
  { id: 'grokBuild', name: 'Grok Build', source: 'grok', caps: ['build'], week: '12 runs', status: 'ready' },
  { id: 'grokImagine', name: 'Grok Imagine', source: 'grok', caps: ['design'], week: '9 images', status: 'ready' },
  { id: 'geminiImage', name: 'Gemini image', source: 'agy', caps: ['design'], week: '7 images', status: 'ready' },
  { id: 'geminiFlash', name: 'Gemini Flash', source: 'agy', caps: ['design', 'build'], week: '7 runs', status: 'ready' },
  { id: 'composer', name: 'Composer 2.5', source: 'cursor', caps: ['build'], week: '4 runs', status: 'ready' },
];

window.TEAM_SKILLS = {
  build: [
    { id: 'first_principles', name: 'First-principles reviewer', model: 'opus', kind: 'review' },
    { id: 'skeptic', name: 'Skeptic', model: 'sonnet', kind: 'review' },
    { id: 'maintainer', name: 'Maintainer', model: 'gpt', kind: 'implementation' },
    { id: 'proof', name: 'Proof skeptic', model: 'geminiFlash', kind: 'qa' },
    { id: 'executor', name: 'Executor', model: 'grokBuild', kind: 'implementation' },
  ],
  design: [
    { id: 'minimal', name: 'Minimal designer', model: 'grokImagine', kind: 'image' },
    { id: 'bold', name: 'Bold designer', model: 'geminiImage', kind: 'image' },
    { id: 'brand', name: 'On-brand designer', model: 'gpt', kind: 'critique' },
    { id: 'product', name: 'Product critic', model: 'opus', kind: 'critique' },
  ],
};

window.TEAM_PRESETS = {
  build: {
    lane: 'Build',
    type: 'Feature',
    effort: 'Deep',
    outputs: '5 workers · spec + implementation options',
    runLabel: 'Run build team',
    brief: 'Turn a work order into implementation paths, risks, proof, and a clean handoff.',
  },
  design: {
    lane: 'Design',
    type: 'Redesign',
    effort: 'Standard',
    outputs: '3 image options · 1 critique pass',
    runLabel: 'Run design team',
    brief: 'Generate real visual options from the models that can make or critique images.',
  },
};

window.TEAM_MODEL_OPTIONS = window.TEAM_MODELS.map((m) => ({ value: m.id, label: m.name }));

window.TeamSource = function TeamSource(id) {
  return window.TEAM_SOURCES.find((s) => s.id === id);
};

window.TeamModel = function TeamModel(id) {
  return window.TEAM_MODELS.find((m) => m.id === id);
};

window.TeamGlyph = function TeamGlyph({ source, model, size = 18 }) {
  const { BrandIcon, Icon } = window;
  const src = source || (model && window.TeamSource(model.source));
  if (src && src.brand) return R.createElement(BrandIcon, { slug: src.brand, color: src.color, size });
  return R.createElement(Icon, { name: (src && src.icon) || 'terminal', size: size - 2, style: { color: 'var(--text-secondary)' } });
};
