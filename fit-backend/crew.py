"""
Fit Analyzer — CrewAI multi-agent backend.

A real agent crew that powers the "Think I'm a Good Fit?" feature with an LLM:
a Requirements Analyst extracts the role's needs, an Evidence Mapper grounds
them in Ve Bui's real portfolio corpus, and an Honest Fit Assessor produces a
calibrated, transparent report (low fits score low; gaps are surfaced).

Output JSON matches the front-end contract in src/lib/fitAnalysis.ts (FitReport),
so it can drop into the existing UI once served behind an API.

Run:
    pip install -r requirements.txt
    setx OPENAI_API_KEY "sk-..."        # or ANTHROPIC_API_KEY + model="anthropic/claude-..."
    python crew.py "paste a job description here"
"""

import json
import sys
from pathlib import Path

from crewai import Agent, Task, Crew, Process

ROOT = Path(__file__).resolve().parent.parent / "src" / "data"


def load_corpus() -> str:
    """Assemble the (small) portfolio corpus — no vector DB needed at this scale."""
    projects = json.loads((ROOT / "projects.json").read_text(encoding="utf-8"))
    experience = json.loads((ROOT / "experience.json").read_text(encoding="utf-8"))
    return json.dumps({"projects": projects, "experience": experience}, indent=2)


def build_crew() -> Crew:
    analyst = Agent(
        role="Requirements Analyst",
        goal="Extract the concrete requirements, technologies, responsibilities, "
        "leadership expectations, and AI capabilities from a job description.",
        backstory="A precise technical recruiter who turns prose into a clean requirement set.",
        verbose=False,
    )
    mapper = Agent(
        role="Evidence Mapper",
        goal="Map each extracted requirement to specific projects and roles in Ve Bui's "
        "portfolio corpus, citing project ids as evidence. Mark requirements with no "
        "supporting evidence as 'limited'.",
        backstory="An engineer who reads systems carefully and refuses to claim what isn't there.",
        verbose=False,
    )
    assessor = Agent(
        role="Honest Fit Assessor",
        goal="Produce a calibrated, transparent fit report. A trustworthy 'moderate' beats an "
        "inflated 'excellent'. Always surface gaps. Never fabricate metrics.",
        backstory="A staff engineer who values candor; recruiters trust their assessments.",
        verbose=False,
    )

    extract = Task(
        description="Job description:\n\n{job_description}\n\n"
        "Extract a normalized requirement set: required_skills, technologies, "
        "responsibilities, leadership_expectations, domain_knowledge, ai_capabilities.",
        expected_output="A structured list of the role's requirements.",
        agent=analyst,
    )
    map_evidence = Task(
        description="Portfolio corpus (projects + experience) as JSON:\n\n{corpus}\n\n"
        "For each requirement from the previous step, find supporting projects (by id) and "
        "experience. Rate each requirement strong / partial / limited based on the evidence.",
        expected_output="Requirement -> evidence mapping with project ids and confidence.",
        agent=mapper,
        context=[extract],
    )
    assess = Task(
        description="Using the requirement->evidence mapping, produce the final report as STRICT "
        "JSON matching this shape (no prose outside JSON):\n"
        '{"matchScore": int 0-100, "bin": str, "headline": str, "scoreRationale": str, '
        '"strengths": [{"title": str, "detail": str, "projectIds": [str]}], '
        '"requirements": [{"text": str, "confidence": "strong|partial|limited", '
        '"evidence": [{"projectId": str, "note": str}]}], '
        '"gaps": [{"area": str, "note": str}], "summary": str}\n'
        "Calibrate honestly: poor fits score low; always include gaps.",
        expected_output="A single JSON object matching the FitReport contract.",
        agent=assessor,
        context=[map_evidence],
    )

    return Crew(agents=[analyst, mapper, assessor], tasks=[extract, map_evidence, assess],
                process=Process.sequential, verbose=False)


def main() -> None:
    jd = " ".join(sys.argv[1:]).strip() or sys.stdin.read().strip()
    if len(jd) < 12:
        print("Provide a job description as an argument or via stdin.")
        sys.exit(1)
    result = build_crew().kickoff(inputs={"job_description": jd, "corpus": load_corpus()})
    print(result)


if __name__ == "__main__":
    main()
