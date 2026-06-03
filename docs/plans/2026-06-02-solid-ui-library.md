# Solid UI Library + Storybook + a11y Implementation Plan

> **For Claude:** Execute task-by-task. There is no test runner yet; "verify" steps use `yarn build`, `yarn storybook`, and the a11y addon as the safety net. Commit after each green phase.

**Goal:** Build an in-repo, accessible SolidJS component library (`src/ui/`) documented in Storybook, themed by the existing token system, dogfooded by the portfolio, and deployed publicly at `/storybook`.

**Architecture:** Primitives live in `src/ui/<Name>/` (component + scss + stories), consuming CSS custom-property tokens extracted to a shared `src/ui/theme/` partial. The site imports primitives from `src/ui/`. Storybook (storybook-solidjs-vite) applies the tokens via a global decorator and runs `@storybook/addon-a11y` (axe-core) on every story. Storybook builds to `storybook-static/` and is published to the `gh-pages` branch under `/storybook` alongside the site.

**Tech Stack:** SolidJS 1.8, Vite 6, TypeScript, SCSS (`?inline`), Storybook 8 (storybook-solidjs-vite renderer), @storybook/addon-a11y.

**Decisions (locked):** in-repo `src/ui/` · deploy Storybook publicly · upgrade Vite to 5/6.

---

## Phase 0 — Dependency upgrade (gates everything)

**Why first:** modern Storybook needs Vite 5+; this also clears most of the 40 Dependabot alerts. Riskiest step — verify the live build still works before building on it.

**Files:** `package.json`, `vite.config.ts`, `yarn.lock`

- Bump `vite` → `^6`, `vite-plugin-solid` → `^2.11`, `vite-plugin-html` to a Vite-6-compatible version (or replace with a small custom html transform if it lags), `sass` → latest.
- `yarn install`, then `yarn build`. Expected: build succeeds, `dist/` produced.
- `yarn dev` smoke check; `npx vite preview` + a quick Playwright load of the homepage to confirm no runtime regressions (shadow DOM, Three-free narrative, nav scroll-spy).
- Commit: `chore: upgrade Vite to 6 (+ clears Dependabot alerts)`.

## Phase 1 — Storybook scaffold + a11y

**Files:** `.storybook/main.ts`, `.storybook/preview.tsx`, `package.json` (scripts + devDeps)

- Add devDeps: `storybook`, `storybook-solidjs-vite` (or `@storybook/your-solid-renderer` current), `@storybook/addon-a11y`, `@storybook/addon-essentials`.
- `.storybook/main.ts`: framework `storybook-solidjs-vite`, stories glob `../src/ui/**/*.stories.@(tsx|ts)`, addons essentials + a11y. Reuse the project `vite.config.ts` (viteFinal merge) so SCSS `?inline` resolves identically.
- Scripts: `"storybook": "storybook dev -p 6006"`, `"build-storybook": "storybook build"`.
- Verify `yarn storybook` boots with zero stories (or one placeholder).
- Commit: `chore: scaffold Storybook for Solid with a11y addon`.

## Phase 2 — Extract design tokens to a shared theme

**Files:** Create `src/ui/theme/tokens.scss`, `src/ui/theme/index.ts`; modify `src/index.scss`, `.storybook/preview.tsx`

- Move the `--bg…--d-accent-2`, fonts, `--maxw` token block out of `.site` into `src/ui/theme/tokens.scss`, exposed both as a `.ui-theme` selector and importable `?inline` string. Keep a `.ui-theme--dark` modifier that remaps light tokens to the `--d-*` values (same trick as `.hp-scene-dark`).
- `src/index.scss` `.site` re-uses the tokens (import the partial) so the site is unchanged visually.
- `.storybook/preview.tsx`: global decorator wraps every story in `<div class="ui-theme">…`, injects the token `<style>`, loads Inter + JetBrains Mono, and adds a light/dark **toolbar toggle** (globalTypes) that switches `ui-theme` ↔ `ui-theme--dark`.
- Verify: `yarn build` (site unchanged) + Storybook shows tokens applied.
- Commit: `refactor: extract design tokens into shared src/ui/theme`.

## Phase 3 — First primitives (Button, Tag, Card)

For each primitive: `src/ui/<Name>/<Name>.tsx` (named export, `props` not destructured, `class` not className, `<style>{styles}</style>` pattern), `<Name>.scss?inline`, `<Name>.stories.tsx` (CSF3, multiple variants), and re-export from `src/ui/index.ts`.

- **Button** — variants (primary/ghost/ai), sizes, `disabled`, optional `as="a"` (href) vs `<button>`; forwards `aria-*`; visible `:focus-visible`. Stories cover every variant + a disabled + a link button. a11y panel must be clean.
- **Tag/Pill** — used by project filters; `selected` state with `aria-pressed`; the `ai` variant carries the ✦ sparkle styling.
- **Card** — surface container; header/body/footer slots via `props.children` + named props; respects dark theme token remap.
- Verify each in Storybook with the a11y panel green (fix contrast/roles as flagged).
- Commit per primitive: `feat(ui): add <Name> primitive with stories`.

## Phase 4 — Interactive primitives (driven by site needs)

- **Dialog/Modal** (if useful for project expand or fit results) — focus trap, `Esc` to close, `role="dialog"` + `aria-modal`, returns focus to trigger. a11y-critical; test keyboard flow in Storybook.
- **VisuallyHidden**, **SkipLink**, **Field/Label** helpers as needed.
- Commit per primitive.

## Phase 5 — Dogfood: refactor the site onto `src/ui/`

- Replace ad-hoc buttons/pills/cards in `Home.tsx`, `ProjectShowcase.tsx`, `FitAnalyzer.tsx`, `NavBar.tsx` with `ui/` primitives where it's a clean swap (don't force-fit bespoke layout).
- Verify visually via Playwright screenshots vs. current; `yarn build`.
- Commit: `refactor: adopt ui/ primitives across the site`.

## Phase 6 — Deploy Storybook to /storybook + showcase it

**Files:** `package.json` (deploy scripts), `src/data/projects.json`, `src/pages/Home/Home.tsx` (or footer link)

- `build-storybook` → `storybook-static/`. Add a deploy step that publishes BOTH `dist/` and `storybook-static/` to `gh-pages` so the site lives at `/` and Storybook at `/storybook` (e.g. `gh-pages -d dist` then copy storybook-static into a `/storybook` subdir of the publish dir, or a combined out dir). Confirm relative-base works for Storybook (`--base` / managerHead).
- Add a project entry: **"Accessible Solid UI Library"** (category Frontend) with a live `/storybook` link and a takeaway about a11y-first, token-driven design.
- Add a footer/nav link to the live Storybook.
- Verify the deployed `/storybook` loads and stories render.
- Commit: `feat: deploy Storybook to /storybook and add it to the showcase`.

## Later / optional

- Vitest + `@solidjs/testing-library` + jsdom for real unit tests on primitives (interaction, a11y assertions). Adds the missing test runner.
- Storybook interaction tests (`play` functions) for keyboard flows.
- Publish `@vebui/ui` to npm if the library outgrows the repo.
