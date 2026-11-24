import { ExperienceList } from "../../components/Experience/Experience";
import { ProjectShowcase } from "../../components/Projects/ProjectShowcase";
import { FitAnalyzer } from "../../components/Fit/FitAnalyzer";
import { ContactForm } from "../../components/Contact/ContactForm";
import { reveal } from "../../utils/reveal";

// keep the directive in scope for Solid's `use:` compiler transform
false && reveal;

// Section contents below the fold. Home.tsx keeps the <section> shells (ids, classes,
// data-nav-dark) so the nav, scroll-spy and jump links work before this chunk arrives;
// everything inside them lives here and is loaded by one dynamic import().

export const Story = () => (
    <div class="container hp-act-inner">
        <div class="hp-act-copy" use:reveal>
            <p class="hp-eyebrow">01 / Backend</p>
            <h2 class="hp-act-title">I started on the backend.</h2>
            <p class="hp-act-body">
                APIs, services, and the databases behind them. I learned to care about
                the unglamorous parts (schema design, indexes, retries, on-call), because
                those are what break at 2am, not the demo.
            </p>
            <ul class="hp-details">
                <li>
                    <span class="hp-d-label">Services</span>
                    <span class="hp-d-desc">Java and Spring Boot in production at Capital One and State Farm, plus some Clojure.</span>
                </li>
                <li>
                    <span class="hp-d-label">Databases</span>
                    <span class="hp-d-desc">Postgres schema design and query tuning for high-volume pipelines.</span>
                </li>
                <li>
                    <span class="hp-d-label">Reliability</span>
                    <span class="hp-d-desc">Monitoring, alerts, and on-call. Kept downtime under 1%.</span>
                </li>
                <li>
                    <span class="hp-d-label">Integrations</span>
                    <span class="hp-d-desc">Queues, third-party APIs, and OAuth between services.</span>
                </li>
            </ul>
            <p class="hp-punch">This is where I learned what "reliable" actually costs.</p>
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
);

export const Range = () => (
    <div class="container hp-act-inner hp-reverse">
        <div class="hp-act-copy" use:reveal>
            <p class="hp-eyebrow hp-eyebrow-2">02 / Full-stack</p>
            <h2 class="hp-act-title">Then I took features end to end.</h2>
            <p class="hp-act-body">
                I moved into the frontend and started owning whole features instead of
                just endpoints: the UI, the tests, the dashboards, and the deploy. Turns
                out the hard part is usually the seams between those, not any one of them.
            </p>
            <ul class="hp-details">
                <li>
                    <span class="hp-d-label">Frontend</span>
                    <span class="hp-d-desc">TypeScript and SolidJS, including a micro-frontend setup and a shared component library.</span>
                </li>
                <li>
                    <span class="hp-d-label">Testing</span>
                    <span class="hp-d-desc">Automated suites and validation across the client, the BFF, and the domain layer.</span>
                </li>
                <li>
                    <span class="hp-d-label">Observability</span>
                    <span class="hp-d-desc">Splunk and New Relic dashboards, trace correlation, and a lot of 504 hunting.</span>
                </li>
                <li>
                    <span class="hp-d-label">Delivery</span>
                    <span class="hp-d-desc">Shipped on AWS with CI/CD pipelines and real rollout planning.</span>
                </li>
            </ul>
            <p class="hp-punch">The interesting work lives in the seams between layers.</p>
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
);

export const Ai = () => (
    <div class="container hp-act-inner">
        <div class="hp-act-copy" use:reveal>
            <p class="hp-eyebrow hp-eyebrow-ai">03 / AI</p>
            <h2 class="hp-act-title">Lately, that means building with LLMs.</h2>
            <p class="hp-act-body">
                At Capital One I build LLM features on top of that same backend work:
                chat over internal data, search that cites its sources, and small tools
                that automate steps people used to do by hand. Same rules as before:
                it has to be reliable and you have to be able to debug it.
            </p>
            <p class="hp-punch">An LLM is just one more unreliable dependency to design around.</p>
        </div>
        <div class="hp-act-visual" use:reveal={{ delay: 120 }}>
            <svg class="hp-diagram hp-diagram-ai" viewBox="0 0 420 220" role="img" aria-label="An AI agent layer reasoning above and acting on the engineered system">
                <rect class="n ai-layer" x="40" y="10" width="340" height="50" rx="12" />
                <text class="lbl ai-lbl" x="210" y="40" text-anchor="middle">llm · retrieve · call tools</text>
                <line class="edge flow" x1="140" y1="60" x2="140" y2="120" />
                <line class="edge flow" x1="210" y1="60" x2="210" y2="120" />
                <line class="edge flow" x1="280" y1="60" x2="280" y2="120" />
                <rect class="n dim" x="90" y="120" width="240" height="74" rx="10" />
                <text class="lbl" x="210" y="151" text-anchor="middle">engineered system</text>
                <text class="lbl sub" x="210" y="173" text-anchor="middle">apis · data · cloud · observability</text>
            </svg>
            <p class="hp-caption hp-caption-ai">the LLM sits on top of normal services</p>
        </div>
    </div>
);

export const Projects = () => (
    <div class="container">
        <p class="hp-eyebrow hp-eyebrow-ai" use:reveal>Projects</p>
        <h2 class="hp-section-title">Things I've built.</h2>

        <ProjectShowcase />
    </div>
);

export const Fit = () => <FitAnalyzer />;

export const Experience = () => (
    <div class="container">
        <p class="hp-eyebrow" use:reveal>Experience</p>
        <h2 class="hp-section-title">Where I've worked.</h2>
        <ExperienceList />
    </div>
);

export const Systems = () => (
    <div class="container">
        <p class="hp-eyebrow">Stack</p>
        <h2 class="hp-section-title">What I work with.</h2>
        <dl class="hp-matrix">
            <div class="hp-row"><dt class="hp-row-k">Backend &amp; APIs</dt><dd class="hp-row-v">Java · Spring Boot · REST · Clojure</dd></div>
            <div class="hp-row"><dt class="hp-row-k">Data &amp; Storage</dt><dd class="hp-row-v">PostgreSQL · schema design · query performance</dd></div>
            <div class="hp-row"><dt class="hp-row-k">Cloud &amp; Infra</dt><dd class="hp-row-v">AWS · CI/CD · observability · on-call</dd></div>
            <div class="hp-row"><dt class="hp-row-k">Frontend</dt><dd class="hp-row-v">TypeScript · SolidJS · micro-frontends</dd></div>
            <div class="hp-row"><dt class="hp-row-k">AI</dt><dd class="hp-row-v">LLM apps · retrieval · tool-calling · evals</dd></div>
        </dl>
    </div>
);

export const Contact = () => (
    <div class="container hp-close-inner" use:reveal>
        <h2 class="hp-close-title">Want to talk?</h2>
        <p class="hp-close-sub">
            I'm open to interesting backend and AI work. Send a note and I'll reply.
        </p>
        <ContactForm />
        <div class="hp-cta-row hp-cta-center">
            <a class="hp-btn hp-btn-ghost" href="mailto:tommy.bui1428@gmail.com">Or just email me →</a>
            <a class="hp-btn hp-btn-ghost" href="./Ve-Bui-Resume.pdf" target="_blank" rel="noopener">Download résumé ↓</a>
            <a class="hp-btn hp-btn-ghost" href="https://linkedin.com/in/vekbui96" target="_blank" rel="noopener">LinkedIn</a>
        </div>
    </div>
);
