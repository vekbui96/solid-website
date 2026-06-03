import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { Tag } from './Tag';

const meta: Meta<typeof Tag> = {
  title: 'Primitives/Tag',
  component: Tag,
  argTypes: {
    variant: { control: 'inline-radio', options: ['default', 'ai'] },
    pressed: { control: 'boolean' },
  },
  args: { children: 'Backend' },
};

export default meta;
type Story = StoryObj<typeof Tag>;

/** Static chip — used for skill tags (Java, AWS, …). */
export const Static: Story = {};

/** Interactive toggle — the discipline filter pills. */
export const Filter: Story = { args: { pressed: false, children: 'Frontend' } };

export const FilterSelected: Story = { args: { pressed: true, children: 'Frontend' } };

/** The ✦ AI variant — gradient border + glow to draw the click. */
export const AI: Story = { args: { variant: 'ai', pressed: false, children: 'AI' } };

export const AISelected: Story = { args: { variant: 'ai', pressed: true, children: 'AI' } };
