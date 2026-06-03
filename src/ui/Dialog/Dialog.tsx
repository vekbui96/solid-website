import { createEffect, onCleanup, Show } from 'solid-js';
import type { JSX } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './Dialog.scss?inline';

const FOCUSABLE =
  'a[href],button:not([disabled]),textarea:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';

export type DialogProps = {
  open: boolean;
  onClose: () => void;
  /** Accessible name; wired to the dialog via aria-labelledby. */
  title?: string;
  /** Close when the backdrop is clicked (default true). */
  closeOnBackdrop?: boolean;
  class?: string;
  children?: JSX.Element;
};

let dialogSeq = 0;

/**
 * Accessible modal dialog: `role="dialog"` + `aria-modal`, Escape to close,
 * focus moves in on open and is restored to the trigger on close, Tab is
 * trapped inside, and background scroll is locked.
 *
 * Rendered inline as a fixed-position overlay (no portal) so the design tokens
 * and shadow-root styles always apply.
 */
export const Dialog = (props: DialogProps) => {
  let panel: HTMLDivElement | undefined;
  const titleId = `ui-dialog-title-${++dialogSeq}`;

  createEffect(() => {
    if (!props.open) return;

    const prevFocus = document.activeElement as HTMLElement | null;
    queueMicrotask(() => panel?.focus());

    const focusables = () =>
      Array.from(panel?.querySelectorAll<HTMLElement>(FOCUSABLE) ?? []).filter(
        (el) => el.getClientRects().length > 0,
      );

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        props.onClose();
        return;
      }
      if (e.key !== 'Tab' || !panel) return;

      const nodes = focusables();
      if (nodes.length === 0) {
        e.preventDefault();
        panel.focus();
        return;
      }
      const first = nodes[0];
      const last = nodes[nodes.length - 1];
      const active = (panel.getRootNode() as Document | ShadowRoot).activeElement;
      if (e.shiftKey && active === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKey, true);
    const prevOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = 'hidden';

    onCleanup(() => {
      document.removeEventListener('keydown', onKey, true);
      document.documentElement.style.overflow = prevOverflow;
      prevFocus?.focus?.();
    });
  });

  return (
    <>
      <style>{styles}</style>
      <Show when={props.open}>
        <div
          class="ui-dialog__backdrop"
          onClick={() => props.closeOnBackdrop !== false && props.onClose()}
        >
          <div
            ref={panel}
            class={['ui-dialog', props.class].filter(Boolean).join(' ')}
            role="dialog"
            aria-modal="true"
            aria-labelledby={props.title ? titleId : undefined}
            tabindex={-1}
            onClick={(e) => e.stopPropagation()}
          >
            <Show when={props.title}>
              <h2 id={titleId} class="ui-dialog__title">
                {props.title}
              </h2>
            </Show>
            {props.children}
          </div>
        </div>
      </Show>
    </>
  );
};
