import * as React from 'react';

export interface TabItem {
  value: string;
  label: React.ReactNode;
  /** Optional trailing mono count. */
  count?: number;
}

/** Switch between views or filter sets. `segmented` for compact in-panel switches, `underline` for page-level section nav. */
export interface TabsProps {
  variant?: 'segmented' | 'underline';
  items: TabItem[];
  value?: string;
  defaultValue?: string;
  onChange?: (value: string) => void;
  className?: string;
}

export function Tabs(props: TabsProps): JSX.Element;
