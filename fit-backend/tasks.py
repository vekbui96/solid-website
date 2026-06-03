"""
The work, broken into delegatable tasks.

Each task is owned by one specialist and consumes the output of the steps before
it via `context=[...]`. The chain is:

    interpret -> extract -> map_evidence -> audit -> assess -> pitch

The final report shape matches the front-end contract in
`../src/lib/fitAnalysis.ts` (FitReport), so the output drops straight into the UI.
"""

from crewai import Task


# Strict JSON shape the UI expects. Kept in one place so the assessor and the
# pitch step agree on it.
REPORT_SCHEMA = (
    '{"matchScore": int 0-100, "bin": "weak|moderate|strong|excellent", '
    '"headline": str, "scoreRationale": str, '
    '"strengths": [{"title": str, "detail": str, "projectIds": [str]}], '
    '"requirements": [{"text": str, "confidence": "strong|partial|limited", '
    '"evidence": [{"projectId": str, "note": str}]}], '
    '"gaps": [{"area": str, "note": str}], "summary": str}'
)


def build_tasks(agents: dict) -> list:
    interpret = Task(
        description="Job description:\n\n{job_description}\n\n"
        "Read it as a hiring manager. Infer the true seniority level, the team's top "
        "3-5 priorities, which items are hard requirements vs. nice-to-haves, and any "
        "unstated expectations. Be concise.",
        expected_output="A short brief: inferred seniority, ranked priorities, "
        "must-haves vs. nice-to-haves, and unstated expectations.",
        agent=agents["jd_interpreter"],
    )

    extract = Task(
        description="Using the interpreter's brief and the original JD, produce a "
        "normalized requirement set: required_skills, technologies, responsibilities, "
        "leadership_expectations, domain_knowledge, ai_capabilities.",
        expected_output="A structured list of the role's requirements, grouped by category.",
        agent=agents["requirements_analyst"],
        context=[interpret],
    )

    map_evidence = Task(
        description="Portfolio corpus (projects + experience) as JSON:\n\n{corpus}\n\n"
        "For each requirement, find supporting projects (by id) and experience. Rate each "
        "requirement strong / partial / limited based strictly on the evidence present.",
        expected_output="Requirement -> evidence mapping with project ids and a "
        "strong/partial/limited confidence on each.",
        agent=agents["evidence_mapper"],
        context=[extract],
    )

    audit = Task(
        description="Adversarially review the evidence mapping. For every 'strong' that "
        "rests on thin or tangential evidence, downgrade it and explain why. Identify the "
        "genuine gaps a skeptical interviewer would probe. If a claim needs re-checking, "
        "delegate back to the Evidence Mapper.",
        expected_output="The corrected requirement->evidence mapping plus an explicit list "
        "of genuine gaps.",
        agent=agents["gap_auditor"],
        context=[map_evidence],
    )

    assess = Task(
        description="Using the audited mapping and gaps, produce the final assessment as "
        "STRICT JSON (no prose outside JSON) matching this shape:\n" + REPORT_SCHEMA + "\n"
        "Calibrate honestly: poor fits score low; the matchScore must be defensible from "
        "the audited evidence; always include the audited gaps. Leave headline and summary "
        "as short placeholders — the Pitch Strategist will finalize them.",
        expected_output="A single JSON object matching the FitReport contract.",
        agent=agents["fit_assessor"],
        context=[audit],
    )

    pitch = Task(
        description="Take the assessor's JSON and rewrite ONLY the `headline` and "
        "`summary` fields in Ve Bui's voice — confident but honest, and fully consistent "
        "with the matchScore, bin, and gaps. Do not change any other field, any score, or "
        "any evidence. Return the complete, updated JSON object and nothing else.",
        expected_output="The final FitReport JSON with a polished headline and summary.",
        agent=agents["pitch_strategist"],
        context=[assess],
    )

    return [interpret, extract, map_evidence, audit, assess, pitch]
