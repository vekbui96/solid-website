import projectsData from "../data/projects.json";

export type Axis = "ai" | "backend" | "frontend" | "platform" | "cloud" | "devex";

export const AXES: { id: Axis; label: string }[] = [
    { id: "ai", label: "AI" },
    { id: "backend", label: "Backend" },
    { id: "frontend", label: "Frontend" },
    { id: "platform", label: "Platform" },
    { id: "cloud", label: "Cloud" },
    { id: "devex", label: "DevEx" },
];

// honest, profile-based candidate strength per axis (0–1)
const STRENGTH: Record<Axis, number> = {
    ai: 0.95, backend: 0.92, frontend: 0.85, platform: 0.85, cloud: 0.78, devex: 0.82,
};

const CONCEPTS: { axis: Axis; terms: string[] }[] = [
    { axis: "ai", terms: ["artificial intelligence", " ai ", "a.i.", "llm", "large language model", "rag", "retrieval-augmented", "retrieval augmented", "agent", "agentic", "genai", "generative", "machine learning", "prompt", "vector", "embedding", "retrieval", "copilot", "chatbot", "nlp"] },
    { axis: "backend", terms: ["backend", "back-end", "back end", " api", "apis", "microservice", "micro-service", "spring boot", "spring", "java", "rest", "grpc", "server-side", "sql", "postgres", "postgresql", "database", "queue", "kafka", "clojure", "bff", "oauth", "authentication"] },
    { axis: "frontend", terms: ["frontend", "front-end", "front end", "react", "solidjs", "solid.js", "vue", "angular", "typescript", "javascript", "html", "css", " ui ", " ux", "user interface", "component library", "design system", "accessibility", "wcag", "ada ", "storybook"] },
    { axis: "platform", terms: ["platform", "developer experience", "developer productivity", "internal tool", "tooling", "framework", "sdk", "governance", "standards", "scalab", "infrastructure", "reusable"] },
    { axis: "cloud", terms: ["aws", "azure", "gcp", "cloud", "kubernetes", "k8s", "docker", "terraform", "ci/cd", "cicd", "devops", "serverless", "lambda", "observability", "monitoring", "reliability", " sre"] },
    { axis: "devex", terms: ["onboarding", "documentation", "workflow", "automation", "productivity", "mentor", "enablement"] },
];

const GAP_TERMS: { term: string; area: string; note: string }[] = [
    { term: "ios", area: "Native iOS development", note: "limited direct experience; closest adjacent is web and micro-frontend work." },
    { term: "android", area: "Native Android development", note: "limited direct experience; closest adjacent is web and micro-frontend work." },
    { term: "swift", area: "Swift", note: "no direct production experience." },
    { term: "kotlin", area: "Kotlin", note: "no direct production experience." },
    { term: "model training", area: "Large-scale ML model training", note: "closest adjacent: applied LLM/agent systems and AI evaluation — not model authoring." },
    { term: "train models", area: "Large-scale ML model training", note: "closest adjacent: applied LLM/agent systems and AI evaluation — not model authoring." },
    { term: "pytorch", area: "Deep-learning frameworks (PyTorch)", note: "I build applied LLM/agent systems rather than authoring models." },
    { term: "tensorflow", area: "Deep-learning frameworks (TensorFlow)", note: "I build applied LLM/agent systems rather than authoring models." },
    { term: "computer vision", area: "Computer vision", note: "adjacent: secure image-processing pipeline (handling, not CV modeling)." },
    { term: "data scien", area: "Data science / statistics", note: "adjacent: large-dataset processing and validation services." },
    { term: "blockchain", area: "Blockchain / web3", note: "no direct experience." },
    { term: "game", area: "Game development", note: "no direct experience." },
];

type Proj = (typeof projectsData)[number] & Record<string, any>;
const projects = projectsData as Proj[];

function projText(p: Proj): string {
    const features = (p.features || []).map((f: any) => `${f.name} ${f.desc}`);
    return [p.title, p.tagline, p.problem, ...(p.skills || []), ...(p.highlights || []), ...(p.categories || []), ...(p.flow || []), ...features]
        .filter(Boolean).join(" • ").toLowerCase();
}

const PROJ_INDEX = projects.map((p) => ({
    id: p.id, title: p.title, categories: p.categories as string[],
    featured: !!p.featured, curated: !!p.curated, text: projText(p),
}));

export interface Evidence { projectId?: string; title: string }
export interface Requirement { text: string; confidence: "strong" | "partial" | "limited"; evidence: Evidence[] }
export interface Strength { title: string; detail: string; projects: { id: string; title: string }[] }
export interface Gap { area: string; note: string }
export interface FitReport {
    matchScore: number;
    bin: string;
    headline: string;
    scoreRationale: string;
    demand: Record<Axis, number>;
    strength: Record<Axis, number>;
    strengths: Strength[];
    requirements: Requirement[];
    gaps: Gap[];
    summary: string;
}

const uniq = <T,>(a: T[]) => [...new Set(a)];
const TERMS = CONCEPTS.flatMap((c) => c.terms);
const AXIS_LABEL = Object.fromEntries(AXES.map((a) => [a.id, a.label])) as Record<Axis, string>;
const AXIS_COPY: Record<Axis, string> = {
    ai: "AI systems — agents, RAG, workflow automation, and evaluation",
    backend: "Backend & APIs — Spring Boot, microservices, data, and security",
    frontend: "Frontend — SolidJS, micro-frontends, component systems, accessibility",
    platform: "Platform engineering — harnesses, internal tooling, standards at scale",
    cloud: "Cloud & reliability — AWS, CI/CD, observability, on-call",
    devex: "Developer experience — onboarding, automation, productivity",
};

export function analyzeFit(jd: string): FitReport {
    const text = ` ${jd.toLowerCase()} `;

    // demand per axis
    const demandRaw = { ai: 0, backend: 0, frontend: 0, platform: 0, cloud: 0, devex: 0 } as Record<Axis, number>;
    for (const c of CONCEPTS) for (const t of c.terms) if (text.includes(t)) demandRaw[c.axis]++;
    const maxDemand = Math.max(1, ...Object.values(demandRaw));
    const demand = {} as Record<Axis, number>;
    (Object.keys(demandRaw) as Axis[]).forEach((a) => (demand[a] = demandRaw[a] / maxDemand));
    const totalSignals = Object.values(demandRaw).reduce((a, b) => a + b, 0);

    // requirement lines straight from the JD (uses their words → feels tailored)
    const rawLines = jd
        .split(/\n|(?<=[.;:])\s+/)
        .map((s) => s.replace(/^[\s•\-*•\d.)]+/, "").trim());
    const seen = new Set<string>();
    const requirements: Requirement[] = rawLines
        .filter((l) => l.length >= 14 && l.length <= 220)
        .map((l) => ({ l, n: TERMS.filter((t) => ` ${l.toLowerCase()} `.includes(t)).length }))
        .filter((x) => x.n > 0)
        .sort((a, b) => b.n - a.n)
        .filter((x) => { const k = x.l.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; })
        .slice(0, 6)
        .map(({ l }) => {
            const lt = ` ${l.toLowerCase()} `;
            const terms = uniq(TERMS.filter((t) => lt.includes(t)));
            const scored = PROJ_INDEX
                .map((p) => ({ p, n: terms.filter((t) => p.text.includes(t.trim())).length + (p.featured ? 0.5 : 0) + (p.curated ? 0.2 : 0) }))
                .filter((x) => x.n > 0)
                .sort((a, b) => b.n - a.n)
                .slice(0, 3);
            const evidence: Evidence[] = scored.map((s) => ({ projectId: s.p.id, title: s.p.title }));
            const strongHit = scored.some((s) => s.p.featured) || scored.length >= 3;
            const confidence: Requirement["confidence"] =
                evidence.length === 0 ? "limited" : evidence.length >= 2 || strongHit ? "strong" : "partial";
            return { text: l, confidence, evidence };
        });

    const withEv = requirements.filter((r) => r.confidence !== "limited").length;
    const coverage = requirements.length ? withEv / requirements.length : 0;

    let alignNum = 0, alignDen = 0;
    (Object.keys(demand) as Axis[]).forEach((a) => { alignNum += demand[a] * STRENGTH[a]; alignDen += demand[a]; });
    const alignment = alignDen ? alignNum / alignDen : 0;

    let score = Math.round((0.5 * coverage + 0.5 * alignment) * 100);
    if (totalSignals < 3) score = Math.min(score, 45);
    if (totalSignals === 0) score = Math.min(score, 22);
    score = Math.max(8, Math.min(98, score));
    const bin = score >= 85 ? "Excellent fit" : score >= 66 ? "Strong fit" : score >= 41 ? "Moderate fit" : "Exploratory fit";

    // strengths — top axes where demand & strength both high
    const strengthAxes = (Object.keys(demand) as Axis[])
        .filter((a) => demand[a] > 0)
        .sort((a, b) => demand[b] * STRENGTH[b] - demand[a] * STRENGTH[a])
        .slice(0, 3);
    const strengths: Strength[] = strengthAxes.map((a) => {
        let chosen = PROJ_INDEX.filter((p) => p.categories.includes(a));
        if (chosen.length === 0) chosen = PROJ_INDEX.filter((p) => p.text.includes(a));
        chosen = chosen.sort((x, y) => Number(y.featured) - Number(x.featured) || Number(y.curated) - Number(x.curated)).slice(0, 3);
        return { title: AXIS_LABEL[a], detail: AXIS_COPY[a], projects: chosen.map((c) => ({ id: c.id, title: c.title })) };
    });

    // gaps — honest
    const gaps: Gap[] = [];
    for (const g of GAP_TERMS) {
        if (text.includes(g.term) && !PROJ_INDEX.some((p) => p.text.includes(g.term)) && !gaps.find((x) => x.area === g.area)) {
            gaps.push({ area: g.area, note: g.note });
        }
    }
    for (const r of requirements.filter((r) => r.confidence === "limited").slice(0, 2)) {
        gaps.push({ area: "Limited direct evidence", note: `"${r.text}" — closest match is adjacent architecture/systems work.` });
    }
    if (gaps.length === 0) {
        gaps.push({ area: "Honest note", note: "No major gaps detected for this role — though I'd still expect a ramp on company-specific systems and domain context." });
    }

    const topLabels = strengthAxes.map((a) => AXIS_LABEL[a]);
    const headline = score >= 66
        ? `Strong alignment on ${topLabels.slice(0, 2).join(" and ") || "core engineering"} — with honest gaps noted below.`
        : score >= 41
            ? `Partial alignment — solid overlap on ${topLabels[0] || "engineering fundamentals"}, lighter in a few areas.`
            : `Exploratory — limited overlap detected. That's worth saying plainly rather than inflating a number.`;
    const scoreRationale = `${withEv} of ${requirements.length || 0} detected requirements have direct project evidence, weighted by alignment with ${topLabels[0] || "core"} strengths.`;
    const summary = score >= 66
        ? `This role lines up well with my experience — especially ${topLabels.slice(0, 2).join(" and ")}. Each requirement below links to a real project as evidence, and I've flagged where I'm lighter so you can judge for yourself.`
        : score >= 41
            ? `There's meaningful overlap, concentrated in ${topLabels[0] || "core engineering"}, alongside areas with less direct evidence. The mapping below is honest about both.`
            : `Based on the text provided, I don't see strong overlap — I'd rather tell you that than inflate a number. If the role is more technical than the description reads, paste more detail and try again.`;

    return { matchScore: score, bin, headline, scoreRationale, demand, strength: STRENGTH, strengths, requirements, gaps, summary };
}
