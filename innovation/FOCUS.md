# Loop focus

<!--
Ve edits this file to steer what the loop proposes (Phase B). The loop only reads it; it cannot write it.
It is read from D:\projects\solid-website\innovation at the start of each run, so an edit there takes
effect on the next run (commit it so the laptop copy agrees). If nothing but headings and comments is
left, or the file is missing, the loop proposes from its own judgment as before.
It steers proposals only: it never overrides LOOP.md's hard rules and never makes Phase A build anything.
-->

## Approve specs, not single ideas (set 2026-11-21 by Ve)

Ve approves a spec once and every slice builds on that approval (auto-approved via spec, LOOP.md
section 1 "Specs"), so one approval should unlock several builds.

- **Default to a spec** (LOOP.md 5.7) for anything more than one small, self-contained change:
  multi-step work, anything touching several sections, anything needing new stored data or an API piece,
  and any priority below that cannot ship as one Size-S slice. Single proposals are only for genuinely
  small polish or fixes: Size S, one section, front end only. Never a run of unlinked issues.
- **Keep one spec waiting for Ve.** After any slices to open, if `slots.mayOpenSpec` is true and a slot
  is free, the session's first new item is a spec whenever a worthwhile multi-step idea exists. The
  LOOP.md limit stays: at most one unapproved spec at a time.
- **Write specs that flow without Ve:** 3-5 slices, each independently shippable, in build order. Put
  anything Manual / needs Ve (content or claims about Ve, new stored data, API data changes) in the FIRST
  slice(s), or name it plainly in the spec, so later slices are not held behind an open Manual slice.
  Prefer a design with no Manual slice where a safe one exists.
- **Next specs, in this order** (check open and closed issues first; never re-propose a rejected one; a
  spec may take in an open single proposal it covers, saying so, but must not duplicate it):
  1. **WCAG AA pass across the nine sections** (priority 1): contrast, keyboard and focus order, reduced
     motion, a section or two per slice, each with its own test (follows #9, #4; relates to #10, #21).
  2. **Performance budget** (priority 2): measure Lighthouse performance / SEO / best-practices on the
     live page first, then fonts, image weight and bundle size slice by slice, each with its before/after
     number (relates to #22).
  3. **Projects section polish** (priority 4): layout, filtering and empty states, presentation only;
     any change to `projects.json` content is a claim about Ve, so slice 1 and Manual, or left out.

## Priorities (highest first)

1. Accessibility to WCAG AA across all nine sections: contrast in the dark sections, keyboard and
   focus handling, reduced motion.
2. Performance: Lighthouse performance / SEO / best-practices on the live page, bundle size, image
   weight, font loading.
3. Contact-form reliability end to end, and API robustness and tests (validation, rate limiting,
   contract tests).
4. Small polish that visitors notice.

## Avoid

- Content or claims about Ve (Fit Analyzer `GAP_TERMS` / `STRENGTH`, profile copy, `projects.json`
  content) unless the proposal explicitly flags it.
- Large redesigns.
- New dependencies (they cannot pass the frozen-lockfile gate).
- Anything touching only `src/ui/` (Storybook-only, low visitor value), unless it is an accessibility fix.
