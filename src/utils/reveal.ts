import type { Accessor } from "solid-js";

type RevealOptions = { delay?: number } | undefined;

/**
 * Solid directive: `use:reveal` / `use:reveal={{ delay: 80 }}`.
 * Adds `.reveal` immediately and `.in-view` when the element scrolls into
 * the viewport, so CSS can run entrance transitions. Honors
 * `prefers-reduced-motion` by revealing instantly with no observer.
 */
export function reveal(el: HTMLElement, value?: Accessor<RevealOptions>) {
    const opts = value?.() ?? {};
    el.classList.add("reveal");
    if (opts?.delay) el.style.setProperty("--reveal-delay", `${opts.delay}ms`);

    const reduce =
        typeof window !== "undefined" &&
        window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

    if (reduce || typeof IntersectionObserver === "undefined") {
        el.classList.add("in-view");
        return;
    }

    const io = new IntersectionObserver(
        (entries) => {
            for (const entry of entries) {
                if (entry.isIntersecting) {
                    entry.target.classList.add("in-view");
                    io.unobserve(entry.target);
                }
            }
        },
        { threshold: 0.15, rootMargin: "0px 0px -10% 0px" }
    );
    io.observe(el);
}

declare module "solid-js" {
    namespace JSX {
        interface Directives {
            reveal: RevealOptions;
        }
    }
}
