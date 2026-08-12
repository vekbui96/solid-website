---
name: tailor-resume
description: Tailor one of Ve's baseline resumes to a specific job description — rewrite bullet points, reorder and extend the skills section, and mirror the posting's vocabulary for ATS matching. Use whenever a job description, posting URL, or "apply to this role" request appears alongside a request to adjust, tailor, customize, or rewrite a resume or CV. Never alters employers, titles, or dates.
---

# Tailor Resume

Turn a baseline resume into a targeted one for a specific posting. The job history is fixed; the
*framing* of that history is what gets tuned.

## Inputs

**Job description** — pasted text, a file, or a URL (fetch it). If only a company + role name is
given, ask for the actual posting text. Do not tailor against a guess at what the role wants.

**Baseline resumes** — look in this order, stop at the first hit:

1. A path the user names in the request
2. `$RESUME_DIR`
3. `./resumes/`
4. `~/resumes/`

If none exist, ask where the baselines live. Never reconstruct a resume from memory or from
another conversation — always read the actual file.

## Hard rules

These are not style preferences. Breaking one produces a document that fails a reference check.

**Never change, and never add to:**

- Employer names, job titles, employment dates, locations, employment type
- Schools, degrees, graduation dates, GPA
- Certifications, licenses, clearances
- Any number describing outcome or scope — percentages, dollar amounts, latency figures, user
  counts, team sizes, request volumes

A metric may be *moved*, *reworded*, or *dropped*. It may never be invented, inflated, or
reattached to a different accomplishment than the one it came from.

**Free to change:**

- Bullet wording, ordering, and emphasis within a role
- How many bullets a role gets (compress older/irrelevant roles to buy space)
- The skills section — grouping, ordering, and additions
- Summary/objective line, if the baseline has one
- Project selection and framing

**Adding skills:** Ve has confirmed broad language and tooling knowledge beyond what any single
baseline lists, so adding a skill is permitted. But every added skill that appears in *no* baseline
resume goes in the "Confirm before sending" list in the change report. Do not skip this — it is the
only check between an added keyword and being asked to whiteboard in it.

## Process

### 1. Analyze the posting

Extract and write down, before touching the resume:

- **Hard requirements** — the must-haves, especially years-of-experience and named technologies
- **Preferred/nice-to-have** — secondary keyword targets
- **The stack** — languages, frameworks, cloud, data stores, CI, observability
- **Responsibility verbs** — what the person actually does day to day (design, migrate, mentor,
  own on-call, ship customer-facing features)
- **Seniority signals** — scope of ownership, mentorship, cross-team influence, ambiguity
- **Domain** — fintech, health, devtools, gov, agency; whether domain fluency is being screened for
- **Their vocabulary** — the exact terms the posting uses. If they write "observability," don't
  write "monitoring." If they write "React Native," don't write "mobile development." ATS matching
  is literal, and so is the human skimming for their own words.

### 2. Pick the baseline

Choose the baseline whose existing content is closest to the posting's stack and role shape. State
which one was picked and why in one line. If two are close, say so and pick the one needing fewer
additions — less stretch means fewer things to confirm.

### 3. Rewrite bullets

For each role, keeping the header line untouched:

- **Lead with what this posting cares about.** Same accomplishment, resequenced so the relevant
  half lands first. "Cut p99 latency 40% by rewriting the ingest path in Go" for a Go/performance
  role; "Rewrote the ingest path, cutting p99 latency 40%" for a systems role.
- **Reorder bullets within the role** so the top one is the strongest match.
- **Adopt the posting's vocabulary** wherever it genuinely describes the same work.
- **Keep the shape:** action verb → what was built/changed → outcome. Keep every real metric.
- **Compress, don't delete, weak roles.** An old unrelated job can drop to one line, but the entry
  stays with its title and dates intact.
- **No filler.** If a bullet says nothing the posting cares about and nothing impressive, cut it and
  give the space to a better one.

### 4. Rebuild the skills section

- Group into categories that match how the posting talks about its stack
- Lead each group with the posting's required items that Ve genuinely has
- Add relevant skills per the rules above
- Drop skills that are noise for this role — a long list dilutes the match
- Mirror exact naming: "PostgreSQL" vs "Postgres", "TypeScript" vs "TS" — follow the posting

### 5. Verify before writing output

Diff mentally against the baseline and confirm:

- Every employer, title, date, degree, and cert is byte-identical to the baseline
- Every number in the tailored version traces to the same accomplishment in the baseline
- No bullet claims ownership of something the baseline attributes to a team, or vice versa
- Page count matches the baseline (resumes are length-disciplined; if it grew, cut)

### 6. Output

Write the tailored resume next to the baselines as `<Company>-<Role>-<YYYY-MM>.<ext>`, preserving
the baseline's format. Do not overwrite a baseline, ever.

- `.md`, `.txt`, `.tex` — edit directly
- `.docx` — use the `docx` skill; preserve the template's styles and layout
- `.pdf` — read it for content, but ask for the source file to produce output from. Do not
  hand back a rebuilt PDF that silently loses the original's design.

## Change report

Print this in chat after writing the file:

```
Baseline used: <file> — <one line why>

Requirements coverage
  ✓ <requirement> → <where it now appears>
  ✓ <requirement> → <where it now appears>
  ⚠ <requirement> → not evidenced in any baseline

Bullets rewritten
  <Role> — <n> bullets reframed, reordered: <one line on the angle taken>

Skills
  Added: <list>
  Dropped: <list>
  Reordered into: <group names>

Confirm before sending
  - <added skill with no baseline evidence>
  - <any claim leaning harder than the baseline supports>

Gaps this resume can't close
  - <hard requirement genuinely not met — worth a cover letter line or a pass on the role>
```

The last two sections are the point of the report. Never print it with those headers omitted
because everything looked fine — if they're genuinely empty, write "none."
