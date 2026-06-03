import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'Primitives/Button',
  component: Button,
  argTypes: {
    variant: { control: 'inline-radio', options: ['primary', 'ghost', 'ai'] },
    size: { control: 'inline-radio', options: ['sm', 'md'] },
    disabled: { control: 'boolean' },
    href: { control: 'text' },
  },
  args: { children: 'Button', variant: 'primary', size: 'md' },
};

export default meta;
type Story = StoryObj<typeof Button>;

export const Primary: Story = {};

export const Ghost: Story = { args: { variant: 'ghost' } };

export const AI: Story = { args: { variant: 'ai', children: 'Job Analyzer' } };

export const Small: Story = { args: { size: 'sm' } };

export const Disabled: Story = { args: { disabled: true } };

/** Renders as an `<a>` when `href` is set — used for the résumé download. */
export const AsLink: Story = {
  args: { href: '#', variant: 'ghost', children: 'Download résumé ↓' },
};
