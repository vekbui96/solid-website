# CLAUDE.md

Guidance for working in this repo.

## What this is

A personal portfolio website for Ve Bui (Software Engineer), built with **SolidJS** + **Vite** + **TypeScript**, deployed to **GitHub Pages**. It's a single-page site with a Three.js animated background, a header, and a context-switched content area (Home / About / Projects).

## Commands

Package manager is **yarn** (`yarn.lock` is committed).

- `yarn dev` — start the Vite dev server (`--host`, exposed on the network)
- `yarn build` — production build of the site to `dist/`
- `yarn storybook` — run Storybook (Solid renderer) on port 6006 with the a11y addon
- `yarn build-storybook` — build Storybook static output (standalone)
- `yarn build:all` — build the site to `dist/` **and** Storybook into `dist/storybook/`
- `yarn deploy` — runs `build:all`, then publishes `dist/` to the `gh-pages` branch. The site lives at `/`, Storybook at `/storybook/`. The live site is served from `origin/gh-pages`; don't edit that branch by hand.

There is no test runner, linter, or formatter configured (a11y is checked via Storybook's axe addon).

## Architecture

- **Entry:** `index.html` mounts a `<main-page />` custom element. `src/index.tsx` defines that element via `solid-element`'s `customElement('main-page', ...)`, wrapping `<MainPage>` in `GlobalContextProvider`. `MainPage` lays out `ThreeBackground`, `Header`, and the `display-manager` content area.
- **Three.js background:** `src/pages/ThreeBackground/ThreeBackground.jsx` sets up the scene (wireframe sphere + particle field) inside `onMount`, with a `resize` listener and `onCleanup` disposal. This is plain imperative Three.js, not reactive Solid.
- **Global state:** `src/context/GlobalContext.tsx` exposes signals via `useGlobalContext()`. The `page` signal (`setPage`) drives which section shows; `NavBar.tsx` calls `setPage("home" | "about" | "projects")`. Note: the content area in `index.tsx` currently always renders `<Home/>` — page switching is wired in context but not yet branched in the layout.
- **Pages** live in `src/pages/<Name>/` (Header, Home, HeroArea, NavBar, About, SocialMedia, ThreeBackground). **Reusable pieces** live in `src/components/`. **Static content** is JSON in `src/data/` (`navbar.json`, `about.json`).
- **Component library:** `src/ui/<Name>/` holds the accessible primitive library (Button, Tag, Card, Dialog, plus VisuallyHidden/SkipLink helpers), each with a sibling `.scss` and `.stories.tsx`, re-exported from `src/ui/index.ts`. Design tokens live in `src/ui/theme/_tokens.scss` as `@mixin design-tokens` / `dark-tokens` — the single source of truth consumed by both `.site` (`src/index.scss`) and Storybook (`.ui-theme` in `theme.scss`). Storybook config is in `.storybook/`; the preview wraps stories in the token theme with a light/dark toolbar toggle. Add a story for every new primitive and keep the axe a11y panel clean.

## Conventions

- **Styling:** each component imports its sibling `.scss` with the `?inline` query (`import styles from './X.scss?inline'`) and renders `<style>{styles}</style>` at the top of its JSX. There is no global stylesheet link beyond fonts in `index.html`. Keep this per-component inline-style pattern.
- **File extensions are mixed** (`.tsx` and `.jsx`). Imports often reference `.jsx` even for `.tsx` files (e.g. `./Home.jsx`) — Vite resolves these. Match the extension of the file you're editing; don't mass-convert.
- **Components** are arrow-function exports returning a Solid fragment. Most are named exports (`export const Home`); `ThreeBackground` is a default export.
- **Solid, not React:** use `class` (not `className`), Solid primitives (`createSignal`, `createEffect`, `onMount`, `onCleanup`), and remember JSX props are reactive — read `props.x` in the body, don't destructure.
- TypeScript is loose (no strict mode); `// @ts-ignore` is used for `?inline` SCSS imports. JSX is `preserve` with `jsxImportSource: solid-js`.

## Notes / known rough edges

- `src/main.tsx` is a leftover stub (returns `test`) and is unused.
- When reusing this site, set the experience start date in `src/pages/Home/Home.tsx` (`startDate`) — years-of-experience is computed from it. Experience entries in `Experience.tsx` are currently hardcoded placeholders.
- `vite.config.ts` sets `base: ""` and `build.target: 'esnext'` for GitHub Pages relative paths.
