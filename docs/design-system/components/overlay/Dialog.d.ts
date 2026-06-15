import * as React from 'react';

/** Modal dialog — confirm a destructive action (Stop all, Revert), settings, or a focused form. Closes on backdrop click or Esc. */
export interface DialogProps {
  open: boolean;
  onClose?: () => void;
  title?: React.ReactNode;
  description?: React.ReactNode;
  /** Optional leading icon node. */
  icon?: React.ReactNode;
  iconTone?: 'neutral' | 'accent' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  /** Footer node — usually the action Buttons. */
  footer?: React.ReactNode;
  showClose?: boolean;
  children?: React.ReactNode;
}

export function Dialog(props: DialogProps): JSX.Element | null;
