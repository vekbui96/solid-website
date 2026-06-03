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

                                    <p class="pj-problem">
                                        <span class="pj-label">Problem</span>
                                        {p.problem}
                                    </p>

                                    <div class="pj-highlights">
                                        <span class="pj-label">Highlights</span>
                                        <ul>
                                            <For each={p.highlights}>{(h) => <li>{h}</li>}</For>
                                        </ul>
                                    </div>

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
