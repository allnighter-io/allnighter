import * as React from 'react';

/**
 * The Council's signature status indicator — a pill with a colored dot. `running` blinks (the brand heartbeat).
 * @startingPoint section="Product" subtitle="Worker run status pill" viewport="700x150"
 */
export interface StatusPillProps extends React.HTMLAttributes<HTMLSpanElement> {
  status?: 'queued' | 'running' | 'done' | 'failed' | 'timedout';
  /** Override the default label text. */
  children?: React.ReactNode;
}

export function StatusPill(props: StatusPillProps): JSX.Element;
