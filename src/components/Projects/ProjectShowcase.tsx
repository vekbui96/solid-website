import { createSignal, createEffect, For, Show, onMount } from "solid-js";
import type projectsJson from "../../data/projects.json";
import { useGlobalContext } from "../../context/GlobalContext";
// @ts-ignore
import styles from "./ProjectShowcase.scss?inline";

const filters = [
    { id: "all", label: "All" },
    { id: "frontend", label: "Frontend" },
    { id: "backend", label: "Backend" },
    { id: "ai", label: "AI" },
] as const;

const catLabel: Record<string, string> = {
    frontend: "Frontend",
    backend: "Backend",
    ai: "AI",
};

export const ProjectShowcase = () => {
    const ctx = useGlobalContext();
    const [filter, setFilter] = createSignal<string>("all");
    const [open, setOpen] = createSignal<string | null>(null);
    const [showAll, setShowAll] = createSignal(false);
    let gridEl: HTMLDivElement | undefined;

    // the project data is its own chunk (shared with the Fit Analyzer), fetched on mount
    const [projects, setProjects] = createSignal<typeof projectsJson>([] as any);
    const [failed, setFailed] = createSignal(false);
    const loadProjects = () => {
        setFailed(false);
        import("../../data/projects.json").then((m) => setProjects((m as any).default), () => setFailed(true));
    };
    onMount(loadProjects);

    const visible = () => {
        const all = projects();
        if (filter() !== "all") return all.filter((p) => p.categories.includes(filter()));
        return showAll() ? all : all.filter((p) => (p as any).curated);
    };

    const toggle = (id: string) => setOpen(open() === id ? null : id);

    // deep-link: the Fit Analyzer requests a project — reveal, open, and scroll to it
    createEffect(() => {
        const id = ctx?.openProjectId();
        if (!id) return;
        setFilter("all");
        setShowAll(true);
        setOpen(id);
        setTimeout(() => {
            const root = gridEl?.getRootNode() as any;
            const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
            root?.getElementById?.(`proj-${id}`)?.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "center" });
            ctx?.setOpenProjectId(null);
        }, 70);
    });

    return (
        <>
            <style>{styles}</style>

            <div class="pj-filters" role="group" aria-label="Filter projects by discipline">
                <For each={filters}>
                    {(f) => (
                        <button
                            class="pj-filter"
                            aria-pressed={filter() === f.id}
                            classList={{ active: filter() === f.id, "pj-filter-ai": f.id === "ai" }}
                            onClick={() => setFilter(f.id)}
                        >
                            {f.label}
                        </button>
                    )}
                </For>
            </div>

            <Show when={!projects().length}>
                <p class="pj-loading" role="status" style={{ "min-height": "320px", opacity: "0.7" }}>
                    {failed() ? "Couldn't load the projects. " : "Loading projects…"}
                    <Show when={failed()}><button class="pj-more-btn" onClick={loadProjects}>Try again</button></Show>
                </p>
            </Show>

            <div class="pj-grid" ref={gridEl}>
                <For each={visible()}>
                    {(p) => (
                        <article id={`proj-${p.id}`} class="pj-card" classList={{ open: open() === p.id, featured: (p as any).featured }}>
                            <button
                                class="pj-head"
                                aria-expanded={open() === p.id}
                                onClick={() => toggle(p.id)}
                            >
                                <span class="pj-head-text">
                                    <span class="pj-cats">
                                        <For each={p.categories}>
                                            {(c) => <span class="pj-cat">{catLabel[c] ?? c}</span>}
                                        </For>
                                        <Show when={(p as any).featured}>
                                            <span class="pj-cat pj-cat-star">Flagship</span>
                                        </Show>
                                    </span>
                                    <span class="pj-title">{p.title}</span>
                                    <span class="pj-tag">{p.tagline}</span>
                                </span>
                                <span class="pj-toggle" aria-hidden="true">{open() === p.id ? "–" : "+"}</span>
                            </button>

                            <Show when={open() === p.id}>
                                <div class="pj-body">
                                    <Show when={(p as any).flow}>
                                        <div class="pj-flow">
                                            <For each={(p as any).flow as string[]}>
                                                {(step, i) => (
                                                    <>
                                                        <Show when={i() > 0}><i aria-hidden="true">→</i></Show>
                                                        <span>{step}</span>
                                                    </>
                                                )}
                                            </For>
                                        </div>
                                    </Show>

                                    <Show when={(p as any).problem}>
                                        <p class="pj-problem">
                                            <span class="pj-label">Problem</span>
                                            {(p as any).problem}
                                        </p>
                                    </Show>

                                    <div class="pj-highlights">
                                        <span class="pj-label">Highlights</span>
                                        <ul>
                                            <For each={p.highlights}>{(h) => <li>{h}</li>}</For>
                                        </ul>
                                    </div>

                                    <Show when={(p as any).challenges}>
                                        <div class="pj-highlights">
                                            <span class="pj-label">Challenges</span>
                                            <ul>
                                                <For each={(p as any).challenges as string[]}>{(c) => <li>{c}</li>}</For>
                                            </ul>
                                        </div>
                                    </Show>

                                    <Show when={(p as any).features}>
                                        <div class="pj-features">
                                            <span class="pj-label">Features</span>
                                            <div class="pj-feature-grid">
                                                <For each={(p as any).features as { name: string; desc: string }[]}>
                                                    {(f) => (
                                                        <div class="pj-feature">
                                                            <span class="pj-feature-name">{f.name}</span>
                                                            <span class="pj-feature-desc">{f.desc}</span>
                                                        </div>
                                                    )}
                                                </For>
                                            </div>
                                        </div>
                                    </Show>

                                    <Show when={(p as any).examples}>
                                        <div class="pj-examples">
                                            <span class="pj-label">Ask it</span>
                                            <For each={(p as any).examples as { q: string; a: string }[]}>
                                                {(ex) => (
                                                    <div class="pj-example">
                                                        <span class="pj-q">{ex.q}</span>
                                                        <span class="pj-a">{ex.a}</span>
                                                    </div>
                                                )}
                                            </For>
                                        </div>
                                    </Show>

                                    <Show when={(p as any).takeaway}>
                                        <div class="pj-takeaway">
                                            <span class="pj-label">Why it matters</span>
                                            <p>{(p as any).takeaway}</p>
                                        </div>
                                    </Show>

                                    <Show when={(p as any).links}>
                                        <div class="pj-links">
                                            <For each={(p as any).links}>
                                                {(lnk: any) => (
                                                    <a
                                                        class="pj-link"
                                                        href={lnk.href}
                                                        target="_blank"
                                                        rel="noopener noreferrer"
                                                        onClick={(e) => e.stopPropagation()}
                                                    >
                                                        {lnk.label} ↗
                                                    </a>
                                                )}
                                            </For>
                                        </div>
                                    </Show>

                                    <div class="pj-skills">
                                        <For each={p.skills}>{(s) => <span class="pj-skill">{s}</span>}</For>
                                    </div>
                                </div>
                            </Show>
                        </article>
                    )}
                </For>
            </div>

            <Show when={filter() === "all" && projects().length}>
                <div class="pj-more">
                    <button class="pj-more-btn" onClick={() => setShowAll(!showAll())}>
                        {showAll() ? "Show fewer" : `Show all ${projects().length} projects →`}
                    </button>
                </div>
            </Show>
        </>
    );
};
