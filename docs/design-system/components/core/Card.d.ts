import * as React from 'react';

/** The base surface for grouping content — teams, list rows, stat tiles, upsell blocks. */
export interface CardProps extends React.HTMLAttributes<HTMLElement> {
  variant?: 'default' | 'flush' | 'accent';
  /** Apply default 16px padding. */
  pad?: boolean;
  /** Hover-lift + deeper shadow for clickable cards. */
  interactive?: boolean;
  /** Element to render as. */
  as?: keyof JSX.IntrinsicElements;
  children: React.ReactNode;
}

export function Card(props: CardProps): JSX.Element;
