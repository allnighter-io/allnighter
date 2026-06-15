import * as React from 'react';

/** On/off toggle for settings and preferences. The thumb springs; the track turns amber when on. */
export interface SwitchProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type'> {
  /** Inline label beside the track. */
  label?: React.ReactNode;
  /** Secondary description under the label. */
  description?: React.ReactNode;
}

export function Switch(props: SwitchProps): JSX.Element;
