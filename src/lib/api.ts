// Tiny client for the personal-site backend (Spring Boot on Render).
// Base URL is overridable at build time via VITE_API_URL; otherwise it points
// at the deployed service. The site is static (GitHub Pages), so this value is
// baked in at `vite build` time.
const API_BASE: string =
    (import.meta as any).env?.VITE_API_URL ?? "https://solid-website-api.onrender.com";

export interface ContactPayload {
    name: string;
    email: string;
    message: string;
}

export interface ContactResult {
    ok: boolean;
    message: string;
    /** field -> message, mirrors the backend's 400 validation response */
    fieldErrors?: Record<string, string>;
}

export async function submitContact(payload: ContactPayload): Promise<ContactResult> {
    try {
        const res = await fetch(`${API_BASE}/api/contact`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
        });

        const data = await res.json().catch(() => ({} as any));

        if (res.ok) {
            return { ok: true, message: data.message ?? "Thanks — I'll be in touch soon." };
        }
        if (res.status === 400 && data.errors) {
            return {
                ok: false,
                message: data.message ?? "Please fix the highlighted fields.",
                fieldErrors: data.errors,
            };
        }
        return {
            ok: false,
            message: data.message ?? `Something went wrong (HTTP ${res.status}). Please try again.`,
        };
    } catch {
        // Network error or the free-tier service waking from a cold start.
        return {
            ok: false,
            message: "Couldn't reach the server — it may be waking up. Please try again in a moment.",
        };
    }
}
