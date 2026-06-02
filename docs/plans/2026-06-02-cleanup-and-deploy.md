# Cleanup & Deploy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove dead/broken code, make the Home/About/Projects nav actually switch content, drive content from real data, normalize file extensions/imports, then build and deploy to GitHub Pages.

**Architecture:** The live app is a single Solid custom element (`<main-page>` in `src/index.tsx`) that renders `ThreeBackground + Header + <content>`. Each component imports its sibling `.scss` with `?inline` and renders `<style>{styles}</style>`. A global signal (`context.page()`) will select which section renders. A second, abandoned React-style set of files (`About.jsx`, `SocialMedia.jsx`, `SectionTitle.jsx`, `HeroArea.jsx`) uses `className` + Tailwind + React `key` and does not work in Solid — we rebuild About/Projects natively and delete the dead files instead of wiring them up.

**Tech Stack:** SolidJS 1.8, Vite 4, TypeScript (loose), SCSS, Three.js, gh-pages.

**Verification:** No test runner (per decision). Each task is verified manually via `yarn dev` (visual check in browser) and/or `yarn build` (must succeed with no errors), then committed.

**Branch:** Work on a branch off `main` (e.g. `cleanup-and-deploy`); deploy happens from the built `dist/` in the final phase.

---

## Phase 0: Branch setup

### Task 0: Create working branch

**Step 1: Confirm clean tree and branch**

Run:
```bash
git status
git checkout -b cleanup-and-deploy
```
Expected: clean tree, now on `cleanup-and-deploy`.

---

## Phase 1: Remove dead / broken code

### Task 1: Delete the unused `main.tsx` stub

**Files:**
- Delete: `src/main.tsx`

**Step 1: Confirm nothing imports it**

Run:
```bash
grep -rn "main.tsx\|from './main'\|from \"../main\"\|main'" src --include=*.tsx --include=*.jsx | grep -i main
```
Expected: no import references to `main.tsx` (it exports an unused `main` returning `test`).

**Step 2: Delete the file**

```bash
git rm src/main.tsx
```

**Step 3: Verify build still works**

Run: `yarn build`
Expected: build succeeds.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove unused main.tsx stub"
```

---

### Task 2: Delete dead React-style files we will not wire up

**Files:**
- Delete: `src/pages/HeroArea/HeroArea.jsx` (empty stub — returns nothing)
- Delete: `src/pages/HeroArea/HeroArea.scss`
- Delete: `src/components/SectionTitle.jsx` (Tailwind classes; no Tailwind configured)

**Why:** `HeroArea` renders nothing and is unused. `SectionTitle` relies on Tailwind utility classes that aren't installed, and uses `className` (ignored by Solid). About/Projects are rebuilt natively in Phase 3, so these aren't needed.

**Step 1: Confirm they're unimported**

Run:
```bash
grep -rn "HeroArea\|SectionTitle" src
```
Expected: matches only inside the files being deleted (and `About.jsx`, which is itself rebuilt in Phase 3 — Task 9 removes the old import).

**Step 2: Delete**

```bash
git rm src/pages/HeroArea/HeroArea.jsx src/pages/HeroArea/HeroArea.scss src/components/SectionTitle.jsx
```

**Step 3: Verify build**

Run: `yarn build`
Expected: build succeeds.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove dead HeroArea and SectionTitle files"
```

---

### Task 3: Strip stray console.log calls

**Files:**
- Modify: `src/index.tsx:28`
- Modify: `src/pages/ThreeBackground/ThreeBackground.jsx:9`

**Step 1: Remove the log in `MainPage`**

In `src/index.tsx`, delete the line:
```tsx
    console.log(context.exampleContext());
```

**Step 2: Remove the log in `ThreeBackground`**

In `src/pages/ThreeBackground/ThreeBackground.jsx`, inside `onMount`, delete:
```jsx
    console.log(containerRef);
```

**Step 3: Verify dev server runs clean**

Run: `yarn dev`, open the site, confirm no console output from these lines and the page renders. Stop the server.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove debug console.log calls"
```

---

### Task 4: Fix `Experience.tsx` rendering bugs

**Files:**
- Modify: `src/components/Experience/Experience.tsx`

**Bugs:** (a) `endDate` renders a raw `Date` object as a string; (b) `acomplishments` is misspelled; (c) the conditional accomplishment helper should use Solid's `<Show>`; (d) both `Experience` and `ExperienceList` inject the same `<style>` (deduped in Task 7).

**Step 1: Replace the file's component code**

Replace the type and `Experience` component with:
```tsx
import { Show } from "solid-js";
import styles from './Experience.scss?inline'

type ExperienceType = {
    company: string;
    position: string;
    startDate: Date;
    endDate?: Date;
    description: string;
    accomplishments?: string;
    skills: string;
}

export const Experience = (props: ExperienceType) => {
    return (
        <div class="experience-container">
            <h2>{props.company}</h2>
            <div class="experience-position-date">
                <h2>{props.position}</h2>
                <h3>
                    {props.startDate.getFullYear()} - {props.endDate ? props.endDate.getFullYear() : "Current"}
                </h3>
            </div>
            <h3 class="experience-description">{props.description}</h3>
            <Show when={props.accomplishments}>
                <p>Accomplishments: {props.accomplishments}</p>
            </Show>
            <p>Skills: {props.skills}</p>
        </div>
    )
}
```
(The single `<style>{styles}</style>` now lives only in `ExperienceList` — see Task 7. Leave `ExperienceList` as-is for this task; it is replaced in Task 8.)

**Step 2: Verify it compiles**

Run: `yarn build`
Expected: build succeeds (no TS error about `acomplishments`).

**Step 3: Verify visually**

Run: `yarn dev`, confirm experience entries show "<year> - Current" (not `[object Object]` / a raw date) and the Accomplishments line renders. Stop the server.

**Step 4: Commit**

```bash
git add -A
git commit -m "fix: correct endDate rendering and accomplishments spelling in Experience"
```

---

## Phase 2: Normalize extensions & imports

### Task 5: Rename `.jsx` source files to `.tsx`

**Files:**
- Rename: `src/pages/ThreeBackground/ThreeBackground.jsx` → `.tsx`

**Why:** Standardize on `.tsx` for all components. (`main.tsx`, `HeroArea.jsx`, `SectionTitle.jsx` were deleted; `About.jsx` is rebuilt as `.tsx` in Task 9; `SocialMedia.jsx` is deleted in Task 9 unless reused. `Home.tsx` is already `.tsx`.)

**Step 1: Rename and type the ref**

```bash
git mv src/pages/ThreeBackground/ThreeBackground.jsx src/pages/ThreeBackground/ThreeBackground.tsx
```
Then in the new file, type the container ref so TS is happy:
```tsx
  let containerRef: HTMLDivElement | undefined;
```
and guard the append:
```tsx
    containerRef?.appendChild(renderer.domElement);
```

**Step 2: Update the import in `index.tsx`**

In `src/index.tsx`, the import already reads:
```tsx
import ThreeBackground from './pages/ThreeBackground/ThreeBackground.jsx'
```
Change the specifier to extensionless:
```tsx
import ThreeBackground from './pages/ThreeBackground/ThreeBackground'
```

**Step 3: Verify build**

Run: `yarn build`
Expected: build succeeds.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: convert ThreeBackground to .tsx"
```

---

### Task 6: Normalize import specifiers to be extensionless

**Files:**
- Modify: `src/index.tsx`

**Why:** Imports point at `.jsx` paths for `.tsx` files (works via Vite, but misleading). Drop the extensions so the resolver picks the real file.

**Step 1: Update the imports in `src/index.tsx`**

Change:
```tsx
import { Header } from './pages/Header/header.jsx'
import { Home } from './pages/Home/Home.jsx'
import { GlobalContextProvider, useGlobalContext } from './context/GlobalContext.jsx';
```
to:
```tsx
import { Header } from './pages/Header/header'
import { Home } from './pages/Home/Home'
import { GlobalContextProvider, useGlobalContext } from './context/GlobalContext';
```

**Step 2: Check for other `.jsx`/`.tsx` specifiers**

Run:
```bash
grep -rn "from '.*\.\(jsx\|tsx\)'" src
```
Expected: no remaining explicit `.jsx`/`.tsx` import specifiers. Fix any that appear.

**Step 3: Verify build**

Run: `yarn build`
Expected: build succeeds.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: use extensionless import specifiers"
```

---

### Task 7: Dedupe the repeated inline `<style>` injection

**Files:**
- Modify: `src/components/Experience/Experience.tsx`

**Why:** The same `Experience.scss` was injected by both `Experience` and `ExperienceList`. One injection at the list level is enough.

**Step 1: Confirm `Experience` (child) no longer injects styles**

After Task 4, the child `Experience` component should NOT contain `<style>{styles}</style>`. Confirm it doesn't. The single injection stays in `ExperienceList` (handled in Task 8).

**Step 2: Verify visually**

Run: `yarn dev`, confirm experience styling still applies (only one `<style>` tag now). Stop the server.

**Step 3: Commit (if any change was needed)**

```bash
git add -A
git commit -m "refactor: inject Experience styles once at the list level"
```

---

## Phase 3: Page switching + real content

### Task 8: Make experience data-driven from JSON

**Files:**
- Create: `src/data/experience.json`
- Modify: `src/components/Experience/Experience.tsx` (the `ExperienceList` export)

**Step 1: Create the data file**

`src/data/experience.json` (pre-filled with known facts — real values completed in Task 11):
```json
[
  {
    "company": "Capital One",
    "position": "Front End Developer",
    "startDate": "2020-01-30",
    "description": "TODO: short description of the role.",
    "accomplishments": "TODO: key accomplishment.",
    "skills": "Java, JavaScript, SolidJS"
  }
]
```

**Step 2: Drive `ExperienceList` from the data**

Replace the `ExperienceList` export in `Experience.tsx` with:
```tsx
import experiences from "../../data/experience.json";
import { For } from "solid-js";

export const ExperienceList = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="experience-list">
                <For each={experiences}>
                    {(exp) => (
                        <Experience
                            company={exp.company}
                            position={exp.position}
                            startDate={new Date(exp.startDate)}
                            endDate={exp.endDate ? new Date(exp.endDate) : undefined}
                            description={exp.description}
                            accomplishments={exp.accomplishments}
                            skills={exp.skills}
                        />
                    )}
                </For>
            </div>
        </>
    )
}
```
Add to `tsconfig.json` compilerOptions if JSON import errors: `"resolveJsonModule": true`. (Vite handles JSON at runtime; this is only for TS.)

**Step 3: Verify**

Run: `yarn build` (succeeds), then `yarn dev` and confirm the experience list renders from JSON. Stop the server.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: drive experience list from experience.json"
```

---

### Task 9: Rebuild the About page natively (Solid + inline SCSS)

**Files:**
- Create: `src/pages/About/About.tsx`
- Create/replace: `src/pages/About/About.scss`
- Delete: `src/pages/About/About.jsx` (React-style, broken in Solid)
- Delete: `src/pages/About/about.scss` (old Tailwind-companion styles)
- Delete: `src/pages/SocialMedia/SocialMedia.jsx` (unused React-style; not wired in)

**Why:** The old `About.jsx` uses `className` (ignored by Solid), Tailwind classes, and placeholder "Lucy Doe" data. Rebuild it to match the live dark, right-aligned theme using the `?inline` pattern.

**Step 1: Create `src/pages/About/About.scss`**

```scss
.about-container {
    max-width: 600px;
    text-align: end;

    p {
        line-height: 1.6;
        margin-bottom: 12px;
    }
}
```

**Step 2: Create `src/pages/About/About.tsx`**

```tsx
import styles from "./About.scss?inline";
import about from "../../data/about.json";

export const About = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="about-container">
                <p>{about.bio}</p>
            </div>
        </>
    );
};
```

**Step 3: Delete the dead files**

```bash
git rm src/pages/About/About.jsx src/pages/About/about.scss src/pages/SocialMedia/SocialMedia.jsx
```

**Step 4: Verify build**

Run: `yarn build`
Expected: build succeeds. (About isn't rendered until Task 10 wires switching — this just confirms it compiles.)

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: rebuild About page in native Solid style"
```

---

### Task 10: Wire up page switching in `MainPage`

**Files:**
- Modify: `src/context/GlobalContext.tsx` (fix default page typo + type the signal)
- Create: `src/pages/Projects/Projects.tsx`
- Create: `src/pages/Projects/Projects.scss`
- Modify: `src/index.tsx` (render based on `context.page()`)

**Step 1: Fix the default page value and type it**

In `src/context/GlobalContext.tsx`, change:
```tsx
    const [page, setPage] = createSignal("hom");
```
to:
```tsx
    const [page, setPage] = createSignal<"home" | "about" | "projects">("home");
```

**Step 2: Create a minimal Projects page**

`src/pages/Projects/Projects.scss`:
```scss
.projects-container {
    max-width: 600px;
    text-align: end;
}
```
`src/pages/Projects/Projects.tsx`:
```tsx
import styles from "./Projects.scss?inline";

export const Projects = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="projects-container">
                <h1>Projects</h1>
                <p>Coming soon.</p>
            </div>
        </>
    );
};
```

**Step 3: Switch content in `MainPage`**

In `src/index.tsx`, add imports:
```tsx
import { Switch, Match } from 'solid-js';
import { About } from './pages/About/About';
import { Projects } from './pages/Projects/Projects';
```
Replace the content area:
```tsx
                <div class="display-manager">
                    <Home/>
                </div>
```
with:
```tsx
                <div class="display-manager">
                    <Switch fallback={<Home/>}>
                        <Match when={context.page() === "home"}><Home/></Match>
                        <Match when={context.page() === "about"}><About/></Match>
                        <Match when={context.page() === "projects"}><Projects/></Match>
                    </Switch>
                </div>
```

**Step 4: Verify switching works**

Run: `yarn dev`. Click Home / About / Projects in the nav and confirm the content area swaps. Stop the server.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: switch content area by nav selection (home/about/projects)"
```

---

### Task 11: Fill in real portfolio content

**Files:**
- Modify: `src/data/about.json` (replace "Lucy Doe" placeholder bio + socials)
- Modify: `src/data/experience.json` (replace TODO fields)
- Modify: `src/pages/Header/header.tsx` (confirm name/title)

> **For Claude:** This task needs the user's real data. Before editing, ask the user for: (1) their bio paragraph, (2) each role's company/title/start+end dates/description/accomplishment/skills, (3) social links. Pre-fill known facts (name "Ve Bui", title "Software Engineer", Capital One start 2020-01-30) and prompt for the rest. Do not invent biographical details.

**Step 1: Gather real content from the user** (see note above).

**Step 2: Update `src/data/about.json`** — set `name`, `bio`, and real `socialMedia` links (or remove the social entries if unused).

**Step 3: Update `src/data/experience.json`** — replace each `TODO:` with real text; add additional role objects as needed.

**Step 4: Confirm `header.tsx`** shows the correct name ("Ve Bui") and title ("Software Engineer"). Edit if needed.

**Step 5: Verify**

Run: `yarn dev`, review Home / About content for accuracy and no leftover "TODO"/"Lucy Doe"/"Tommy". Stop the server.

**Step 6: Commit**

```bash
git add -A
git commit -m "content: populate real bio and experience data"
```

---

## Phase 4: Build & deploy

### Task 12: Production build sanity check

**Step 1: Clean build**

Run:
```bash
rm -rf dist
yarn build
```
Expected: build succeeds, `dist/index.html` and `dist/assets/*` produced.

**Step 2: Preview the production build locally**

Run: `yarn vite preview` (or `npx vite preview`). Open the served URL, click through Home/About/Projects, confirm the Three.js background renders and nav works. Stop the preview.

**Step 3: Commit any final fixes** (only if changes were needed).

---

### Task 13: Merge to main and deploy

**Files:** none (git + deploy)

**Step 1: Merge the branch to `main`**

```bash
git checkout main
git merge --no-ff cleanup-and-deploy
```

**Step 2: Build from main**

Run: `yarn build`
Expected: succeeds.

**Step 3: Deploy to GitHub Pages**

Run: `yarn deploy`
Expected: `gh-pages` publishes `dist/` to the `gh-pages` branch (the live source).

**Step 4: Push main**

```bash
git push origin main
```

**Step 5: Verify the live site**

Open the GitHub Pages URL for `vekbui96/solid-website` and confirm the deployed site shows the cleaned-up content and working nav. Note: GitHub Pages may take a minute to update.

---

## Done criteria

- [ ] No unused/dead files (`main.tsx`, `HeroArea*`, `SectionTitle`, old `About.jsx`/`about.scss`, `SocialMedia.jsx` removed)
- [ ] No stray `console.log`
- [ ] Experience renders years correctly and from JSON
- [ ] All source components are `.tsx` with extensionless imports
- [ ] Nav switches Home / About / Projects
- [ ] Real content in `about.json` / `experience.json` / header
- [ ] `yarn build` clean; live `gh-pages` site reflects changes
