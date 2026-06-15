import * as React from 'react';

/** Multi-line input for prompts, bios, and notes. Optional live character counter. */
export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
  hint?: string;
  rows?: number;
  /** Show a live count when `maxLength` is set. */
  showCount?: boolean;
  /** Mono face (for prompts / code). */
  mono?: boolean;
}

export function Textarea(props: TextareaProps): JSX.Element;
