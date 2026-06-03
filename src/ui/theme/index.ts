// @ts-ignore — Vite resolves the ?inline SCSS query to a compiled CSS string.
import themeCss from './theme.scss?inline';

export { themeCss };

export const THEME_CLASS = 'ui-theme';
export const THEME_DARK_CLASS = 'ui-theme ui-theme--dark';
