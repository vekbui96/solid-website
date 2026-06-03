# Fit Analyzer — CrewAI backend

A multi-agent crew (CrewAI) that powers the site's "Think I'm a Good Fit?" feature
with a real LLM. The work is **delegated across six specialists**, each with a narrow
role, chained so every step builds on the last:

| # | Agent | Role | Delegates? |
|---|-------|------|-----------|
| 1 | **JD Interpreter** | Reads the posting like a hiring manager — infers seniority, real priorities, must-haves vs. nice-to-haves, unstated expectations. | no |
| 2 | **Requirements Analyst** | Normalizes the role into a clean requirement set. | no |
| 3 | **Evidence Mapper** | Grounds each requirement in Ve Bui's real corpus (`../src/data/projects.json` + `experience.json`), citing project ids. | no |
| 4 | **Gap Auditor** | Red-teams the mapping: downgrades thin "strong" claims, names the real gaps. Can delegate re-checks back to the Mapper. | yes |
| 5 | **Honest Fit Assessor** | Produces the calibrated `FitReport` JSON — score must be defensible from the audited evidence. | yes |
| 6 | **Pitch Strategist** | Rewrites only the headline + summary in Ve's voice, consistent with the score. | no |

The chain: `interpret → extract → map_evidence → audit → assess → pitch`.

Code is split so roles stay readable: **`agents.py`** (the roster), **`tasks.py`**
(the delegatable work + the `FitReport` schema), **`crew.py`** (wiring + CLI).

The final output matches the front-end contract in `../src/lib/fitAnalysis.ts`
(`FitReport`), so it drops straight into the existing UI.

> No vector DB: the corpus is small (~30 projects + roles), so the whole thing goes
> in the prompt. RAG here would be overkill — that's the deliberate engineering call.

## Two ways to run the crew

- **Sequential** (default) — the six tasks run step by step. Deterministic, cheaper,
  easy to reason about.
- **Hierarchical** — a seventh agent, the **Fit Analysis Lead**, delegates each step
  to the right specialist and owns the final report (it can re-delegate weak work).
  More autonomous, costs more tokens.

```bash
cd fit-backend
python -m venv .venv && .venv\Scripts\activate     # Windows
pip install -r requirements.txt
setx OPENAI_API_KEY "sk-..."                        # or ANTHROPIC_API_KEY

python crew.py "paste a job description here"                  # sequential
python crew.py --hierarchical "paste a job description here"   # delegating manager
```

## Wiring it to the site (next step)

The static site currently runs a deterministic in-browser matcher (`fitAnalysis.ts`).
To use this crew instead, expose it behind a small endpoint (FastAPI or a serverless
function) that returns the report JSON, then point the front-end at it — keeping the
client-side matcher as the offline/fallback path. The output shape already matches, so
the UI needs no changes beyond the fetch call.
