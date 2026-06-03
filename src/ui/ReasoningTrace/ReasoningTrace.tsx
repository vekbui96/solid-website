import { Index, Show } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './ReasoningTrace.scss?inline';

export type ReasoningStatus = 'pending' | 'active' | 'done' | 'error';

export interface ReasoningStep {
  label: string;
  status?: ReasoningStatus;
  /** Optional sub-line — e.g. "9 projects matched". */
  detail?: string;
}

export type ReasoningTraceProps = {
  steps: ReasoningStep[];
  /** Accessible name for the list of steps. */
  label?: string;
  class?: string;
};

/**
 * A live "thinking" / agent-step timeline: a vertical trace whose steps move
 * through pending → active → done (or error). Extracted from the site's Fit
 * Analyzer and generalized so it can narrate any agent run or tool sequence.
 *
 * Accessibility: rendered as an ordered list with `aria-live="polite"` so
 * progress is announced, the active step carries `aria-current="step"`, and
 * done/error states have screen-reader-only text since the dot color is the
 * only visual cue.
 */
export const ReasoningTrace = (props: ReasoningTraceProps) => {
  const cls = () => ['ui-rt', props.class].filter(Boolean).join(' ');

  return (
    <>
      <style>{styles}</style>
      <ol class={cls()} aria-label={props.label ?? 'Reasoning steps'} aria-live="polite">
        <Index each={props.steps}>
          {(item) => {
            const status = () => item().status ?? 'pending';
            return (
              <li
                class="ui-rt__step"
                classList={{
                  'ui-rt__step--active': status() === 'active',
                  'ui-rt__step--done': status() === 'done',
                  'ui-rt__step--error': status() === 'error',
                }}
                aria-current={status() === 'active' ? 'step' : undefined}
              >
                <span class="ui-rt__dot" aria-hidden="true" />
                <span class="ui-rt__body">
                  <span class="ui-rt__label">
                    {item().label}
                    <Show when={status() === 'active'}>
                      <span class="ui-rt__ellipsis" aria-hidden="true">…</span>
                    </Show>
                    <Show when={status() === 'done'}>
                      <span class="ui-rt__sr"> — done</span>
                    </Show>
                    <Show when={status() === 'error'}>
                      <span class="ui-rt__sr"> — failed</span>
                    </Show>
                  </span>
                  <Show when={item().detail}>
                    <span class="ui-rt__detail">{item().detail}</span>
                  </Show>
                </span>
              </li>
            );
          }}
        </Index>
      </ol>
    </>
  );
};
