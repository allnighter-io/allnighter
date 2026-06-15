import * as React from 'react';

/**
 * A worker in the team or live run grid: brand glyph, name, model ID, and run status.
 * Selectable (team) or read-only (run view).
 * @startingPoint section="Product" subtitle="Worker row — team & live run" viewport="700x150"
 */
export interface WorkerChipProps extends React.HTMLAttributes<HTMLElement> {
  /** Display name, e.g. "Opus 4.8". */
  name: React.ReactNode;
  /** Mono sub-label, e.g. "via claude-code". */
  model?: React.ReactNode;
  /** Brand glyph node (e.g. a Simple Icons <img>). */
  glyph?: React.ReactNode;
  /** Run status — renders a StatusPill. */
  status?: 'queued' | 'running' | 'done' | 'failed' | 'timedout';
  /** Mono trailing meta, e.g. "1,284 tok · 00:42". */
  meta?: React.ReactNode;
  /** Team mode: show a selection checkbox. */
  selectable?: boolean;
  selected?: boolean;
  onToggle?: () => void;
}

export function WorkerChip(props: WorkerChipProps): JSX.Element;
