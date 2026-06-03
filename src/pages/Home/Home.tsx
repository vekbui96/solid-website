import { reveal } from "../../utils/reveal";
// @ts-ignore
import styles from "./Home.scss?inline"

// keep the directive in scope for Solid's `use:` compiler transform
false && reveal;

export const Home = () => {
    let storyRef: HTMLElement | undefined;
    let projectsRef: HTMLElement | undefined;

    const scrollTo = (el?: HTMLElement) =>
        el?.scrollIntoView({ behavior: "smooth", block: "start" });

    return (
        <>
            <style>{styles}</style>

            {/* ───────────────────────── HERO ───────────────────────── */}
            <section class="hp-hero">
                <div class="container hp-hero-inner">
                    <div class="hp-hero-copy" use:reveal>
                        <p class="hp-eyebrow">Full-Stack Engineer → AI Systems</p>
                        <h1 class="hp-hero-title">I build software systems that think.</h1>
                        <p class="hp-hero-sub">
                            Six years across backend, full-stack, and cloud — now architecting
                            AI agents and enterprise AI solutions.
                        </p>
                        <div class="hp-cta-row">
                            <button class="hp-btn hp-btn-primary" onClick={() => scrollTo(projectsRef)}>
                                See what I build →
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

            {/* ──────────────────── ACT I — BACKEND ──────────────────── */}
            <section class="hp-act" ref={storyRef} id="story">
                <div class="container hp-act-inner">
                    <div class="hp-act-copy" use:reveal>
                        <p class="hp-eyebrow">01 — Foundations</p>
                        <h2 class="hp-act-title">It started with the backend.</h2>
                        <p class="hp-act-body">
                            APIs, services, integrations, and the data systems that keep everything
                            running. I learned to think in system design, scalability, and reliability —
                            the disciplines that decide whether software survives contact with production.
                        </p>
                        <ul class="hp-beats">
                            <li>System design</li>
                            <li>Scalability</li>
                            <li>Reliability</li>
                            <li>Architecture</li>
                        </ul>
                        <p class="hp-punch">Focused on building software that <strong>works</strong>.</p>
                    </div>
                    <div class="hp-act-visual" use:reveal={{ delay: 120 }}>
                        <svg class="hp-diagram" viewBox="0 0 380 220" role="img" aria-label="Backend topology: client to API to auth, queue, and Postgres">
                            <line class="edge" x1="190" y1="42" x2="190" y2="86" />
                            <line class="edge" x1="170" y1="124" x2="80" y2="176" />
                            <line class="edge" x1="190" y1="124" x2="190" y2="176" />
                            <line class="edge" x1="210" y1="124" x2="305" y2="176" />
                            <rect class="n" x="150" y="8" width="80" height="34" rx="8" />
                            <rect class="n accent" x="140" y="86" width="100" height="38" rx="8" />
                            <rect class="n" x="35" y="176" width="90" height="34" rx="8" />
                            <rect class="n" x="145" y="176" width="90" height="34" rx="8" />
                            <rect class="n" x="260" y="176" width="95" height="34" rx="8" />
                            <text class="lbl" x="190" y="29" text-anchor="middle">client</text>
                            <text class="lbl" x="190" y="109" text-anchor="middle">api / services</text>
                            <text class="lbl" x="80" y="197" text-anchor="middle">auth</text>
                            <text class="lbl" x="190" y="197" text-anchor="middle">queue</text>
                            <text class="lbl" x="307" y="197" text-anchor="middle">postgres</text>
                        </svg>
                        <p class="hp-caption">designed for throughput, indexed for reliability</p>
                    </div>
                </div>
            </section>

            {/* ─────────────────── ACT II — FULL-STACK ─────────────────── */}
            <section class="hp-act hp-act-alt">
                <div class="container hp-act-inner hp-reverse">
                    <div class="hp-act-copy" use:reveal>
                        <p class="hp-eyebrow hp-eyebrow-2">02 — Range</p>
                        <h2 class="hp-act-title">Then I owned the whole product.</h2>
                        <p class="hp-act-body">
                            I expanded into frontend and product, working end-to-end across UI, testing,
                            observability, and cloud. I stopped shipping endpoints and started shipping
                            experiences.
                        </p>
                        <ul class="hp-beats hp-beats-2">
                            <li>Frontend &amp; UX</li>
                            <li>Testing</li>
                            <li>Observability</li>
                            <li>Cloud</li>
                        </ul>
                        <p class="hp-punch">Focused on building software people <strong>enjoy using</strong>.</p>
                    </div>
                    <div class="hp-act-visual" use:reveal={{ delay: 120 }}>
                        <svg class="hp-diagram hp-diagram-2" viewBox="0 0 400 240" role="img" aria-label="Full system: web and mobile clients, API, database, CI/CD, and observability">
                            <line class="edge" x1="90" y1="44" x2="150" y2="92" />
                            <line class="edge" x1="220" y1="44" x2="200" y2="92" />
                            <line class="edge" x1="205" y1="111" x2="255" y2="111" />
                            <line class="edge" x1="130" y1="130" x2="90" y2="190" />
                            <line class="edge" x1="180" y1="130" x2="245" y2="190" />
                            <rect class="n" x="40" y="10" width="100" height="34" rx="8" />
                            <rect class="n" x="170" y="10" width="100" height="34" rx="8" />
                            <rect class="n accent" x="105" y="92" width="100" height="38" rx="8" />
                            <rect class="n" x="255" y="92" width="90" height="38" rx="8" />
                            <rect class="n" x="40" y="190" width="100" height="34" rx="8" />
                            <rect class="n" x="195" y="190" width="110" height="34" rx="8" />
                            <text class="lbl" x="90" y="31" text-anchor="middle">web app</text>
                            <text class="lbl" x="220" y="31" text-anchor="middle">mobile</text>
                            <text class="lbl" x="155" y="115" text-anchor="middle">api</text>
                            <text class="lbl" x="300" y="115" text-anchor="middle">db</text>
                            <text class="lbl" x="90" y="211" text-anchor="middle">ci / cd</text>
                            <text class="lbl" x="250" y="211" text-anchor="middle">observability</text>
                        </svg>
                        <p class="hp-caption">one system, owned end to end</p>
                    </div>
                </div>
            </section>

            {/* ──────────────────── ACT III — AI (dark) ──────────────────── */}
            <section class="hp-act hp-scene-dark hp-act-ai">
                <div class="container hp-act-inner">
                    <div class="hp-act-copy" use:reveal>
                        <p class="hp-eyebrow hp-eyebrow-ai">03 — Intelligence</p>
                        <h2 class="hp-act-title">Now I build systems that think alongside people.</h2>
                        <p class="hp-act-body">
                            I build AI agents, retrieval-augmented generation systems, workflow automation,
                            and enterprise AI solutions — software that amplifies engineering teams and
                            business outcomes.
                        </p>
                        <p class="hp-punch">
                            Focused on systems that help people <strong>think, decide, and work more
                            effectively</strong>.
                        </p>
                    </div>
                    <div class="hp-act-visual" use:reveal={{ delay: 120 }}>
                        <svg class="hp-diagram hp-diagram-ai" viewBox="0 0 420 220" role="img" aria-label="An AI agent layer reasoning above and acting on the engineered system">
                            <rect class="n ai-layer" x="40" y="10" width="340" height="50" rx="12" />
                            <text class="lbl ai-lbl" x="210" y="40" text-anchor="middle">ai / agents · reason · retrieve · act</text>
                            <line class="edge flow" x1="140" y1="60" x2="140" y2="120" />
                            <line class="edge flow" x1="210" y1="60" x2="210" y2="120" />
                            <line class="edge flow" x1="280" y1="60" x2="280" y2="120" />
                            <rect class="n dim" x="90" y="120" width="240" height="74" rx="10" />
                            <text class="lbl" x="210" y="151" text-anchor="middle">engineered system</text>
                            <text class="lbl sub" x="210" y="173" text-anchor="middle">apis · data · cloud · observability</text>
                        </svg>
                        <p class="hp-caption hp-caption-ai">intelligence, grounded in real engineering</p>
                    </div>
                </div>
            </section>

            {/* ──────────────────── PROJECTS (dark) ──────────────────── */}
            <section class="hp-projects hp-scene-dark" ref={projectsRef} id="projects">
                <div class="container">
                    <p class="hp-eyebrow hp-eyebrow-ai">Selected systems</p>
                    <h2 class="hp-section-title">What I'm building.</h2>

                    <div class="hp-cards">
                        <article class="hp-card" use:reveal>
                            <span class="hp-card-num">01</span>
                            <h3 class="hp-card-title">Enterprise Operations Copilot</h3>
                            <p class="hp-card-tag">Natural-language operations over fragmented enterprise data.</p>
                            <div class="hp-flow">
                                <span>chat</span><i>→</i><span>orchestrator</span><i>→</i><span>RAG + tools</span><i>→</i><span>systems of record</span>
                            </div>
                            <dl class="hp-psa">
                                <dt>Problem</dt><dd>Ops teams drown in fragmented systems and tribal knowledge.</dd>
                                <dt>System</dt><dd>An agentic copilot that plans across tools, retrieves grounded context, and executes guarded actions.</dd>
                                <dt>Impact</dt><dd>Faster time-to-answer and fewer escalations.</dd>
                            </dl>
                        </article>

                        <article class="hp-card" use:reveal={{ delay: 90 }}>
                            <span class="hp-card-num">02</span>
                            <h3 class="hp-card-title">AI Incident Commander</h3>
                            <p class="hp-card-tag">Detects, triages, and narrates incidents in real time.</p>
                            <div class="hp-flow">
                                <span>alerts</span><i>→</i><span>reasoning loop</span><i>→</i><span>runbooks</span><i>→</i><span>comms</span>
                            </div>
                            <dl class="hp-psa">
                                <dt>Problem</dt><dd>During incidents, engineers waste critical minutes correlating signals.</dd>
                                <dt>System</dt><dd>An agent that ingests alerts, reasons over telemetry and runbooks, drafts the timeline, and coordinates comms.</dd>
                                <dt>Impact</dt><dd>Lower MTTR and cleaner postmortems.</dd>
                            </dl>
                        </article>

                        <article class="hp-card" use:reveal={{ delay: 180 }}>
                            <span class="hp-card-num">03</span>
                            <h3 class="hp-card-title">AI Codebase Onboarding Agent</h3>
                            <p class="hp-card-tag">Turns a repository into an interactive mentor.</p>
                            <div class="hp-flow">
                                <span>repo index</span><i>→</i><span>graph + RAG</span><i>→</i><span>guided Q&amp;A</span>
                            </div>
                            <dl class="hp-psa">
                                <dt>Problem</dt><dd>New engineers take weeks to get productive in large codebases.</dd>
                                <dt>System</dt><dd>Indexes the repo into a graph and vector store, then serves a conversational mentor that answers where, why, and how — with citations.</dd>
                                <dt>Impact</dt><dd>Faster ramp-up and fewer interrupt questions.</dd>
                            </dl>
                        </article>
                    </div>
                </div>
            </section>

            {/* ──────────────────── CAPABILITIES ──────────────────── */}
            <section class="hp-caps">
                <div class="container">
                    <p class="hp-eyebrow">Capabilities</p>
                    <h2 class="hp-section-title">Systems I can own end-to-end.</h2>
                    <div class="hp-matrix">
                        <div class="hp-row"><span class="hp-row-k">Backend &amp; APIs</span><span class="hp-row-v">Java · Spring Boot · REST · Clojure</span></div>
                        <div class="hp-row"><span class="hp-row-k">Data &amp; Storage</span><span class="hp-row-v">PostgreSQL · schema design · query performance</span></div>
                        <div class="hp-row"><span class="hp-row-k">Cloud &amp; Infra</span><span class="hp-row-v">AWS · CI/CD · observability · on-call</span></div>
                        <div class="hp-row"><span class="hp-row-k">Frontend</span><span class="hp-row-v">TypeScript · SolidJS · micro-frontends</span></div>
                        <div class="hp-row"><span class="hp-row-k">AI Systems</span><span class="hp-row-v">Agents · RAG · workflow automation · evals</span></div>
                    </div>
                </div>
            </section>

            {/* ──────────────────── CLOSE / CTA ──────────────────── */}
            <section class="hp-close">
                <div class="container hp-close-inner" use:reveal>
                    <h2 class="hp-close-title">Let's build intelligent systems together.</h2>
                    <p class="hp-close-sub">
                        I help teams turn deep engineering into AI that delivers measurable outcomes.
                    </p>
                    <div class="hp-cta-row hp-cta-center">
                        <a class="hp-btn hp-btn-primary" href="mailto:tommy.bui1428@gmail.com">Get in touch →</a>
                        <a class="hp-btn hp-btn-ghost" href="https://linkedin.com/in/vekbui96" target="_blank" rel="noopener">LinkedIn</a>
                    </div>
                </div>
            </section>

            {/* ──────────────────── FOOTER ──────────────────── */}
            <footer class="hp-footer">
                <div class="container hp-footer-inner">
                    <span>Ve Bui — Dallas, TX</span>
                    <span class="hp-footer-links">
                        <a href="mailto:tommy.bui1428@gmail.com">Email</a>
                        <a href="https://github.com/vekbui96" target="_blank" rel="noopener">GitHub</a>
                        <a href="https://linkedin.com/in/vekbui96" target="_blank" rel="noopener">LinkedIn</a>
                    </span>
                    <span class="hp-footer-built">Built with SolidJS</span>
                </div>
            </footer>
        </>
    )
}
