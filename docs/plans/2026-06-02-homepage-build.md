# Homepage Narrative — Build Plan

> Executes `docs/design/2026-06-02-homepage-narrative-design.md`.
> Stack: SolidJS + Vite + SCSS. Verify each phase via `yarn build` + Playwright screenshot. Commit/push per phase. Deploy when a phase is presentable.

**Target architecture:** the **Home** tab becomes the long-scroll narrative homepage (Hero → Act I → Act II → Act III → Projects → Capabilities → Close). Existing Experience/About/Projects tabs stay during the build; nav is reconciled into single-page anchor scroll in Phase 6.

---

## Phase 1 — Design tokens + typography  ✅ presentable: no
- Load Inter + JetBrains Mono in `index.html` (replace Roboto).
- `src/index.scss`: define light tokens on `.site` and dark tokens under `.site[data-act="3"]` / a `.scene-dark` class; base type (display vs mono), heading scale helpers.
- No content change yet beyond font swap.
- Verify: existing pages still render with new type.

## Phase 2 — Static narrative skeleton (story-first, no motion)  ✅ presentable: yes
- Rewrite `src/pages/Home/Home.tsx` + `Home.scss` with ALL sections, real copy from the spec appendix, full visual hierarchy, and **simple static SVG diagrams** per act.
- Act III rendered as a static dark full-bleed `.scene-dark` section; Projects section also dark.
- Projects = 3 case-study cards (Problem/System/Outcome), qualitative impact placeholders.
- Capabilities = system-layer matrix. Close = CTA. Footer.
- Verify: screenshot desktop + mobile; confirm the story reads top-to-bottom. **Deploy after this phase.**

## Phase 3 — Reveal layer
- `use:reveal` IntersectionObserver directive → `.in-view` entrance transitions (respect `prefers-reduced-motion`).

## Phase 4 — Evolving system diagram
- SVG node system; nodes grow across acts (backend → +frontend/observability → +AI layer). Shared diagram grammar reused in project cards.

## Phase 5 — Act III theme inversion on scroll + data-flow animation
- Scroll-position signal sets `data-act` on root; CSS-variable crossfade; marching-ants data flow in the AI layer.

## Phase 6 — Nav reconciliation (single-page anchor scroll)
- Convert nav to anchor links (Work / Story / Systems / Contact) with smooth scroll; retire redundant tabs or repurpose.

## Phase 7 — Project case-study detail (optional v2)
- Expandable inline breakdowns or detail routes.

## Phase 8 — A11y + performance + polish
- Contrast (light+dark), focus rings, reduced-motion, LCP<2s, JS<60KB; parallax/packet micro-interactions.

---

### Decisions taken
- Typography: **Inter** (display+body) + **JetBrains Mono** (eyebrows/labels). Was Roboto.
- Project impact: **qualitative** until real metrics provided (no invented numbers).
- Home tab hosts the narrative; tab→anchor reconciliation deferred to Phase 6.
