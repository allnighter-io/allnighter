import * as React from 'react';

/** Compact status or metadata label — plan tiers, counts, categories, model tags. */
export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  tone?: 'neutral' | 'accent' | 'positive' | 'danger' | 'info' | 'warning';
  /** Leading status dot. */
  dot?: boolean;
  /** Use the mono face (for counts, model IDs). */
  mono?: boolean;
  children: React.ReactNode;
}

export function Badge(props: BadgeProps): JSX.Element;
