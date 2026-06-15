import * as React from 'react';

/** Binary on/off toggle for settings — worker enabled, quiet hours, local-only. */
export interface SwitchProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type'> {
  label?: string;
  description?: string;
}

export function Switch(props: SwitchProps): JSX.Element;
