import type { StorybookConfig } from 'storybook-solidjs-vite';

const config: StorybookConfig = {
  framework: { name: 'storybook-solidjs-vite', options: {} },
  stories: ['../src/ui/**/*.stories.@(ts|tsx)'],
  addons: ['@storybook/addon-a11y'],
};

export default config;
