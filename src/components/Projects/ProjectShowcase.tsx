import { createSignal, For, Show } from "solid-js";
import projects from "../../data/projects.json";
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
    const [filter, setFilter] = createSignal<string>("all");
    const [open, setOpen] = createSignal<string | null>(null);

    const visible = () =>
        filter() === "all"
            ? projects
            : projects.filter((p) => p.categories.includes(filter()));

    const toggle = (id: string) => setOpen(open() === id ? null : id);

    return (
        <>
            <style>{styles}</style>

            <div class="pj-filters" role="tablist" aria-label="Filter projects by discipline">
                <For each={filters}>
                    {(f) => (
                        <button
                            class="pj-filter"
                            role="tab"
                            aria-selected={filter() === f.id}
                            classList={{ active: filter() === f.id }}
                            onClick={() => setFilter(f.id)}
                        >
                            {f.label}
                        </button>
                    )}
                </For>
            </div>

            <div class="pj-grid">
                <For each={visible()}>
                    {(p) => (
                        <article class="pj-card" classList={{ open: open() === p.id, featured: (p as any).featured }}>
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

                                    <div class="pj-skills">
                                        <For each={p.skills}>{(s) => <span class="pj-skill">{s}</span>}</For>
                                    </div>
                                </div>
                            </Show>
                        </article>
                    )}
                </For>
            </div>
        </>
    );
};
