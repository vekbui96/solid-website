# Homepage Narrative Design Spec — "From Systems to Intelligence"

> Personal portfolio for Ve Bui — Full-Stack Software Engineer → AI Engineer / AI Solutions Architect.
> Target audience: engineering leaders, AI leaders, consulting firms, enterprise orgs.
> Quality bar: Stripe, Linear, Vercel, Anthropic, OpenAI, Ramp.
> Stack: SolidJS + Vite + SCSS (existing).

---

## 0. Design thesis

**The page is an argument, not a résumé.** Every résumé says "I did X." This page makes the reader *conclude*: "He understands software deeply, has full-stack range, and is now compounding that into AI systems." We never state the conclusion — we engineer the experience so the visitor arrives at it themselves. That is the core UX principle behind every decision below.

Three structural ideas carry the whole page:

1. **One evolving system diagram.** A single architecture diagram is introduced in Act 1 with a few nodes (Client → API → DB). As the visitor scrolls into Act 2, nodes animate in (frontend, queue, observability, CI/CD). In Act 3, an **agent/AI layer** materializes on top. The visitor literally watches a system — and a career — grow in sophistication. *Reasoning: it simultaneously demonstrates systems thinking, technical depth, and progression in one persistent, memorable object. Showing beats telling.*

2. **Theme progresses with the narrative.** The page is not one color scheme; it transitions across three "acts." This makes the scroll feel like forward motion and growth rather than a flat list. *Reasoning: color is the cheapest, most visceral signal of change; tying it to the story makes the metaphor felt, not read.*

3. **Pinned, chaptered scroll.** Each act is a scroll-pinned scene where copy animates in beats while the diagram updates. *Reasoning: pacing. We control the rate of information so the story lands; a free-scrolling wall of text cannot.*

---

## 1. Narrative architecture (the spine)

```
[0] HERO            — the thesis in one line; the system diagram seeds here
[1] ACT I  BACKEND  — "It started with the backend." Foundations.
[2] ACT II FULL-STACK — "Then I owned the whole product." Range.
[3] ACT III AI      — "Now I build systems that think alongside people." The arrival.
[4] PROOF / PROJECTS — 3 flagship AI systems, presented as case studies.
[5] CAPABILITIES    — the systems-thinking matrix (scannable depth).
[6] CLOSE / CTA     — "Let's build intelligent systems together."
[7] FOOTER          — contact, links, quiet.
```

Bookends (Hero + Close) state the promise and the ask. The three acts are the proof of growth. Projects are the evidence. Capabilities is the skim layer for skeptical senior readers. This ordering moves the reader from *hook → story → proof → reassurance → action* — the canonical persuasion arc.

---

## 2. Full wireframe, top to bottom (with exact copy)

Notation: `H1/H2` = headline level, `▸` = animation beat, `⟦…⟧` = visual element.

### [0] HERO — "The thesis"

```
┌───────────────────────────────────────────────────────────────┐
│  Ve Bui ·                       Work   Story   Systems   Contact│  ← thin sticky nav
│                                                                 │
│   FULL-STACK ENGINEER → AI SYSTEMS                              │  ← eyebrow, mono, accent
│                                                                 │
│   I build software systems                                     │  ← H1, huge, -0.03em
│   that think.                                                  │
│                                                                 │
│   Six years across backend, full-stack, and cloud —            │  ← subhead, muted
│   now architecting AI agents and enterprise AI solutions.      │
│                                                                 │
│   [ See what I build → ]   [ Read the story ]                  │  ← primary + ghost CTA
│                                                                 │
│        ⟦ minimal seed diagram: ( ) → [API] → [DB] ⟧            │  ← right / below, faint, animated
└───────────────────────────────────────────────────────────────┘
```

- **Headline:** "I build software systems that think." — short, declarative, memorable; "think" foreshadows AI without naming it yet.
- **Subhead:** "Six years across backend, full-stack, and cloud — now architecting AI agents and enterprise AI solutions."
- **CTAs:** primary `See what I build →` (jumps to Projects), secondary `Read the story` (smooth-scrolls into Act I).
- **Visual:** the seed of the evolving diagram — 3 nodes, hairline edges, drawn on with `stroke-dashoffset`. A single packet dot travels Client→API→DB on a slow loop.
- **▸ Motion:** headline lines rise + fade (staggered 60ms), subhead follows, CTAs last. Diagram draws in over ~1.2s. Subtle pointer-parallax on the diagram (≤6px).
- **UX reasoning:** Above the fold must do three jobs in 5 seconds — say *what* you are, *prove* you think in systems (the diagram), and offer two intents (skimmers click Work, storyreaders scroll). The diagram seed creates an open loop the reader wants to see resolve.

---

### [1] ACT I — BACKEND · "Foundations"

Layout: **two-column pinned scene.** Left = narrative copy (sticky, animates in beats). Right = the system diagram, now centered on the backend.

```
┌──────────────────────────┬────────────────────────────────────┐
│  01 — FOUNDATIONS         │                                     │
│                           │     ⟦  [Client]                     │
│  It started with          │          │                          │
│  the backend.             │        [ API / Services ]           │
│                           │        ╱     │      ╲                │
│  APIs, services,          │   [Auth]  [Queue]  [Postgres]       │
│  integrations, and the    │                                     │
│  data systems that keep   │     (nodes draw in on scroll)       │
│  everything running.      │                                     │
│                           │                                     │
│  ▸ system design          │   ⟦ caption, mono: ⟧                │
│  ▸ scalability            │   "designed for throughput,         │
│  ▸ reliability            │    indexed for reliability"         │
│                           │                                     │
│  Focused on building      │                                     │
│  software that works.     │  ← punchline, larger weight         │
└──────────────────────────┴────────────────────────────────────┘
```

- **Headline:** "It started with the backend."
- **Body:** "APIs, services, integrations, and the data systems that keep everything running. I learned to think in system design, scalability, and reliability — the disciplines that decide whether software survives contact with production."
- **Beat list (animate in sequentially):** System design · Scalability · Reliability · Architecture.
- **Punchline:** "Focused on building software that **works**."
- **Visual:** diagram resolves to a clean backend topology (Client → API → Auth/Queue/DB). Edges animate as the reader hits each beat.
- **▸ Motion:** copy beats reveal on scroll (IntersectionObserver, 1 beat per ~15vh). Diagram nodes pop in (scale 0.9→1, 200ms) synced to beats. Theme here: cool slate, structural, a faint dotted "blueprint" grid in the background.
- **Transition out:** the grid background lightens and the diagram *does not reset* — it persists and will gain nodes. A hairline progress rail on the left fills 1/3.
- **UX reasoning:** Starting at the foundation earns credibility with engineering leaders before any AI claim. The persistent diagram is the thread that makes "growth" legible. "Software that works" is deliberately humble — it sets up the escalation.

---

### [2] ACT II — FULL-STACK · "Range"

Layout: same pinned two-column, but the **palette warms** and a product UI motif joins the diagram.

```
┌──────────────────────────┬────────────────────────────────────┐
│  02 — RANGE               │   ⟦ diagram GAINS nodes: ⟧          │
│                           │   [Web App] ─┐                      │
│  Then I owned             │   [Mobile]  ─┼─ [API] ─ [DB]        │
│  the whole product.       │              │     │                │
│                           │        [CI/CD]  [Observability]     │
│  Frontend to infra —      │                                     │
│  building complete         │   ⟦ a tiny product UI card fades   │
│  products, not just        │     in beside the frontend node ⟧  │
│  endpoints.               │                                     │
│                           │                                     │
│  ▸ frontend & UX          │                                     │
│  ▸ testing                │                                     │
│  ▸ observability          │                                     │
│  ▸ cloud                  │                                     │
│                           │                                     │
│  Focused on building      │                                     │
│  software people          │                                     │
│  enjoy using.             │                                     │
└──────────────────────────┴────────────────────────────────────┘
```

- **Headline:** "Then I owned the whole product."
- **Body:** "I expanded into frontend and product, working end-to-end across UI, testing, observability, and cloud. I stopped shipping endpoints and started shipping experiences."
- **Beats:** Frontend & UX · Testing · Observability · Cloud.
- **Punchline:** "Focused on building software people **enjoy using**."
- **Visual:** the diagram *grows* — frontend clients, CI/CD, and observability nodes animate in and wire up to the existing backend. A small, real-looking product card materializes (mini dashboard) to signal UX sensibility.
- **▸ Motion:** new edges draw from old nodes (continuity = growth). Palette crossfades from slate to a brighter, slightly indigo light. Progress rail → 2/3.
- **UX reasoning:** The escalation from "works" → "enjoy using" signals maturity (you now think about humans, not just machines). Growing the *same* diagram rather than showing a new one is the whole thesis: range built on foundations.

---

### [3] ACT III — AI · "The arrival"

Layout: **the page goes premium-dark here.** This is the emotional peak. The diagram gains an AI layer that sits *above* the system, observing and acting on it.

```
┌───────────────────────────────────────────────────────────────┐
│  (full-bleed dark scene, luminous accent)                      │
│                                                                 │
│   03 — INTELLIGENCE                                            │
│                                                                 │
│   Now I build systems that                                     │
│   think alongside people.                                      │
│                                                                 │
│        ⟦ AI layer glows ABOVE the full system: ⟧               │
│        ┌───────────  AI / Agents  ───────────┐                 │
│        │  reason · retrieve · act · automate  │   ← pulsing     │
│        └───┬─────────────┬──────────────┬─────┘                 │
│            ▼             ▼              ▼                        │
│        [the entire Act-II system, now dimmed beneath]          │
│                                                                 │
│   AI agents, RAG, and workflow automation that help teams      │
│   think, decide, and ship faster.                              │
│                                                                 │
│   Focused on systems that help people think, decide, and work. │
└───────────────────────────────────────────────────────────────┘
```

- **Headline:** "Now I build systems that think alongside people."
- **Body:** "I build AI agents, retrieval-augmented generation systems, workflow automation, and enterprise AI solutions — software that amplifies engineering teams and business outcomes."
- **Punchline:** "Focused on building systems that help people **think, decide, and work more effectively**."
- **Visual:** an "AI / Agents" plane illuminates above the full stack, with downward connections into the system (it reads from observability, acts on services). Soft glow, animated dashed data-flow lines pulsing upward (retrieval) and downward (action).
- **▸ Motion:** background transitions to near-black (#0B0E14) as this section enters viewport (driven by scroll position). Accent shifts to a luminous cyan/violet. Data-flow lines animate continuously. Progress rail → 3/3 and dissolves.
- **Transition:** the dark holds through the Projects section (projects are "AI systems," so the dark frame contextualizes them as the payoff), then resolves back to light for the calm CTA.
- **UX reasoning:** The theme inversion makes Act III feel like *arrival* and gives the AI work gravity and focus (dark = depth, "the lab"). Placing AI *above and connected to* the full system — not replacing it — visually argues your differentiator: AI grounded in real engineering, not hype.

---

### [4] PROOF — PROJECTS (3 flagship AI systems)

Presented as **case-study cards**, not a gallery. Each is a small story: Problem → System → Outcome, with a schematic architecture diagram. Stays in the dark theme.

```
┌───────────────────────────────────────────────────────────────┐
│  SELECTED SYSTEMS                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ 01  Enterprise Operations Copilot                         │ │
│  │     Natural-language ops over fragmented enterprise data. │ │
│  │     ⟦ mini arch diagram: chat → orchestrator → tools/RAG  │ │
│  │       → systems of record ⟧                               │ │
│  │     Problem · Approach · Impact   [ View breakdown → ]     │ │
│  └─────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ 02  AI Incident Commander                                 │ │
│  │     Detects, triages, and narrates incidents in real time.│ │
│  │     ⟦ alerts → reasoning loop → runbooks → comms ⟧        │ │
│  └─────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ 03  AI Codebase Onboarding Agent                          │ │
│  │     Turns a repo into an interactive mentor.              │ │
│  │     ⟦ repo index → graph + RAG → guided Q&A ⟧             │ │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

**Showcase strategy (UX reasoning):**
- **Three, not ten.** Senior audiences value editorial restraint; three flagship systems read as "principal," ten reads as "junior with side projects."
- **Each card is Problem → System → Outcome.** This is how leaders evaluate engineers: can you frame a problem, design a system, and tie it to impact? Lead with the problem (business), not the tech.
- **Schematic diagrams, not screenshots.** Diagrams communicate *systems thinking* and never look unfinished or fake; product screenshots of internal/conceptual tools tend to look thin. Keep them as clean node-edge SVGs with mono labels, matching the hero diagram language.
- **Copy per card (recommended):**
  - **Enterprise Operations Copilot** — *Problem:* "Ops teams drown in fragmented systems and tribal knowledge." *System:* "An agentic copilot that plans across tools, retrieves grounded context (RAG), and executes guarded actions against systems of record." *Impact:* frame as time-to-answer / fewer escalations.
  - **AI Incident Commander** — *Problem:* "During incidents, humans waste minutes correlating signals." *System:* "An agent that ingests alerts, reasons over telemetry and runbooks, drafts the incident timeline, and coordinates comms." *Impact:* MTTR reduction / cleaner postmortems.
  - **AI Codebase Onboarding Agent** — *Problem:* "New engineers take weeks to get productive in large codebases." *System:* "Indexes the repo into a graph + vector store and serves a guided, conversational mentor that answers 'where/why/how' with citations." *Impact:* faster ramp / fewer interrupt questions.
- **Interaction:** cards reveal on scroll (staggered), lift on hover, and the mini-diagram animates its data flow when the card enters view. `View breakdown →` expands an inline case study (or routes to a detail page in v2).

---

### [5] CAPABILITIES — "The skim layer"

A calm, scannable matrix for the reader who skipped the story and wants proof of depth. Back in light theme.

```
SYSTEMS I CAN OWN END-TO-END
─────────────────────────────────────────────────────────────
Backend & APIs      Java · Spring Boot · REST · Clojure
Data & Storage      PostgreSQL · schema design · query perf
Cloud & Infra       AWS · CI/CD · observability · on-call
Frontend            TypeScript · SolidJS · micro-frontends
AI Systems          Agents · RAG · workflow automation · evals
```

- **Headline:** "Systems I can own end-to-end."
- **UX reasoning:** Story-first pages can frustrate evaluators who need facts fast. This section is the "exit ramp to proof." Grouping by *system layer* (not an alphabetized skill cloud) reinforces systems thinking one more time. Keep it boring on purpose — it builds trust through legibility.

---

### [6] CLOSE — CTA

```
┌───────────────────────────────────────────────────────────────┐
│        Let's build intelligent systems together.              │
│                                                                 │
│   I help teams turn deep engineering into AI that delivers     │
│   measurable outcomes.                                         │
│                                                                 │
│        [ Get in touch → ]      [ View résumé ]                 │
│                                                                 │
│   ⟦ the full evolved diagram returns, calm, as a quiet motif ⟧ │
└───────────────────────────────────────────────────────────────┘
```

- **Headline:** "Let's build intelligent systems together."
- **Sub:** "I help teams turn deep engineering into AI that delivers measurable outcomes."
- **CTAs:** primary `Get in touch →` (mailto / contact), secondary `View résumé` (PDF).
- **UX reasoning:** One primary action, stated as collaboration ("together") to appeal to leaders and consulting/enterprise buyers who hire for partnership. The returning diagram closes the open loop from the hero — narrative symmetry = memorability.

---

### [7] FOOTER

Quiet: name · email (`tommy.bui1428@gmail.com`) · GitHub (`vekbui96`) · LinkedIn (`in/vekbui96`) · location (Dallas, TX) · "Built with SolidJS." No heavy nav.

---

## 3. Design system

### 3.1 Color — a progressing palette

A shared neutral spine plus three act-accents. Implemented as CSS custom properties that crossfade by scroll/section.

| Token | Light base (Acts I–II, Caps, CTA) | Dark scene (Act III + Projects) |
|---|---|---|
| `--bg` | `#FFFFFF` → `#F7F8FA` | `#0B0E14` |
| `--surface` | `#F8FAFC` | `#121723` |
| `--text` | `#0B1220` | `#E6EAF2` |
| `--muted` | `#5B6577` | `#8B95A7` |
| `--border` | `#E5E8EE` | `#222A38` |
| `--accent` (Act I) | `#2563EB` (engineer blue) | — |
| `--accent` (Act II) | `#4F46E5` (indigo, product) | — |
| `--accent` (Act III) | — | `#22D3EE` → `#A78BFA` (luminous cyan→violet) |

- **Reasoning:** A single neutral spine keeps the page cohesive and premium (à la Linear/Vercel); the *accent* is the storyteller. Blue (trust/engineering) → indigo (craft/product) → luminous cyan/violet (intelligence/energy) tracks the narrative. The dark Act III is the only full inversion, reserved for maximum impact.
- Keep saturation low except for the AI accent — restraint reads as senior. One accent live at a time; never a rainbow.

### 3.2 Typography

- **Display / headlines:** a modern grotesk — **Inter Display**, **Söhne**, or **Geist** (Vercel's). Tight tracking on large sizes (`-0.02em` to `-0.03em`), weight 600–700.
- **Body:** same family at 300–400, 16–18px, line-height 1.6–1.75.
- **Mono accent:** **JetBrains Mono** / **Geist Mono** for eyebrows, diagram labels, captions, and section numbers (`01 — FOUNDATIONS`).
- **Scale (desktop):** Hero H1 64–84px · Act H2 40–56px · Card title 20–22px · Body 17px · Eyebrow/mono 12–13px (uppercase, letter-spacing 0.08em).
- **Reasoning:** Grotesk + mono is the visual signature of premium engineering brands (Vercel, Linear, Stripe docs). Mono labels signal "this person ships" and tie the copy to the diagrams. Big, tightly-tracked display type is what makes a page feel "designed" rather than templated. *(Current site uses Roboto — upgrading to Inter/Geist is a meaningful premium uplift; called out as a decision.)*

### 3.3 Layout & spacing

- **Content max-width 1100–1200px**, generous gutters; narrative copy column capped ~50ch for readability.
- **8px spacing system**; section vertical rhythm 120–160px desktop / 72–88px mobile.
- **Two-column pinned scenes** for the three acts (copy sticky, diagram animates). Collapses to single column on mobile with the diagram above the copy and simplified animation.
- **Reasoning:** Whitespace is the cheapest luxury signal. The pinned two-column pattern is the proven device for "scrollytelling" (Stripe, Apple) — it decouples reading pace from scroll distance.

### 3.4 Motion principles

- **Easing:** `cubic-bezier(0.22, 1, 0.36, 1)` (gentle overshoot) for entrances; `ease-out` for micro-interactions.
- **Durations:** micro 120–200ms · reveals 400–600ms · diagram draw 800–1200ms.
- **Choreography:** stagger related elements 40–80ms; never animate everything at once.
- **Restraint:** motion clarifies the story (reveal, draw, flow) — no gratuitous spin/bounce.
- **`prefers-reduced-motion`:** all scroll-driven motion degrades to instant reveals; data-flow loops pause. Non-negotiable.
- **Reasoning:** Premium = confident and calm. The diagram animations *carry meaning* (a system being built), which justifies their presence; decorative motion would cheapen it.

---

## 4. Scroll & animation — technical approach (SolidJS)

- **Reveals:** `IntersectionObserver` wrapped in a small Solid directive (`use:reveal`) toggling a `.in-view` class. Cheap, dependency-free, SSR-safe.
- **Pinned scenes / progress:** native **CSS scroll-driven animations** (`animation-timeline: view()` / `scroll()`) where supported, with an IntersectionObserver fallback. Avoids a heavy scroll library.
- **Diagram:** hand-authored **SVG** with `stroke-dasharray/offset` draw-on; animated `<circle>` packets via CSS `offset-path` or a tiny `requestAnimationFrame` loop. Nodes are Solid components so the *same* diagram instance gains children across acts (`<For>` over a growing node set keyed to scroll act).
- **Theme transition:** a scroll-position signal sets `data-act="1|2|3"` on the root; CSS variables transition with `transition: background-color 600ms, color 600ms`.
- **If a motion lib is wanted:** `@motionone/solid` (tiny) for spring reveals — optional, keep the bundle lean (current bundle is ~25KB; budget < 60KB JS).
- **Reasoning:** The existing site is featherweight after removing Three.js; preserve that. Native scroll-driven CSS + IO is the modern, performant path and keeps it premium without a 100KB animation framework.

---

## 5. Presenting architecture diagrams

- **One visual language** across hero, acts, and project cards: hairline edges, rounded-rect nodes, mono labels, generous spacing, max ~7 nodes per view.
- **Schematic, not literal.** Boxes-and-arrows of *roles* (API, RAG, Orchestrator, Systems of Record), never cluttered infra screenshots.
- **Animate flow, not decoration:** dashed lines with marching ants show data/agent flow; direction encodes meaning (retrieval up, action down in Act III).
- **Label in mono, describe in caption.** Each diagram gets a one-line mono caption ("designed for throughput, indexed for reliability").
- **Accessibility:** diagrams are SVG with `<title>`/`<desc>` and an adjacent text summary; never information-only-in-motion.
- **Reasoning:** Consistent diagram grammar is itself a credibility signal (you think in systems and communicate them clearly) and is the single most differentiating visual choice for this audience.

---

## 6. CTA strategy

- **Two intents, everywhere they matter:** "See what I build" (proof) and "Get in touch" (action). Hero offers both; Close commits to one primary.
- **Sticky nav** keeps `Contact` reachable at all times (low-friction for a leader who decides early).
- **Language is collaborative and outcome-oriented** ("build … together", "measurable outcomes") — speaks to hiring managers, consulting firms, and enterprise buyers, not recruiters scanning keywords.
- **No popups, no newsletter.** Premium restraint; the audience hates friction.
- **Reasoning:** B2B/leadership audiences convert on clarity and confidence, not urgency tactics. One strong primary CTA outperforms many competing ones.

---

## 7. Accessibility & performance guardrails

- WCAG AA contrast in *both* light and dark acts (verify the dark cyan/violet on `#0B0E14`).
- Full keyboard nav; visible focus rings; nav buttons are real `<button>`/`<a>`.
- `prefers-reduced-motion` fully supported (reveals instant, loops paused).
- Performance budget: LCP < 2.0s, JS < 60KB gz, no layout shift from reveals (reserve space). Lazy-init diagram animations via IO.
- Semantic landmarks: `header`, `main`, `section` per act with `aria-labelledby`, `footer`.

---

## 8. Recommended build phasing (maps to existing Solid app)

1. **Design tokens + type:** add Inter/Geist + JetBrains Mono; introduce the progressing CSS-variable theme on `.site` with `data-act`.
2. **Static narrative skeleton:** Hero + 3 acts + Projects + Capabilities + CTA with real copy, no motion. Verify the *story* reads first.
3. **Reveal layer:** `use:reveal` IntersectionObserver entrances.
4. **The evolving diagram:** build the SVG node system; wire node growth to act.
5. **Act III theme inversion + data-flow animation.**
6. **Project case-study cards + mini diagrams.**
7. **Reduced-motion + a11y + perf pass.**
8. **Polish:** parallax, packet animations, micro-interactions.

Each phase is shippable; the page is presentable after phase 2 and premium by phase 5.

---

## Appendix — copy block (paste-ready)

- **Hero H1:** I build software systems that think.
- **Hero sub:** Six years across backend, full-stack, and cloud — now architecting AI agents and enterprise AI solutions.
- **Act I H2:** It started with the backend. · *works.*
- **Act II H2:** Then I owned the whole product. · *enjoy using.*
- **Act III H2:** Now I build systems that think alongside people. · *think, decide, and work more effectively.*
- **Projects header:** Selected systems.
- **Capabilities header:** Systems I can own end-to-end.
- **Close H2:** Let's build intelligent systems together.
