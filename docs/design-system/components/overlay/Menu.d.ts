import * as React from 'react';

export interface MenuItem {
  label?: React.ReactNode;
  icon?: React.ReactNode;
  onClick?: () => void;
  /** Mono shortcut hint on the right. */
  kbd?: string;
  danger?: boolean;
  /** Render a divider (ignores other fields). */
  divider?: boolean;
  /** Render as a non-interactive section label. */
  heading?: boolean;
}

/** Contextual dropdown menu — the kebab on a run, right-click actions (duplicate, skip, delete). */
export interface MenuProps {
  /** The clickable trigger node (e.g. an IconButton). */
  trigger: React.ReactNode;
  items: MenuItem[];
  align?: 'start' | 'end';
  className?: string;
}

export function Menu(props: MenuProps): JSX.Element;
