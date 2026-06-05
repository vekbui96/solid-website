import { splitProps, Show } from 'solid-js';
import type { JSX } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './Tag.scss?inline';

export type TagVariant = 'default' | 'ai';

export type TagProps = {
  variant?: TagVariant;
  /**
   * When provided, the Tag becomes an interactive toggle (`<button>` with
   * `aria-pressed`) — the project filter pills. When omitted it renders as a
   * static chip (`<span>`) — e.g. skill tags.
   */
  pressed?: boolean;
  class?: string;
  children?: JSX.Element;
} & JSX.HTMLAttributes<HTMLElement>;

/**
 * A pill/chip. Static by default (skill tags); becomes a toggle when `pressed`
 * is supplied (discipline filters). The `ai` variant is an accented outline.
 */
export const Tag = (props: TagProps) => {
  const [local, rest] = splitProps(props, ['variant', 'pressed', 'class', 'children']);

  const interactive = () => local.pressed !== undefined;
  const cls = () =>
    [
      'ui-tag',
      `ui-tag--${local.variant ?? 'default'}`,
      interactive() ? 'ui-tag--interactive' : null,
      local.pressed ? 'ui-tag--on' : null,
      local.class,
    ]
      .filter(Boolean)
      .join(' ');

  const Content = () => <>{local.children}</>;

  return (
    <>
      <style>{styles}</style>
      <Show
        when={interactive()}
        fallback={
          <span class={cls()} {...(rest as JSX.HTMLAttributes<HTMLSpanElement>)}>
            <Content />
          </span>
        }
      >
        <button
          type="button"
          class={cls()}
          aria-pressed={local.pressed ? 'true' : 'false'}
          {...(rest as JSX.ButtonHTMLAttributes<HTMLButtonElement>)}
        >
          <Content />
        </button>
      </Show>
    </>
  );
};
