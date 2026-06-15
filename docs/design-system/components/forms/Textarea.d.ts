import * as React from 'react';

/** Multi-line text field — the prompt composer surface and any long-form entry. Vertically resizable. */
export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  /** Field label rendered above the control. */
  label?: React.ReactNode;
  /** Helper text below the field. */
  hint?: React.ReactNode;
  /** Initial visible rows. Default 4. */
  rows?: number;
  /** Show a live `count/maxLength` readout (requires `maxLength`). */
  showCount?: boolean;
  /** Render content in the mono face. */
  mono?: boolean;
}

export function Textarea(props: TextareaProps): JSX.Element;
