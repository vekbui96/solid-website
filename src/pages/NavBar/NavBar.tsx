import { For, onMount, onCleanup } from 'solid-js';
// @ts-ignore
import styles from './NavBar.scss?inline'
import { useGlobalContext } from '../../context/GlobalContext'

const links = [
    { id: "story", label: "Story" },
    { id: "projects", label: "Projects" },
    { id: "experience", label: "Experience" },
    { id: "contact", label: "Contact" },
] as const;

// sections tracked by the scroll-spy (includes ones without a nav link)
const tracked = ["hero", "story", "ai", "projects", "experience", "systems", "contact"];

export const Navbar = () => {
    const ctx = useGlobalContext();
    let navEl: HTMLElement | undefined;

    const root = () => navEl?.getRootNode() as ShadowRoot | Document | undefined;

    const go = (id: string) => {
        const r = root() as any;
        r?.getElementById?.(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
    };

    onMount(() => {
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
            <nav class="nav" ref={navEl}>
                <For each={links}>
                    {(link) => (
                        <button
                            class="nav-link"
                            classList={{ active: ctx?.activeSection() === link.id }}
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
