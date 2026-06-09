## 1. Update design tokens

- [x] 1.1 In `src/ui/theme/_tokens.scss` `design-tokens`, restore the neutral base: `--bg: #ffffff`, `--surface: #f8fafc`, `--text: #0b1220`, `--muted: #5b6577`, `--border: #e5e8ee`.
- [x] 1.2 In `design-tokens`, set the cyan accent family: `--accent: #22d3ee`, `--accent-ink: #0e7490`, `--accent-soft: rgba(34, 211, 238, 0.12)`. Update the trailing comments to describe cyan.
- [x] 1.3 In `design-tokens`, restore the dark scene neutrals: `--d-bg: #0b0e14`, `--d-surface: #121723`, `--d-text: #e6eaf2`, `--d-muted: #8b95a7`, `--d-border: #222a38`.
- [x] 1.4 In `design-tokens`, set the dark accents: `--d-accent: #22d3ee`, `--d-accent-2: #7dd3fc`.
- [x] 1.5 In the `dark-tokens` mixin, update `--accent-ink: var(--d-accent)` (keep) and `--accent-soft: rgba(34, 211, 238, 0.14)`.

## 2. Sweep hardcoded accent literals

- [x] 2.1 `src/pages/Home/Home.scss` — replace each `rgba(255, 90, 77, X)` with `rgba(34, 211, 238, X)` (preserve alpha); includes the `--accent-soft` override on line ~188.
- [x] 2.2 `src/components/Projects/ProjectShowcase.scss` — replace each `rgba(255, 90, 77, X)` with `rgba(34, 211, 238, X)`.
- [x] 2.3 `src/components/Fit/FitAnalyzer.scss` — replace each `rgba(255, 90, 77, X)` with `rgba(34, 211, 238, X)`.
- [x] 2.4 `src/pages/Header/header.scss` — replace `rgba(255, 90, 77, 0.14)` with `rgba(34, 211, 238, 0.14)`.
- [x] 2.5 `src/ui/ReasoningTrace/ReasoningTrace.scss` — replace each `rgba(255, 90, 77, X)` with `rgba(34, 211, 238, X)`.

## 3. Verify

- [x] 3.1 Repo-wide grep confirms no `rgba(255, 90, 77` or `rgba(229, 57, 47` and no old red hex (`#e5392f`, `#bf2b22`, `#ff5a4d`, `#f2a541`) remain in `src/`.
- [x] 3.2 Run `yarn storybook` and confirm the axe a11y panel reports no color-contrast violations on the primitive stories (Button, Tag, Card, Dialog, ReasoningTrace).
- [x] 3.3 Run `yarn dev` and spot-check the homepage (light + dark scenes), Projects, and Header: base reads white/black, accent reads cyan, accent text is legible.
