import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { SkipLink } from './SkipLink';

const meta: Meta<typeof SkipLink> = {
  title: 'Helpers/SkipLink',
  component: SkipLink,
};

export default meta;
type Story = StoryObj<typeof SkipLink>;

/** Press Tab to reveal the link (it's hidden until focused). */
export const Default: Story = {
  render: () => (
    <div style="position: relative; height: 120px;">
      <SkipLink href="#main" />
      <p style="color: var(--muted);">Press Tab — the skip link slides in at the top-left.</p>
    </div>
  ),
};
