# solid-website

Personal portfolio site for **Ve Bui** — SolidJS + Vite 6 + TypeScript, deployed
to GitHub Pages.

Live: <https://vekbui96.github.io/solid-website/>
Component library (Storybook): <https://vekbui96.github.io/solid-website/storybook/>

It is a single scrolling page with nine sections, a scroll-spy that morphs the
header title as you read, an in-browser "Think I'm a Good Fit?" job-description
analyzer, and a contact form that posts to a self-hosted Spring Boot backend.

## Getting started

Requires Node and **yarn** (`yarn.lock` is committed).

```bash
yarn install
yarn dev        # Vite dev server, --host, http://localhost:5173
```

**Use `http://localhost:5173`, not the LAN URL that `--host` also prints.** The
backend's CORS allowlist contains `http://localhost:5173`, `http://localhost:3000`
and `https://vekbui96.github.io` and nothing else, so loading the dev site by IP
makes the contact form fail as a network error. Same if 5173 is taken and Vite
falls back to 5174.

## Commands

| Command | What it does |
| --- | --- |
| `yarn dev` | Vite dev server on 5173, exposed on the LAN via `--host` |
| `yarn build` | Site → `dist/` |
| `yarn storybook` | Storybook on 6006, with the axe a11y addon |
| `yarn build-storybook` | Storybook → `storybook-static/` |
| `yarn build:all` | `vite build`, then Storybook → `dist/storybook/` |
| `yarn deploy` | `build:all`, then publish `dist/` to the `gh-pages` branch |

There is **no test runner, linter, or formatter**, and no CI — nothing runs
automatically on push. The only automated check is Storybook's axe panel, which
covers `src/ui/` only.

## Deploy

```bash
yarn deploy
```

This builds the site and Storybook into `dist/`, then force-pushes `dist/` to the
`gh-pages` branch, which is what GitHub Pages serves. Deploys are manual, run
from a workstation.

Two things to know:

- **Order matters inside `build:all`.** `vite build` empties `dist/`, so
  Storybook is built into `dist/storybook` afterwards. Running a bare
  `yarn build` after a `build:all` deletes the Storybook output.
- **`vite.config.ts` sets `base: ""` on purpose.** The site is served from the
  `/solid-website/` subpath, so assets must be relative. Changing `base` to `/`
  produces a page that returns HTTP 200 and loads nothing.

## The backend

The contact form is the only network call the site makes:
`POST {API_BASE}/api/contact`, where `API_BASE` comes from `VITE_API_URL` at
build time and defaults to `https://server-pc.tail0e4194.ts.net`.

The server is a separate repo — [`solid-website-api`](https://github.com/vekbui96/solid-website-api)
(Spring Boot; checked out locally as `../personal-site-api`). It validates the
payload, drops honeypot submissions, rate-limits by IP, and sends the message on
via Resend.

Because this is a static bundle, the backend URL is compiled into the JS.
Repointing it means a rebuild and redeploy.

## Project layout

```
index.html                 light-DOM shell: <main-page>, SEO/OG tags, noscript copy
src/index.tsx              defines the <main-page> custom element (Shadow DOM)
src/pages/Home/Home.tsx    the entire page — 9 sections
src/pages/Header/          sticky header; title morphs with the active section
src/pages/NavBar/          scroll-spy + section navigation
src/components/            Projects showcase, Fit analyzer, Contact form, Experience
src/lib/api.ts             contact-form client
src/lib/fitAnalysis.ts     the shipped, in-browser fit scoring
src/ui/                    standalone component library (Storybook only)
src/data/*.json            projects, experience, navbar content
fit-backend/               CrewAI multi-agent fit analyzer — CLI only, not wired up
docs/                      dated design + plan notes from June 2026
```

## Two things that surprise people

- **The Fit Analyzer is not AI.** What ships is a deterministic keyword matcher
  (`src/lib/fitAnalysis.ts`). The CrewAI six-agent crew in `fit-backend/` is real
  and runnable from the command line, but nothing serves it over HTTP and the
  site never calls it. See `fit-backend/README.md`.
- **The site does not use its own component library.** `src/ui/` is published to
  `/storybook/` as a portfolio exhibit; no page or section imports from it.

## Working on this

Read [CLAUDE.md](./CLAUDE.md) before changing anything structural. It covers the
Shadow DOM constraints (why every component inlines its own `<style>`, and why
`document.getElementById` cannot find the sections), the scroll-spy and
`data-nav-dark` conventions, the contact-form response contract, and an audited
list of dead files.

## Reusing this site

The content is specific to one person. If you fork it:

- `src/data/projects.json` and `src/data/experience.json` hold the real content.
- `src/pages/Home/Home.tsx` carries the narrative copy and the `startDate` used
  to compute years of experience.
- `src/lib/fitAnalysis.ts` hardcodes per-axis strengths and an honest list of
  skill gaps. Both are personal claims — rewrite them rather than tuning them.
- `index.html` contains the name, canonical URL, Open Graph tags and
  `schema.org` Person block.

## License

MIT.
