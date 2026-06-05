import { splitProps, Show } from 'solid-js';
import type { JSX } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './Button.scss?inline';

export type ButtonVariant = 'primary' | 'ghost' | 'ai';
export type ButtonSize = 'sm' | 'md';

export type ButtonProps = {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** When set, the button renders as an `<a>` (for downloads, external links). */
  href?: string;
  type?: 'button' | 'submit' | 'reset';
  disabled?: boolean;
  class?: string;
  children?: JSX.Element;
} & JSX.HTMLAttributes<HTMLElement>;

/**
 * The site's primary action. The `ai` variant is an accented outline used for
 * the Job Analyzer call-to-action. Theming comes entirely from design tokens,
 * so it adapts to light and dark scenes automatically.
 */
export const Button = (props: ButtonProps) => {
  const [local, rest] = splitProps(props, [
    'variant',
    'size',
    'href',
    'type',
    'disabled',
    'class',
    'children',
  ]);

  const cls = () =>
    [
      'ui-btn',
      `ui-btn--${local.variant ?? 'primary'}`,
      `ui-btn--${local.size ?? 'md'}`,
      local.class,
    ]
      .filter(Boolean)
      .join(' ');

  const Content = () => <>{local.children}</>;

  return (
    <>
      <style>{styles}</style>
      <Show
        when={local.href !== undefined}
        fallback={
          <button
            class={cls()}
            type={local.type ?? 'button'}
            disabled={local.disabled}
            {...(rest as JSX.ButtonHTMLAttributes<HTMLButtonElement>)}
          >
            <Content />
          </button>
        }
      >
        <a
          class={cls()}
          href={local.href}
          aria-disabled={local.disabled ? 'true' : undefined}
          {...(rest as JSX.AnchorHTMLAttributes<HTMLAnchorElement>)}
        >
          <Content />
        </a>
      </Show>
    </>
  );
};
