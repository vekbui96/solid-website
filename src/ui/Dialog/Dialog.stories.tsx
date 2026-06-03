import { createSignal } from 'solid-js';
import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { Dialog } from './Dialog';
import { Button } from '../Button/Button';

const meta: Meta<typeof Dialog> = {
  title: 'Primitives/Dialog',
  component: Dialog,
};

export default meta;
type Story = StoryObj<typeof Dialog>;

/**
 * Open it, then try: Escape to close, Tab to cycle focus inside, click the
 * backdrop to dismiss. Focus returns to the trigger on close.
 */
export const Default: Story = {
  render: () => {
    const [open, setOpen] = createSignal(false);
    return (
      <>
        <Button onClick={() => setOpen(true)}>Open dialog</Button>
        <Dialog open={open()} onClose={() => setOpen(false)} title="Spec-Driven Development Harness">
          <p style="margin: 0 0 1.25rem; color: var(--muted);">
            A company harness that scales AI-assisted development across an organization.
            Focus is trapped here, Escape closes, and focus returns to the button.
          </p>
          <div style="display: flex; gap: 0.6rem; justify-content: flex-end;">
            <Button variant="ghost" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => setOpen(false)}>Got it</Button>
          </div>
        </Dialog>
      </>
    );
  },
};
