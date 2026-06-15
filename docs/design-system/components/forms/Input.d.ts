import * as React from 'react';

/** Labelled text input with hint, error, and affix slots. Used everywhere data is entered. */
export interface InputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'size' | 'prefix'> {
  label?: string;
  hint?: string;
  error?: string;
  required?: boolean;
  /** Mono prefix shown inside the field, e.g. "ikiro.pro/" or a "$". */
  prefixText?: string;
  suffix?: React.ReactNode;
  size?: 'md' | 'lg';
  /** Render the value in the mono face (slugs, paths, model IDs). */
  mono?: boolean;
}

export function Input(props: InputProps): JSX.Element;
