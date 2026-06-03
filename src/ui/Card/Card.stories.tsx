import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { Card } from './Card';
import { Tag } from '../Tag/Tag';

const meta: Meta<typeof Card> = {
  title: 'Primitives/Card',
  component: Card,
  argTypes: {
    as: { control: 'inline-radio', options: ['div', 'article', 'section', 'li'] },
    interactive: { control: 'boolean' },
  },
  args: {
    interactive: false,
    children: (
      <p style="margin: 0;">
        A surface container themed entirely by design tokens — it inverts cleanly
        in dark scenes.
      </p>
    ),
  },
};

export default meta;
type Story = StoryObj<typeof Card>;

export const Basic: Story = {};

export const Interactive: Story = { args: { interactive: true } };

/** With header + footer slots — the shape used by project / experience cards. */
export const WithHeaderAndFooter: Story = {
  args: {
    as: 'article',
    header: <span>Enterprise Operations Copilot</span>,
    children: (
      <p style="margin: 0;">Natural-language operations over fragmented enterprise data.</p>
    ),
    footer: (
      <div style="display: flex; gap: 0.5rem;">
        <Tag>Java</Tag>
        <Tag>AWS</Tag>
        <Tag variant="ai">AI</Tag>
      </div>
    ),
  },
};
