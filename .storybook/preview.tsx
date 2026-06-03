import type { Preview } from 'storybook-solidjs-vite';
import { themeCss } from '../src/ui/theme';

const preview: Preview = {
  // Wrap every story in the shared design-token theme, with a light/dark toggle
  // in the toolbar so primitives can be checked against both scenes.
  decorators: [
    (Story, context) => {
      const dark = context.globals.theme === 'dark';
      return (
        <>
          <style>{themeCss}</style>
          <div
            class={dark ? 'ui-theme ui-theme--dark' : 'ui-theme'}
            style="padding: 2rem; min-height: 100vh;"
          >
            <Story />
          </div>
        </>
      );
    },
  ],
  globalTypes: {
    theme: {
      description: 'Theme scene (light = Acts I–II, dark = Act III)',
      defaultValue: 'light',
      toolbar: {
        title: 'Theme',
        icon: 'paintbrush',
        items: [
          { value: 'light', title: 'Light' },
          { value: 'dark', title: 'Dark' },
        ],
        dynamicTitle: true,
      },
    },
  },
  parameters: {
    // Show a11y findings in the panel; don't fail the build yet (we fix as we go).
    a11y: { test: 'todo' },
    controls: {
      matchers: { color: /(background|color)$/i, date: /Date$/i },
    },
  },
};

export default preview;
