import { createSignal, Show } from "solid-js";
import { submitContact } from "../../lib/api";
// @ts-ignore
import styles from "./ContactForm.scss?inline";

type Status = "idle" | "sending" | "sent" | "error";

export const ContactForm = () => {
    const [name, setName] = createSignal("");
    const [email, setEmail] = createSignal("");
    const [message, setMessage] = createSignal("");
    const [status, setStatus] = createSignal<Status>("idle");
    const [feedback, setFeedback] = createSignal("");
    const [errors, setErrors] = createSignal<Record<string, string>>({});

    const fieldErr = (f: string) => errors()[f];

    const submit = async (e: Event) => {
        e.preventDefault();
        if (status() === "sending") return;
        setStatus("sending");
        setFeedback("");
        setErrors({});

        const result = await submitContact({
            name: name().trim(),
            email: email().trim(),
            message: message().trim(),
        });

        if (result.ok) {
            setStatus("sent");
            setFeedback(result.message);
            setName(""); setEmail(""); setMessage("");
        } else {
            setStatus("error");
            setFeedback(result.message);
            if (result.fieldErrors) setErrors(result.fieldErrors);
        }
    };

    return (
        <>
            <style>{styles}</style>
            <form class="cf-form" onSubmit={submit} novalidate>
                <div class="cf-field">
                    <label class="cf-label" for="cf-name">Name</label>
                    <input
                        id="cf-name"
                        class="cf-input"
                        type="text"
                        autocomplete="name"
                        value={name()}
                        onInput={(e) => setName(e.currentTarget.value)}
                        aria-invalid={fieldErr("name") ? "true" : undefined}
                        aria-describedby={fieldErr("name") ? "cf-name-err" : undefined}
                    />
                    <Show when={fieldErr("name")}>
                        <span id="cf-name-err" class="cf-err">{fieldErr("name")}</span>
                    </Show>
                </div>

                <div class="cf-field">
                    <label class="cf-label" for="cf-email">Email</label>
                    <input
                        id="cf-email"
                        class="cf-input"
                        type="email"
                        autocomplete="email"
                        value={email()}
                        onInput={(e) => setEmail(e.currentTarget.value)}
                        aria-invalid={fieldErr("email") ? "true" : undefined}
                        aria-describedby={fieldErr("email") ? "cf-email-err" : undefined}
                    />
                    <Show when={fieldErr("email")}>
                        <span id="cf-email-err" class="cf-err">{fieldErr("email")}</span>
                    </Show>
                </div>

                <div class="cf-field">
                    <label class="cf-label" for="cf-message">Message</label>
                    <textarea
                        id="cf-message"
                        class="cf-input cf-textarea"
                        rows="5"
                        value={message()}
                        onInput={(e) => setMessage(e.currentTarget.value)}
                        aria-invalid={fieldErr("message") ? "true" : undefined}
                        aria-describedby={fieldErr("message") ? "cf-message-err" : undefined}
                    />
                    <Show when={fieldErr("message")}>
                        <span id="cf-message-err" class="cf-err">{fieldErr("message")}</span>
                    </Show>
                </div>

                <div class="cf-actions">
                    <button class="cf-submit" type="submit" disabled={status() === "sending"}>
                        {status() === "sending" ? "Sending…" : "Send message →"}
                    </button>
                </div>

                <p
                    class="cf-feedback"
                    classList={{ "cf-ok": status() === "sent", "cf-bad": status() === "error" }}
                    role="status"
                    aria-live="polite"
                >
                    {feedback()}
                </p>
            </form>
        </>
    );
};
