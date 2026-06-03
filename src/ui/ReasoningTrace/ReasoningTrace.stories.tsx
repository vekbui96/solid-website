import { createSignal, onCleanup } from 'solid-js';
import type { Meta, StoryObj } from 'storybook-solidjs-vite';
import { ReasoningTrace } from './ReasoningTrace';
import type { ReasoningStep, ReasoningStatus } from './ReasoningTrace';

const meta: Meta<typeof ReasoningTrace> = {
  title: 'AI/ReasoningTrace',
  component: ReasoningTrace,
};

export default meta;
type Story = StoryObj<typeof ReasoningTrace>;

/** A snapshot mid-run: two steps done, one running, one queued. */
export const MixedStates: Story = {
  args: {
    label: 'Fit analysis',
    steps: [
      { label: 'Reading the role', status: 'done', detail: 'Parsed 14 requirements' },
      { label: 'Mapping requirements to evidence', status: 'done', detail: '9 projects matched' },
      { label: 'Scoring fit & finding gaps', status: 'active' },
      { label: 'Drafting the summary', status: 'pending' },
    ],
  },
};

/** Error state — a failed step surfaces honestly instead of silently stalling. */
export const WithError: Story = {
  args: {
    label: 'Agent run',
    steps: [
      { label: 'Fetching corpus', status: 'done' },
      { label: 'Calling the model', status: 'error', detail: 'rate limited — retrying' },
      { label: 'Scoring', status: 'pending' },
    ],
  },
};

const LABELS = [
  'Reading the role',
  'Extracting requirements',
  'Mapping requirements to evidence',
  'Scoring fit & finding gaps',
];

/** Live run — steps advance automatically, the way the Fit Analyzer drives it. */
export const Live: Story = {
  render: () => {
    const [n, setN] = createSignal(0);
    const id = setInterval(() => setN((v) => (v + 1) % (LABELS.length + 2)), 850);
    onCleanup(() => clearInterval(id));

    const steps = (): ReasoningStep[] =>
      LABELS.map((label, i) => ({
        label,
        status: (i < n() ? 'done' : i === n() ? 'active' : 'pending') as ReasoningStatus,
      }));

    return <ReasoningTrace steps={steps()} label="Analyzing fit" />;
  },
};
