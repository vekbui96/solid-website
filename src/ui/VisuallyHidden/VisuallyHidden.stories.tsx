import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { VisuallyHidden } from './VisuallyHidden';

const meta: Meta<typeof VisuallyHidden> = {
  title: 'Helpers/VisuallyHidden',
  component: VisuallyHidden,
};

export default meta;
type Story = StoryObj<typeof VisuallyHidden>;

/**
 * The hidden text is read by screen readers but takes no visual space — inspect
 * the DOM or use a screen reader to confirm. Here it gives an icon button an
 * accessible name.
 */
export const Default: Story = {
  render: () => (
    <button type="button" style="font-size: 1.2rem; padding: 0.5rem 0.7rem;">
      ✦<VisuallyHidden>Run the AI job analyzer</VisuallyHidden>
    </button>
  ),
};
