"""
Fit Analyzer — CrewAI multi-agent backend.

A real agent crew that powers the "Think I'm a Good Fit?" feature with an LLM.
Roles are delegated out across six specialists (see agents.py) working a chain
of tasks (see tasks.py):

    JD Interpreter -> Requirements Analyst -> Evidence Mapper
        -> Gap Auditor -> Honest Fit Assessor -> Pitch Strategist

Two ways to run the crew:
  * sequential   — the chain runs step by step (deterministic, cheaper).
  * hierarchical — a Fit Analysis Lead delegates each step and owns the result
                   (more autonomous; the manager can re-delegate weak work).

Output JSON matches the front-end contract in src/lib/fitAnalysis.ts (FitReport),
so it can drop into the existing UI once served behind an API.

Run:
    pip install -r requirements.txt
    setx OPENAI_API_KEY "sk-..."        # or ANTHROPIC_API_KEY + model="anthropic/claude-..."
    python crew.py "paste a job description here"
    python crew.py --hierarchical "paste a job description here"
"""

import json
import sys
from pathlib import Path

from crewai import Crew, Process

import agents as roster
from tasks import build_tasks

ROOT = Path(__file__).resolve().parent.parent / "src" / "data"


def load_corpus() -> str:
    """Assemble the (small) portfolio corpus — no vector DB needed at this scale."""
    projects = json.loads((ROOT / "projects.json").read_text(encoding="utf-8"))
    experience = json.loads((ROOT / "experience.json").read_text(encoding="utf-8"))
    return json.dumps({"projects": projects, "experience": experience}, indent=2)


def build_crew(hierarchical: bool = False) -> Crew:
    agents = {
        "jd_interpreter": roster.jd_interpreter(),
        "requirements_analyst": roster.requirements_analyst(),
        "evidence_mapper": roster.evidence_mapper(),
        "gap_auditor": roster.gap_auditor(),
        "fit_assessor": roster.fit_assessor(),
        "pitch_strategist": roster.pitch_strategist(),
    }
    tasks = build_tasks(agents)

    if hierarchical:
        # A manager agent delegates each task to the right specialist and owns
        # the final report. The manager is NOT listed in `agents`.
        return Crew(
            agents=list(agents.values()),
            tasks=tasks,
            process=Process.hierarchical,
            manager_agent=roster.fit_lead(),
            verbose=False,
        )

    return Crew(
        agents=list(agents.values()),
        tasks=tasks,
        process=Process.sequential,
        verbose=False,
    )


def main() -> None:
    args = sys.argv[1:]
    hierarchical = False
    if args and args[0] in ("--hierarchical", "-H"):
        hierarchical = True
        args = args[1:]

    jd = " ".join(args).strip() or sys.stdin.read().strip()
    if len(jd) < 12:
        print("Provide a job description as an argument or via stdin.")
        sys.exit(1)

    crew = build_crew(hierarchical=hierarchical)
    result = crew.kickoff(inputs={"job_description": jd, "corpus": load_corpus()})
    print(result)


if __name__ == "__main__":
    main()
