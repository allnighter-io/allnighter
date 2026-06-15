import * as React from 'react';

export interface SelectOption { value: string; label: React.ReactNode; }

/** Dropdown select — choose the synthesizer, a preset, a risk tier. Trigger + popover list. */
export interface SelectProps {
  label?: string;
  options: SelectOption[];
  value?: string;
  defaultValue?: string;
  onChange?: (value: string) => void;
  placeholder?: string;
  size?: 'md' | 'lg';
  /** Mono face for the value (model IDs). */
  mono?: boolean;
  /** Optional node before the value (e.g. a glyph). */
  leading?: React.ReactNode;
  disabled?: boolean;
  className?: string;
}

export function Select(props: SelectProps): JSX.Element;
