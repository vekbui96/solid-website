import type { JSX } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './VisuallyHidden.scss?inline';

export type VisuallyHiddenProps = {
  children?: JSX.Element;
};

/**
 * Hides content visually while keeping it available to screen readers — for
 * labels, status messages, and extra context that sighted users get from
 * layout but assistive tech doesn't.
 */
export const VisuallyHidden = (props: VisuallyHiddenProps) => (
  <>
    <style>{styles}</style>
    <span class="ui-visually-hidden">{props.children}</span>
  </>
);
