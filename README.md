# solid-website

Personal portfolio website for Ve Bui (Software Engineer), built with [SolidJS](https://www.solidjs.com/) + [Vite](https://vitejs.dev/) and deployed to GitHub Pages.

## Getting started

```bash
yarn install
yarn dev      # start the dev server (exposed on the local network via --host)
```

## Build & deploy

```bash
yarn build    # production build to dist/
yarn deploy   # publish dist/ to the gh-pages branch via gh-pages
```

The live site is served from the `gh-pages` branch of this repo.

## Project layout

- `src/index.tsx` — entry; registers the `<main-page>` custom element
- `src/pages/` — page sections (Header, Home, NavBar, ThreeBackground, …)
- `src/components/` — reusable components
- `src/context/` — global state (page switching)
- `src/data/` — static JSON content

See [CLAUDE.md](./CLAUDE.md) for architecture and conventions.

## Reusing this site

In `src/pages/Home/Home.tsx`, set `startDate` — the "years of experience" figure is computed from it. Experience entries in `src/components/Experience/Experience.tsx` are currently hardcoded placeholders.

## Todo

- Decouple the header and content area from the shared flex layout.
