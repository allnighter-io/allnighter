import * as React from 'react';

export interface TabItem {
  /** Stable identifier passed to `onChange` and matched against `value`. */
  value: string;
  /** Visible label. */
  label: React.ReactNode;
  /** Optional trailing mono count, e.g. answers count. */
  count?: React.ReactNode;
}

/** Tab strip for switching views — `segmented` (a control) or `underline` (a header). Controlled or uncontrolled. */
export interface TabsProps extends Omit<React.HTMLAttributes<HTMLDivElement>, 'onChange'> {
  variant?: 'segmented' | 'underline';
  /** The tabs to render. */
  items: TabItem[];
  /** Controlled active value. */
  value?: string;
  /** Uncontrolled initial value (defaults to the first item). */
  defaultValue?: string;
  /** Fires with the new value on select. */
  onChange?: (value: string) => void;
}

export function Tabs(props: TabsProps): JSX.Element;
