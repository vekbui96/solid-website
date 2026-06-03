import { createMemo, createEffect, createSignal, Show } from 'solid-js';
// @ts-ignore
import styles from './header.scss?inline'
import { Navbar } from '../NavBar/NavBar';
import { useGlobalContext } from '../../context/GlobalContext';

// section → evolving title (enacts the Backend → Full-Stack → AI arc)
const TITLE_BY_SECTION: Record<string, string> = {
    hero: "Software Engineer",
    story: "Software Engineer",
    range: "Full-Stack Software Engineer",
    ai: "AI Engineer",
    projects: "AI Engineer",
    fit: "AI Engineer",
    experience: "AI Engineer",
    systems: "AI Engineer",
    contact: "AI Engineer",
};

export const Header = () => {
    const ctx = useGlobalContext();
    const toTop = () => {
        const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
        window.scrollTo({ top: 0, behavior: reduce ? "auto" : "smooth" });
    };

    const title = createMemo(() => TITLE_BY_SECTION[ctx?.activeSection() ?? "hero"] ?? "Full-Stack Software Engineer");
    const [fade, setFade] = createSignal(false);

    // crossfade the title whenever it changes
    createEffect((prev) => {
        const t = title();
        if (prev !== undefined && prev !== t && !window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
            setFade(true);
            requestAnimationFrame(() => requestAnimationFrame(() => setFade(false)));
        }
        return t;
    });

    return (
        <>
        <style>{styles}</style>
        <header class="topbar" classList={{ "topbar-dark": ctx?.onDark() }}>
            <button class="brand" onClick={toTop}>
                <span class="brand-name">Ve Bui</span>
                <span class="brand-title" classList={{ "brand-title-fade": fade() }}>
                    <Show when={title() === "AI Engineer"}><span class="brand-spark" aria-hidden="true">✦</span></Show>
                    {title()}
                </span>
            </button>
            <Navbar />
        </header>
        </>
    );
};
