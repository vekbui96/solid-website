import { createSignal, For, Show, onCleanup, onMount } from "solid-js";
import type { FitReport, Axis } from "../../lib/fitAnalysis";
import { useGlobalContext } from "../../context/GlobalContext";
// @ts-ignore
import styles from "./FitAnalyzer.scss?inline";

const SAMPLES: Record<string, string> = {
    ai: `Senior AI Engineer
We're hiring a Senior AI Engineer to build production AI systems.
- Design and ship LLM-powered agents and RAG pipelines
- Build AI-enabled workflows with human-in-the-loop controls
- Integrate retrieval over enterprise knowledge and tools
- Evaluate model quality, latency, cost, and hallucination rates
- Partner with platform teams on developer experience and governance
Requires strong backend fundamentals (Java/Spring or similar), API design, and cloud (AWS).`,
    fullstack: `Full-Stack Software Engineer
Build complete product experiences end to end.
- Develop frontend features in TypeScript (React or SolidJS)
- Design backend services and REST APIs (Spring Boot)
- Build reusable UI components and design systems
- Implement validation, caching, and state management
- Ensure accessibility (WCAG) and observability
- Collaborate cross-functionally with product and design`,
    platform: `Platform Engineer
Scale engineering practices across the org.
- Build internal developer tooling and frameworks
- Improve developer experience and onboarding
- Define standards, governance, and reusable workflows
- Work with CI/CD, observability, and cloud infrastructure (AWS)
- Enable AI-assisted development workflows across teams`,
};

const STEPS = [
    "Reading the role",
    "Extracting requirements",
    "Mapping requirements to evidence",
    "Scoring fit & finding gaps",
];

export const FitAnalyzer = () => {
    const ctx = useGlobalContext();
    const [input, setInput] = createSignal("");
    const [status, setStatus] = createSignal<"idle" | "analyzing" | "done">("idle");
    const [step, setStep] = createSignal(0);
    const [report, setReport] = createSignal<FitReport | null>(null);
    const [dial, setDial] = createSignal(0);
    let timer: ReturnType<typeof setTimeout> | undefined;
    let textareaEl: HTMLTextAreaElement | undefined;
    let wrapEl: HTMLDivElement | undefined;
    let runId = 0;

    // The scoring code (and the projects data it matches against) is a separate chunk,
    // fetched when the section nears the viewport or on first interaction, never before.
    type FitMod = typeof import("../../lib/fitAnalysis");
    const [mod, setMod] = createSignal<FitMod | null>(null);
    let loading: Promise<FitMod> | undefined;
    const load = () => (loading ??= import("../../lib/fitAnalysis").then((m) => (setMod(m), m)));
    const axes = () => mod()?.AXES ?? [];

    onMount(() => {
        if (typeof IntersectionObserver === "undefined" || !wrapEl) return;
        const io = new IntersectionObserver((entries) => {
            if (entries.some((e) => e.isIntersecting)) { load(); io.disconnect(); }
        }, { rootMargin: "600px 0px" });
        io.observe(wrapEl);
        onCleanup(() => io.disconnect());
    });

    // what the polite live region says: nothing while idle, then progress, then the result
    const announcement = () => {
        if (status() === "analyzing") return "Analyzing the job description…";
        const r = report();
        if (status() === "done" && r) return `Analysis ready: match score ${r.matchScore} out of 100, ${r.bin}. ${r.headline}`;
        return "";
    };

    const reduce = () =>
        typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

    const tween = (target: number) => {
        if (reduce()) { setDial(target); return; }
        const start = performance.now(), dur = 950;
        const f = (t: number) => {
            const k = Math.min(1, (t - start) / dur);
            setDial(Math.round(target * (0.5 - 0.5 * Math.cos(Math.PI * k))));
            if (k < 1) requestAnimationFrame(f);
        };
        requestAnimationFrame(f);
    };

    const run = async () => {
        const jd = input().trim();
        if (jd.length < 12) return;
        clearTimeout(timer);
        const id = ++runId;
        setReport(null); setDial(0); setStatus("analyzing"); setStep(0);
        let m: FitMod;
        try { m = await load(); } catch { loading = undefined; if (id === runId) setStatus("idle"); return; }
        if (id !== runId) return;
        const r = m.analyzeFit(jd);
        const reveal = () => { setReport(r); setStatus("done"); tween(r.matchScore); };
        if (reduce()) { reveal(); return; }
        let i = 0;
        const tick = () => {
            i++; setStep(i);
            timer = setTimeout(i < STEPS.length ? tick : reveal, 520);
        };
        timer = setTimeout(tick, 350);
    };
    onCleanup(() => clearTimeout(timer));

    const useSample = (k: string) => { load(); setInput(SAMPLES[k]); runId++; setStatus("idle"); setReport(null); };
    // the reset button removes itself, so hand keyboard focus back to the input
    const reset = () => { runId++; setStatus("idle"); setReport(null); setDial(0); textareaEl?.focus(); };

    // radar geometry (viewBox 200x200, center 100,100, radius 78)
    const pt = (axis: Axis, v: number, i: number) => {
        const ang = ((-90 + i * 60) * Math.PI) / 180;
        const r = 78 * Math.max(0.05, Math.min(1, v));
        return [100 + r * Math.cos(ang), 100 + r * Math.sin(ang)];
    };
    const poly = (vals: Record<Axis, number>) =>
        axes().map((a, i) => pt(a.id, vals[a.id], i).join(",")).join(" ");
    const axisEnd = (i: number) => {
        const ang = ((-90 + i * 60) * Math.PI) / 180;
        return [100 + 78 * Math.cos(ang), 100 + 78 * Math.sin(ang)];
    };
    const labelPos = (i: number) => {
        const ang = ((-90 + i * 60) * Math.PI) / 180;
        return [100 + 96 * Math.cos(ang), 100 + 96 * Math.sin(ang)];
    };

    const R = 52, C = 2 * Math.PI * R;
    const confClass = () => {
        const s = report()?.matchScore ?? 0;
        return s >= 66 ? "fa-strong" : s >= 41 ? "fa-moderate" : "fa-low";
    };

    return (
        <>
            <style>{styles}</style>
            <div class="container fa-wrap" ref={wrapEl}>
                <p class="hp-eyebrow fa-eyebrow">Fit Analyzer</p>
                <h2 class="fa-title">Wondering if I fit a role?</h2>
                <p class="fa-sub">
                    Paste a job description. It runs in your browser and shows where I line up and where I don't.
                </p>

                <div class="fa-input-wrap">
                    <textarea
                        ref={textareaEl}
                        class="fa-textarea"
                        rows="6"
                        placeholder="Paste a job description…"
                        aria-label="Job description"
                        value={input()}
                        onFocus={() => { load(); }}
                        onInput={(e) => setInput(e.currentTarget.value)}
                    />
                    <div class="fa-controls">
                        <div class="fa-samples" role="group" aria-label="Try a sample job description">
                            <span class="fa-try">Try:</span>
                            <button class="fa-chip" onClick={() => useSample("ai")}>AI Engineer</button>
                            <button class="fa-chip" onClick={() => useSample("fullstack")}>Full-Stack</button>
                            <button class="fa-chip" onClick={() => useSample("platform")}>Platform</button>
                        </div>
                        <button class="fa-analyze" onClick={run} disabled={input().trim().length < 12}>
                            Analyze fit →
                        </button>
                    </div>
                    <p class="fa-privacy">🔒 Analyzed in your browser — your text never leaves this page or gets stored.</p>
                </div>

                {/* screen-reader announcement; always rendered so changes are spoken */}
                <p class="fa-sr" role="status" aria-live="polite" aria-atomic="true">{announcement()}</p>

                {/* reasoning timeline */}
                <Show when={status() === "analyzing"}>
                    <div class="fa-timeline">
                        <For each={STEPS}>
                            {(s, i) => (
                                <div class="fa-step" classList={{ done: step() > i(), active: step() === i() + 1 || (step() > i()) }}>
                                    <span class="fa-dot" />
                                    <span class="fa-step-label">{s}…</span>
                                </div>
                            )}
                        </For>
                    </div>
                </Show>

                {/* report */}
                <Show when={status() === "done" && report()}>
                    {(rep) => (
                        <div class="fa-report">
                            <div class="fa-top">
                                <div class="fa-dial-box">
                                    <svg viewBox="0 0 140 140" class={`fa-dial ${confClass()}`} role="img" aria-label={`Match score ${rep().matchScore} out of 100`}>
                                        <circle cx="70" cy="70" r={R} class="fa-dial-track" />
                                        <circle cx="70" cy="70" r={R} class="fa-dial-arc"
                                            transform="rotate(-90 70 70)"
                                            style={{ "stroke-dasharray": `${C}`, "stroke-dashoffset": `${C * (1 - dial() / 100)}` }} />
                                        <text x="70" y="68" class="fa-dial-num">{dial()}</text>
                                        <text x="70" y="90" class="fa-dial-bin">{rep().bin}</text>
                                    </svg>
                                    <p class="fa-rationale">{rep().scoreRationale}</p>
                                </div>

                                <div class="fa-radar-box">
                                    <svg viewBox="0 0 200 200" class="fa-radar" role="img" aria-label="Capability radar: role demand versus candidate strength">
                                        <For each={[0.25, 0.5, 0.75, 1]}>
                                            {(g) => <polygon class="fa-grid" points={axes().map((a, i) => axisEnd(i).map((c) => 100 + (c - 100) * g).join(",")).join(" ")} />}
                                        </For>
                                        <For each={axes()}>
                                            {(_, i) => <line class="fa-axis" x1="100" y1="100" x2={axisEnd(i())[0]} y2={axisEnd(i())[1]} />}
                                        </For>
                                        <polygon class="fa-strength" points={poly(rep().strength)} />
                                        <polygon class="fa-demand" points={poly(rep().demand)} />
                                        <For each={axes()}>
                                            {(a, i) => {
                                                const [x, y] = labelPos(i());
                                                return <text class="fa-radar-label" x={x} y={y} text-anchor="middle" dominant-baseline="middle">{a.label}</text>;
                                            }}
                                        </For>
                                    </svg>
                                    <div class="fa-legend">
                                        <span class="fa-leg fa-leg-strength">My strength</span>
                                        <span class="fa-leg fa-leg-demand">Role demand</span>
                                    </div>
                                </div>
                            </div>

                            <p class="fa-headline">{rep().headline}</p>

                            {/* strengths */}
                            <Show when={rep().strengths.length}>
                                <div class="fa-block">
                                    <span class="fa-label">Strength areas</span>
                                    <div class="fa-strengths">
                                        <For each={rep().strengths}>
                                            {(s) => (
                                                <div class="fa-strength-card">
                                                    <h4>{s.title}</h4>
                                                    <p>{s.detail}</p>
                                                    <div class="fa-ev-chips">
                                                        <For each={s.projects}>
                                                            {(p) => <button class="fa-ev-chip" onClick={() => ctx?.setOpenProjectId(p.id)}>{p.title}</button>}
                                                        </For>
                                                    </div>
                                                </div>
                                            )}
                                        </For>
                                    </div>
                                </div>
                            </Show>

                            {/* requirement → evidence */}
                            <Show when={rep().requirements.length}>
                                <div class="fa-block">
                                    <span class="fa-label">Requirement → evidence</span>
                                    <div class="fa-reqs">
                                        <For each={rep().requirements}>
                                            {(r) => (
                                                <div class="fa-req">
                                                    <div class="fa-req-head">
                                                        <span class={`fa-conf fa-conf-${r.confidence}`}>{r.confidence}</span>
                                                        <span class="fa-req-text">{r.text}</span>
                                                    </div>
                                                    <Show when={r.evidence.length} fallback={<p class="fa-noev">No direct evidence — adjacent systems work only.</p>}>
                                                        <div class="fa-ev-chips">
                                                            <For each={r.evidence}>
                                                                {(e) => <button class="fa-ev-chip" onClick={() => e.projectId && ctx?.setOpenProjectId(e.projectId)}>{e.title}</button>}
                                                            </For>
                                                        </div>
                                                    </Show>
                                                </div>
                                            )}
                                        </For>
                                    </div>
                                </div>
                            </Show>

                            {/* gaps */}
                            <div class="fa-block">
                                <span class="fa-label">Gap analysis</span>
                                <div class="fa-gaps">
                                    <For each={rep().gaps}>
                                        {(g) => (
                                            <div class="fa-gap">
                                                <span class="fa-gap-area">{g.area}</span>
                                                <span class="fa-gap-note">{g.note}</span>
                                            </div>
                                        )}
                                    </For>
                                </div>
                            </div>

                            <p class="fa-summary">{rep().summary}</p>

                            <div class="fa-actions">
                                <a class="fa-analyze" href="mailto:tommy.bui1428@gmail.com">This look right? Let's talk →</a>
                                <button class="fa-reset" onClick={reset}>Analyze another role</button>
                            </div>
                        </div>
                    )}
                </Show>
            </div>
        </>
    );
};
