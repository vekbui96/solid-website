# CLAUDE.md

Personal portfolio site for Ve Bui. **SolidJS + Vite 6 + TypeScript**, shipped as a
single custom element, deployed to **GitHub Pages** from the `gh-pages` branch.

Live at <https://vekbui96.github.io/solid-website/>.

The contact form talks to a **separate repo** — `solid-website-api` (Spring Boot),
checked out locally as `../personal-site-api`, self-hosted on SERVER-PC and
published over Tailscale Funnel. Changing the contact form usually means reading
that repo too.

Most of what follows is here because it is not guessable from the file names.

## Commands

Package manager is **yarn** (`yarn.lock` is committed; there is no
`package-lock.json`).

- `yarn dev` — Vite dev server with `--host` (see the CORS trap below)
- `yarn build` — site to `dist/`
- `yarn storybook` — Storybook on port 6006, a11y addon enabled
- `yarn build:all` — `vite build && storybook build -o dist/storybook`
- `yarn deploy` — `build:all`, then `gh-pages -d dist`

**There is no test runner, no linter, and no formatter.** No Prettier config, no
ESLint, and no `.github/` directory — so **there is no CI and nothing gates a
commit**. Deploys happen from a workstation by running `yarn deploy` by hand.
The only automated quality check in the project is Storybook's axe a11y panel,
and it only covers `src/ui/`.

**The order inside `build:all` is load-bearing.** `vite build` empties `dist/`
before writing, so Storybook must be built *into* `dist/storybook` afterwards.
Running a bare `yarn build` after a `build:all` silently deletes the Storybook
output; if `/storybook/` 404s on the live site, this is why.

## Deploying

```bash
yarn deploy      # build:all + gh-pages -d dist
```

That is the whole procedure. `gh-pages` force-pushes `dist/` to the `gh-pages`
branch of `origin`. **Never edit `gh-pages` by hand** — the next deploy discards
it.

`vite.config.ts` sets `base: ""`. This is deliberate and required: the site is
served from a project subpath (`/solid-website/`), not a domain root, so assets
must be referenced relatively. Setting `base` to `/` publishes a page that
returns HTTP 200 and loads nothing.

**The backend URL is baked in at build time.** `src/lib/api.ts` reads
`import.meta.env.VITE_API_URL` and falls back to
`https://server-pc.tail0e4194.ts.net`. This is a static bundle — the value is
compiled into the JS, so pointing the site at a different backend means a
rebuild and redeploy, not a config change. Never put a secret in a `VITE_`
variable here for the same reason.

**Not established:** whether this site has ever been published by anything other
than a manual `yarn deploy`. There is no workflow file in the repo, and the
`gh-pages` branch is the only evidence of a deploy.

## Architecture

### The whole site is one custom element, and that means Shadow DOM

`index.html` contains `<main-page>`. `src/index.tsx` defines it with
`solid-element`'s `customElement('main-page', ...)`, wrapping `<MainPage>` in
`GlobalContextProvider`. `MainPage` renders `<Header>` plus a
`<main class="page-host">` containing `<Home>`.

`customElement` mounts into a **shadow root**. Two consequences drive most of
the conventions in this repo:

1. **Global stylesheets do not reach the components.** Every component imports
   its sibling `.scss` with `?inline` and renders `<style>{styles}</style>` at
   the top of its own JSX. There is no site-wide stylesheet link beyond the
   Google Fonts tag in `index.html`. Keep this pattern; a global stylesheet
   would apply to nothing.
2. **`document.getElementById` cannot see the sections.** They live inside the
   shadow root. `NavBar.tsx` works around this explicitly:

   ```ts
   const root = () => navEl?.getRootNode() as ShadowRoot | Document | undefined;
   r?.getElementById?.(id)?.scrollIntoView(...)
   ```

   Any new code that needs to find a section by id must go through
   `getRootNode()` the same way. A plain `document.querySelector` returns `null`
   and the failure is silent. For the same reason the nav is **buttons calling
   `scrollIntoView`, not `<a href="#story">`** — fragment navigation does not
   cross the shadow boundary.

`index.html` also carries the `<noscript>` fallback, the canonical URL, Open
Graph tags and a `schema.org` Person block. Those are in the light DOM on
purpose — crawlers and social scrapers never execute the custom element.

### One page, nine sections, driven by a scroll-spy

`src/pages/Home/Home.tsx` (271 lines) is the entire page. Its sections, in
order, with the ids other code depends on:

`hero` → `story` → `range` → `ai` → `projects` → `fit` → `experience` →
`systems` → `contact`

Sections from `ai` onward carry `class="hp-scene-dark"` and the
**`data-nav-dark`** attribute.

`NavBar.tsx` observes all nine (the `tracked` array) with an
`IntersectionObserver` at `rootMargin: "-14% 0px -80% 0px"` — a thin band near
the top of the viewport, so "active" means "the section under the header", not
"the section that is most visible". On intersection it sets two context signals:

- `setActiveSection(el.id)` — drives the nav's `active` class and `aria-current`
- `setOnDark(el.hasAttribute("data-nav-dark"))` — flips the header to
  `topbar-dark`

**To make a section dark you add `data-nav-dark` to the markup.** There is no
list of dark section ids anywhere; the attribute is the source of truth. The id
*does* still need adding to `tracked` in `NavBar.tsx`, or the header keeps
whatever state the previous section left it in as you scroll past.

`header.tsx` maps `activeSection` through `TITLE_BY_SECTION` so the subtitle
morphs `Software Engineer → Full-Stack Software Engineer → AI Engineer` as you
scroll. It is a plain record; a section id missing from it falls back to
`"Full-Stack Software Engineer"`, which is *not* the same as the `hero` value,
so new sections should be added there too.

### Global state is three signals, and none of them is routing

`src/context/GlobalContext.tsx` exposes exactly `activeSection`, `onDark`, and
`openProjectId`. `openProjectId` is how the Fit Analyzer deep-links a project
open in `ProjectShowcase` without the two components knowing about each other.

There is **no router and no page switching**, despite `@solidjs/router` being in
`dependencies`. It is unused. Everything is one scrolling document.

### Entrance animations: the `reveal` directive

`src/utils/reveal.ts` is a Solid directive (`use:reveal`, optionally
`use:reveal={{ delay: 80 }}`). It adds `.reveal` immediately and `.in-view` on
intersection (`threshold: 0.15`, `rootMargin: "0px 0px -10% 0px"`), then
**unobserves** — entrances play once, not on every scroll past.

It checks `prefers-reduced-motion` and, when set, adds `.in-view` immediately
and never creates an observer at all. The same check appears in `header.tsx`,
`NavBar.tsx` (smooth vs. instant scroll) and `FitAnalyzer.tsx` (score-dial
tween). **Honor it in anything new** — it is a consistent convention here, not
an accident.

## The Fit Analyzer is client-side. The CrewAI backend is not wired up.

This is the most misleading thing in the repo, so it is stated plainly:

- **What ships:** `src/lib/fitAnalysis.ts` — a deterministic, in-browser keyword
  matcher. No network call, no LLM. `FitAnalyzer.tsx` imports `analyzeFit` and
  calls it synchronously; the "Reading the role / Extracting requirements / …"
  step list is a timed animation over a computation that has already finished.
- **What does not ship:** `fit-backend/` — a real CrewAI six-agent crew
  (JD Interpreter → Requirements Analyst → Evidence Mapper → Gap Auditor →
  Honest Fit Assessor → Pitch Strategist). It is **CLI only**
  (`python crew.py "<jd>"`, `--hierarchical` for a delegating manager). There is
  no HTTP server in front of it and the site never calls it.
  `fit-backend/README.md` is honest about this and names "expose it behind
  FastAPI" as the next step. Its output type deliberately matches the front-end
  `FitReport` contract so it could drop in unchanged.

Do not describe the site's fit feature as AI-powered, and do not "fix" the
frontend to await a backend that is not running.

### How the shipped scoring actually works

Worth knowing before touching it, because the numbers are tuned:

- Six axes (`ai`, `backend`, `frontend`, `platform`, `cloud`, `devex`), each with
  a hardcoded candidate `STRENGTH` (0.78–0.95) and a keyword list (`CONCEPTS`).
- `demand` per axis = keyword hits, normalized against the highest-scoring axis.
- Requirement lines are pulled verbatim out of the pasted JD (split on newlines
  and sentence punctuation; kept if 14–220 chars and containing at least one
  known term; top 6 by term count) and matched against `src/data/projects.json`
  for evidence. Using the reader's own words is the point — it is what makes the
  report feel tailored.
- `score = round((0.5 * coverage + 0.5 * alignment) * 100)`, then clamped:
  **fewer than 3 keyword signals caps the score at 45; zero signals caps it at
  22**; the final clamp is 8–98. Those caps exist so pasting arbitrary text
  cannot produce a flattering number.
- Bins: ≥85 Excellent, ≥66 Strong, ≥41 Moderate, else Exploratory.
- `GAP_TERMS` reports honest gaps (iOS, Swift, Kotlin, model training,
  PyTorch/TensorFlow, computer vision, data science, blockchain, games) and only
  fires when the term appears in the JD **and** in no project.

Both the gap list and the strength values are editorial claims about a real
person. Changing them is a content decision, not a tuning decision.

## Contact form → solid-website-api

`src/components/Contact/ContactForm.tsx` → `submitContact` in `src/lib/api.ts`
→ `POST {API_BASE}/api/contact`.

The response contract, verified against
`../personal-site-api/src/main/java/com/vebui/personalsiteapi/web/`:

| Status | Body                                  | Frontend behavior                    |
| ------ | ------------------------------------- | ------------------------------------ |
| 200    | `{status:"received", message}`        | success, fields cleared              |
| 400    | `{message, errors: {field: msg}}`     | per-field errors under each input    |
| 429    | `{status:"error", message}`           | generic error, shows the server text |
| 502    | `{status:"error", message}`           | email delivery failed server-side    |

`api.ts` only reads `errors` on a **400**. The field keys are `name`, `email`
and `message`, and they must keep matching the `ContactRequest` record field
names on the Java side, or validation messages render nowhere.

**A honeypot hit looks exactly like success.** The `website` field is a hidden
input that humans never fill. If it arrives non-blank the backend logs it and
returns the normal 200 acknowledgment — deliberately, so bots are not told they
were caught. That means "the form said thanks but no email arrived" is an
expected outcome for a bot and an alarming one for a human. Check the backend
log before assuming email delivery is broken.

### The CORS trap with `yarn dev --host`

The backend allowlists exactly three origins (`app.cors.allowed-origins` in
`application.properties`):

```
https://vekbui96.github.io, http://localhost:3000, http://localhost:5173
```

`yarn dev` runs `vite --host`, which prints a LAN URL alongside the localhost
one. **Loading the dev site by its LAN address (`http://192.168.x.x:5173`) puts
the contact form outside the allowlist** — CORS matches the origin string
exactly, and the IP form is not `localhost`. The submit then fails as a network
error and `api.ts` shows "Couldn't reach the server", which reads exactly like
the server being down. Test the contact form on `http://localhost:5173`
specifically.

Note also that only ports 5173 and 3000 are allowlisted: if 5173 is already
taken, Vite moves to 5174 without saying much and the form breaks the same way.

## The `src/ui/` component library is not used by the site

`src/ui/` holds Button, Tag, Card, Dialog, ReasoningTrace, VisuallyHidden and
SkipLink, each with a sibling `.scss` and `.stories.tsx`, re-exported from
`src/ui/index.ts`. Design tokens live in `src/ui/theme/_tokens.scss` as
`@mixin design-tokens` / `dark-tokens`, consumed by both `.site`
(`src/index.scss`) and Storybook's `.ui-theme`.

**But nothing in `src/pages/` or `src/components/` imports from `src/ui`.**
Verified: the only consumers are `src/ui/index.ts` and other files inside
`src/ui/` (Tag is used by Card's story, Button by Dialog's story). The library
is real, documented and deployed to `/storybook/`, and the site links to it — it
is a portfolio exhibit, not the site's own toolkit. Its components are styled
independently of the page sections.

That is a legitimate arrangement, but do not assume that changing a `src/ui`
component changes the site, and do not assume a page section can be refactored
onto `<Button>` without visual drift.

`.storybook/main.ts` globs `../src/ui/**/*.stories.@(ts|tsx)` **only** — a story
written next to a page or a `src/components/` piece will not be picked up.

## Conventions

- **Styling:** sibling `.scss`, imported `?inline`, rendered as
  `<style>{styles}</style>` inside the component's own JSX. Required by the
  Shadow DOM (above), not a preference.
- **Solid, not React:** `class` not `className`; `createSignal` /
  `createEffect` / `onMount` / `onCleanup`; props are reactive, so read
  `props.x` in the body rather than destructuring.
- Components are arrow-function exports; most are named exports.
- TypeScript is **loose** — no `strict`, `jsx: "preserve"`,
  `jsxImportSource: "solid-js"`. The `// @ts-ignore` above every `?inline` SCSS
  import is the established workaround for the missing module declaration.
- Static content is JSON in `src/data/` (`projects.json`, `experience.json`,
  `navbar.json`). `projects.json` is read by **both** the site and
  `fit-backend/crew.py` (which loads it from `../src/data`), so its shape is a
  cross-language contract.

## Dead and stale things (verified)

- `src/utils/checkExternalLink.js` — **not imported anywhere.**
- `src/images/hero-bg.jpg`, `src/images/skyscraper.jpg` — **not referenced from
  any `.tsx` or `.scss`.**
- `src/tsconfig.app.json` — a leftover stub. It lists
  `"files": ["main.ts", "polyfills.ts"]`, neither of which exists, and misspells
  `compilerOptions` as `compileOptions`. Nothing extends or references it.
- `@solidjs/router` is in `dependencies` and unused.
- `openspec/` holds an in-progress change proposal (`restore-cyan-palette`) and
  is **untracked** — not part of the published site.
- `docs/design/` and `docs/plans/` are dated design notes from June 2026. They
  record intent at the time, not current behavior. Where they disagree with this
  file, this file was checked against the code.
- Earlier versions of this repo had a Three.js animated background
  (`ThreeBackground`), an `About` page, `HeroArea`, `SocialMedia`, and a `page` /
  `setPage` signal for section switching. **All of them are gone** — `three` is
  not a dependency and none of those files exist. Documentation or comments
  referring to them are stale.
