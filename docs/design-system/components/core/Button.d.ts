import * as React from 'react';

/**
 * Primary action control for Allnighter.
 * @startingPoint section="Core" subtitle="Primary / secondary / ghost / danger button" viewport="700x150"
 */
export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Visual emphasis. `primary` = the single most important action (amber). */
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  /** React node (e.g. an <Icon/>) rendered before the label. */
  iconLeft?: React.ReactNode;
  iconRight?: React.ReactNode;
  /** Stretch to full container width. */
  block?: boolean;
}

export function Button(props: ButtonProps): JSX.Element;
