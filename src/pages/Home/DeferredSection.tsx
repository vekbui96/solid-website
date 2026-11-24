import { createSignal, lazy, onMount, Show, Suspense, type JSX } from "solid-js";

// The below-the-fold section contents live in BelowFold.tsx and arrive through one
// dynamic import(). The <section> shells stay in Home.tsx, so ids, refs, the nav's
// scroll-spy and jump links never depend on the chunk having loaded.
const part = <K extends string>(name: K) =>
    lazy(() => import("./BelowFold").then((m: any) => ({ default: m[name] as () => JSX.Element })));

export const Below = {
    Story: part("Story"),
    Range: part("Range"),
    Ai: part("Ai"),
    Projects: part("Projects"),
    Fit: part("Fit"),
    Experience: part("Experience"),
    Systems: part("Systems"),
    Contact: part("Contact"),
};

const [ready, setReady] = createSignal(false);
let armed = false;

// Start loading once the hero has painted and the browser is idle, or as soon as the
// visitor interacts (scroll, pointer, key, focus), whichever comes first.
export const armDeferred = () => {
    if (armed) return;
    armed = true;
    const events = ["scroll", "pointerdown", "keydown", "touchstart", "focusin"];
    const go = () => {
        events.forEach((e) => window.removeEventListener(e, go));
        setReady(true);
    };
    events.forEach((e) => window.addEventListener(e, go, { once: true, passive: true }));
    const idle = (window as any).requestIdleCallback as undefined | ((cb: () => void, o?: object) => void);
    if (idle) idle(go, { timeout: 1500 });
    else setTimeout(go, 300);
};

// Same-height placeholder: reserves the section's space until its content is in.
export const Deferred = (props: { minHeight: string; children: JSX.Element }) => {
    onMount(armDeferred);
    const placeholder = () => <div class="hp-deferred" aria-hidden="true" style={{ "min-height": props.minHeight }} />;
    return (
        <Show when={ready()} fallback={placeholder()}>
            <Suspense fallback={placeholder()}>{props.children}</Suspense>
        </Show>
    );
};
