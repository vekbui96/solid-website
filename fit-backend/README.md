# Fit Analyzer — CrewAI backend

A multi-agent crew (CrewAI) that powers the site's "Think I'm a Good Fit?" feature
with a real LLM. Three agents run sequentially:

1. **Requirements Analyst** — extracts the role's requirements from a job description.
2. **Evidence Mapper** — grounds each requirement in Ve Bui's real portfolio corpus
   (`../src/data/projects.json` + `experience.json`), citing project ids.
3. **Honest Fit Assessor** — emits a calibrated, transparent `FitReport` JSON that
   matches the front-end contract in `../src/lib/fitAnalysis.ts`.

> No vector DB: the corpus is small (~30 projects + roles), so the whole thing goes
> in the prompt. RAG here would be overkill — that's the deliberate engineering call.

## Run locally

```bash
cd fit-backend
python -m venv .venv && .venv\Scripts\activate     # Windows
pip install -r requirements.txt
setx OPENAI_API_KEY "sk-..."                        # or ANTHROPIC_API_KEY
python crew.py "paste a job description here"
```

## Wiring it to the site (next step)

The static site currently runs a deterministic in-browser matcher (`fitAnalysis.ts`).
To use this crew instead, expose it behind a small endpoint (FastAPI or a serverless
function) that returns the report JSON, then point the front-end at it — keeping the
client-side matcher as the offline/fallback path. The output shape already matches, so
the UI needs no changes beyond the fetch call.
