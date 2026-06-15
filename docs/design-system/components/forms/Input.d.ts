import * as React from 'react';

/** Single-line text field with optional label, hint/error, mono mode, and prefix/suffix affordances. */
export interface InputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'size'> {
  /** Field label rendered above the control. */
  label?: React.ReactNode;
  /** Helper text below the field. */
  hint?: React.ReactNode;
  /** Error text — also turns the border red and supersedes `hint`. */
  error?: React.ReactNode;
  /** Show the required asterisk on the label. */
  required?: boolean;
  /** Mono leading text inside the field (e.g. a path prefix). */
  prefixText?: React.ReactNode;
  /** Mono trailing text inside the field (e.g. a unit). */
  suffix?: React.ReactNode;
  size?: 'md' | 'lg';
  /** Render the input value in the mono face (for IDs, counts, paths). */
  mono?: boolean;
}

export function Input(props: InputProps): JSX.Element;
