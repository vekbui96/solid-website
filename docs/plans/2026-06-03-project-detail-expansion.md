# Project Detail Expansion — Plan

> Goal: make the project deep-dives richer without fabricating facts or touching the card component (it already renders flow / problem / highlights / challenges / features / examples / takeaway / skills).

## Approach
Data-only enrichment of `src/data/projects.json`:

1. **Problem framing** — add a concise `problem` to the ~14 projects that lack one (honest framing of the business/engineering problem, no invented metrics).
2. **Architecture flow** — add a `flow` pipeline to projects that have a clear implied pipeline but no diagram yet (so the expanded card shows the chip flow).
3. **"Why it matters" takeaway** — add a `takeaway` to ~10 standout projects (RLS, JSONB migration, OAuth, Observability, Gateway Timeout, Context Engineering, AI Eval, Workflow Agents, Incident Commander, Campaign Builder) to give them senior-level framing.

Flagships (Ops Copilot, Codebase Intelligence, Spec-Driven Harness) are already deep — left as-is.

## Guardrails
- No new metrics or claims beyond what the user provided; additions are framing/structure only.
- `problem`/`flow` only added where missing (never overwrite existing content).
- Owner should review wording for accuracy.

## Steps
1. Run an idempotent enrich script over `projects.json`.
2. Validate JSON + `yarn build`.
3. Spot-check an enriched card in-browser.
4. Commit, push, deploy.
