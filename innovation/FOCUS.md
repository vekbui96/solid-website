# Loop focus

<!--
Ve edits this file to steer what the loop proposes (Phase B). The loop only reads it; it cannot write it.
It is read from D:\projects\solid-website\innovation at the start of each run, so an edit there takes
effect on the next run (commit it so the laptop copy agrees). If nothing but headings and comments is
left, or the file is missing, the loop proposes from its own judgment as before.
It steers proposals only: it never overrides LOOP.md's hard rules and never makes Phase A build anything.
-->


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
