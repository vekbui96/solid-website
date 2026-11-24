import { reveal } from "../../utils/reveal";
import { jumpTo } from "../../utils/jumpTo";
import { Below, Deferred } from "./DeferredSection";
// @ts-ignore
import styles from "./Home.scss?inline"

// keep the directive in scope for Solid's `use:` compiler transform
false && reveal;

export const Home = () => {
    let storyRef: HTMLElement | undefined;
    let projectsRef: HTMLElement | undefined;
    let fitRef: HTMLElement | undefined;

    const scrollTo = (el?: HTMLElement) => jumpTo(el);

    return (
        <>
            <style>{styles}</style>

            {/* ───────────────────────── HERO ───────────────────────── */}
            <section class="hp-hero" id="hero">
                <div class="container hp-hero-inner">
                    <div class="hp-hero-copy" use:reveal>
                        <p class="hp-eyebrow">Software Engineer · Dallas, TX</p>
                        <h1 class="hp-hero-title">I build backends that hold up in production.</h1>
                        <p class="hp-hero-sub">
                            Six years on backend, full-stack, and cloud, most recently building
                            LLM features at Capital One. I like systems that survive real traffic.
                        </p>
                        <div class="hp-cta-row">
                            <button class="hp-btn hp-btn-primary" onClick={() => scrollTo(projectsRef)}>
                                See my work →
                            </button>
                            <button class="hp-btn hp-btn-ai" onClick={() => scrollTo(fitRef)}>
                                Job Analyzer
                            </button>
                            <button class="hp-btn hp-btn-ghost" onClick={() => scrollTo(storyRef)}>
                                Read the story
                            </button>
                        </div>
                    </div>
                    <div class="hp-hero-visual" use:reveal={{ delay: 150 }}>
                        <svg class="hp-diagram" viewBox="0 0 360 80" role="img" aria-label="Client connected to API connected to database">
                            <line class="edge" x1="100" y1="40" x2="135" y2="40" />
                            <line class="edge" x1="225" y1="40" x2="260" y2="40" />
                            <rect class="n" x="10" y="22" width="90" height="36" rx="8" />
                            <rect class="n accent" x="135" y="22" width="90" height="36" rx="8" />
                            <rect class="n" x="260" y="22" width="90" height="36" rx="8" />
                            <text class="lbl" x="55" y="44" text-anchor="middle">client</text>
                            <text class="lbl" x="180" y="44" text-anchor="middle">api</text>
                            <text class="lbl" x="305" y="44" text-anchor="middle">db</text>
                        </svg>
                    </div>
                </div>
            </section>

            {/* Below the fold: the section shells stay here (ids, classes, data-nav-dark, refs)
                so nav, scroll-spy and jump links work at once; their contents load from BelowFold.tsx. */}

            {/* ──────────────────── ACT I — BACKEND ──────────────────── */}
            <section class="hp-act" ref={storyRef} id="story">
                <Deferred minHeight="640px"><Below.Story /></Deferred>
            </section>

            {/* ─────────────────── ACT II — FULL-STACK ─────────────────── */}
            <section class="hp-act hp-act-alt" id="range">
                <Deferred minHeight="640px"><Below.Range /></Deferred>
            </section>

            {/* ──────────────────── ACT III — AI (dark) ──────────────────── */}
            <section class="hp-act hp-scene-dark hp-act-ai" id="ai" data-nav-dark>
                <Deferred minHeight="520px"><Below.Ai /></Deferred>
            </section>

            {/* ──────────────────── PROJECTS (dark) ──────────────────── */}
            <section class="hp-projects hp-scene-dark" ref={projectsRef} id="projects" data-nav-dark>
                <Deferred minHeight="900px"><Below.Projects /></Deferred>
            </section>

            {/* ──────────────────── FIT ANALYZER ──────────────────── */}
            <section class="hp-fit hp-scene-dark" id="fit" data-nav-dark ref={fitRef}>
                <Deferred minHeight="700px"><Below.Fit /></Deferred>
            </section>

            {/* ──────────────────── EXPERIENCE ──────────────────── */}
            <section class="hp-exp hp-scene-dark" id="experience" data-nav-dark>
                <Deferred minHeight="800px"><Below.Experience /></Deferred>
            </section>

            {/* ──────────────────── CAPABILITIES ──────────────────── */}
            <section class="hp-caps hp-scene-dark" id="systems" data-nav-dark>
                <Deferred minHeight="420px"><Below.Systems /></Deferred>
            </section>

            {/* ──────────────────── CLOSE / CTA ──────────────────── */}
            <section class="hp-close hp-scene-dark" id="contact" data-nav-dark>
                <Deferred minHeight="720px"><Below.Contact /></Deferred>
            </section>

            {/* ──────────────────── FOOTER ──────────────────── */}
            <footer class="hp-footer hp-scene-dark">
                <div class="container hp-footer-inner">
                    <span>Ve Bui — Dallas, TX</span>
                    <span class="hp-footer-links">
                        <a href="mailto:tommy.bui1428@gmail.com">Email</a>
                        <a href="./Ve-Bui-Resume.pdf" target="_blank" rel="noopener">Résumé</a>
                        <a href="https://github.com/vekbui96" target="_blank" rel="noopener">GitHub</a>
                        <a href="./storybook/" target="_blank" rel="noopener">Storybook</a>
                        <a href="https://linkedin.com/in/vekbui96" target="_blank" rel="noopener">LinkedIn</a>
                    </span>
                    <span class="hp-footer-built">Built with SolidJS</span>
                </div>
            </footer>
        </>
    )
}
