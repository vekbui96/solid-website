import { splitProps, Show } from 'solid-js';
import { Dynamic } from 'solid-js/web';
import type { JSX } from 'solid-js';
// @ts-ignore — Vite resolves ?inline SCSS to a CSS string.
import styles from './Card.scss?inline';

export type CardProps = {
  /** Underlying element — `article` for project/experience cards, `div` otherwise. */
  as?: 'div' | 'article' | 'section' | 'li';
  /** Adds hover lift + pointer affordance (clickable cards). */
  interactive?: boolean;
  /** Optional header / footer regions; body is `children`. */
  header?: JSX.Element;
  footer?: JSX.Element;
  class?: string;
  children?: JSX.Element;
} & JSX.HTMLAttributes<HTMLElement>;

/**
 * Surface container themed by tokens (so it inverts cleanly in dark scenes).
 * Optional `header`/`footer` slots; everything else goes in the body.
 */
export const Card = (props: CardProps) => {
  const [local, rest] = splitProps(props, [
    'as',
    'interactive',
    'header',
    'footer',
    'class',
    'children',
  ]);

  const cls = () =>
    ['ui-card', local.interactive ? 'ui-card--interactive' : null, local.class]
      .filter(Boolean)
      .join(' ');

  return (
    <>
      <style>{styles}</style>
      <Dynamic component={local.as ?? 'div'} class={cls()} {...rest}>
        <Show when={local.header}>
          <div class="ui-card__header">{local.header}</div>
        </Show>
        <div class="ui-card__body">{local.children}</div>
        <Show when={local.footer}>
          <div class="ui-card__footer">{local.footer}</div>
        </Show>
      </Dynamic>
    </>
  );
};
