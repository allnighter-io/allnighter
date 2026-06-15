import * as React from 'react';

/** Icon-only button for toolbars, editor chrome, and card affordances. Always pass `label`. */
export interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'ghost' | 'outline' | 'solid' | 'accent';
  size?: 'sm' | 'md' | 'lg';
  /** Accessible label (also the tooltip). Required. */
  label: string;
  /** The icon node. */
  children: React.ReactNode;
}

export function IconButton(props: IconButtonProps): JSX.Element;
