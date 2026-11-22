import { For, onMount, onCleanup, createSignal, createEffect } from 'solid-js';
// @ts-ignore
import styles from './NavBar.scss?inline'
import { useGlobalContext } from '../../context/GlobalContext'

const links = [
    { id: "story", label: "Story" },
    { id: "projects", label: "Projects" },
    { id: "fit", label: "Fit" },
    { id: "experience", label: "Experience" },
    { id: "contact", label: "Contact" },
] as const;

// sections tracked by the scroll-spy (includes ones without a nav link)
const tracked = ["hero", "story", "range", "ai", "projects", "fit", "experience", "systems", "contact"];

export const Navbar = () => {
    const ctx = useGlobalContext();
    let navEl: HTMLElement | undefined;
    // on phones the link row is a horizontally scrollable strip; these flags drive the edge fades
    const [fadeStart, setFadeStart] = createSignal(false);
    const [fadeEnd, setFadeEnd] = createSignal(false);
    const reduceMotion = () => !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

    const updateFades = () => {
        if (!navEl) return;
        const max = navEl.scrollWidth - navEl.clientWidth;
        setFadeStart(navEl.scrollLeft > 2);
        setFadeEnd(max - navEl.scrollLeft > 2);
    };

    const root = () => navEl?.getRootNode() as ShadowRoot | Document | undefined;

    const go = (id: string) => {
        const r = root() as any;
        r?.getElementById?.(id)?.scrollIntoView({ behavior: reduceMotion() ? "auto" : "smooth", block: "start" });
    };

    // keep the active link visible inside the strip. Scrolls only the nav itself
    // (never scrollIntoView, which would also move the page vertically).
    const centerInStrip = (btn: HTMLElement | null | undefined, instant = false) => {
        if (!navEl || !btn || navEl.scrollWidth <= navEl.clientWidth) return;
        const left = btn.offsetLeft - (navEl.clientWidth - btn.offsetWidth) / 2;
        navEl.scrollTo({ left: Math.max(0, left), behavior: instant || reduceMotion() ? "auto" : "smooth" });
    };
    createEffect(() => {
        const id = ctx?.activeSection();
        if (id) centerInStrip(navEl?.querySelector<HTMLElement>(`[data-section="${id}"]`));
    });

    onMount(() => {
        updateFades();
        const ro = new ResizeObserver(updateFades);
        if (navEl) ro.observe(navEl);
        onCleanup(() => ro.disconnect());

        const r = root() as any;
        if (!r?.getElementById) return;
        const sections = tracked.map((id) => r.getElementById(id)).filter(Boolean) as HTMLElement[];
        if (!sections.length) return;

        const io = new IntersectionObserver(
            (entries) => {
                for (const entry of entries) {
                    if (entry.isIntersecting) {
                        const el = entry.target as HTMLElement;
                        ctx?.setActiveSection(el.id);
                        ctx?.setOnDark(el.hasAttribute("data-nav-dark"));
                    }
                }
            },
            { rootMargin: "-14% 0px -80% 0px", threshold: 0 }
        );
        sections.forEach((s) => io.observe(s));
        onCleanup(() => io.disconnect());
    });

    return (
        <>
            <style>{styles}</style>
            <nav
                class="nav"
                classList={{ "nav-fade-start": fadeStart(), "nav-fade-end": fadeEnd() }}
                aria-label="Primary"
                ref={navEl}
                onScroll={updateFades}
                // the browser doesn't scroll this strip to a link reached by Tab, so do it
                // here. Native listener (on:), not Solid's delegated onFocusIn: a focus move
                // between two links inside the shadow root never reaches the document.
                on:focusin={(e) => centerInStrip(e.target as HTMLElement, true)}
            >
                <For each={links}>
                    {(link) => (
                        <button
                            class="nav-link"
                            data-section={link.id}
                            classList={{ active: ctx?.activeSection() === link.id }}
                            aria-current={ctx?.activeSection() === link.id ? "true" : undefined}
                            onClick={() => go(link.id)}
                        >
                            {link.label}
                        </button>
                    )}
                </For>
            </nav>
        </>
    );
};
