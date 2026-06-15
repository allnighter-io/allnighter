import * as React from 'react';

/** Transient notification — "Master plan ready", "Published", "Landed · revert". Calm, factual, never salesy. */
export interface ToastProps extends React.HTMLAttributes<HTMLDivElement> {
  tone?: 'default' | 'accent' | 'positive' | 'danger';
  title?: React.ReactNode;
  description?: React.ReactNode;
  /** Leading icon node (e.g. the live mark, or a Lucide Icon). */
  icon?: React.ReactNode;
  /** Trailing action node (e.g. a ghost Button "View" / "Undo"). */
  action?: React.ReactNode;
  onClose?: () => void;
}

export function Toast(props: ToastProps): JSX.Element;
