import type { JSX } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './SkipLink.scss?inline';

export type SkipLinkProps = {
  /** Target anchor — defaults to "#main". */
  href?: string;
  children?: JSX.Element;
};

/**
 * Keyboard-only "skip to content" link. Hidden until focused, then appears at
 * the top-left so keyboard users can jump past the nav. Place it as the first
 * focusable element on the page.
 */
export const SkipLink = (props: SkipLinkProps) => (
  <>
    <style>{styles}</style>
    <a class="ui-skip-link" href={props.href ?? '#main'}>
      {props.children ?? 'Skip to content'}
    </a>
  </>
);
