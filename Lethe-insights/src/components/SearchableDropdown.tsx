import { useState, useRef, useEffect, useCallback } from 'react';

// =============================================================================
// NORMALIZATION HELPERS - Support both string and {value, label} formats
// =============================================================================

type OptionInput = string | { value: string; label?: string };

function normalizeValue(opt: OptionInput): string {
  if (typeof opt === 'string') return opt;
  if (opt && typeof opt === 'object' && 'value' in opt) {
    return String(opt.value ?? '');
  }
  return '';
}

function normalizeLabel(opt: OptionInput): string {
  if (typeof opt === 'string') return opt;
  if (opt && typeof opt === 'object') {
    return String(opt.label ?? opt.value ?? '');
  }
  return '';
}

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  container: {
    position: 'relative' as const,
    display: 'inline-block',
  } as React.CSSProperties,

  inputWrapper: {
    position: 'relative' as const,
    display: 'flex',
    alignItems: 'center',
  } as React.CSSProperties,

  input: {
    padding: '6px 28px 6px 10px',
    fontSize: '12px',
    width: '80px',
    background: 'rgba(255, 255, 255, 0.06)',
    // Use non-shorthand border props to avoid React warning when merging with inputOpen
    borderWidth: '1px',
    borderStyle: 'solid',
    borderColor: 'rgba(255, 255, 255, 0.1)',
    // Use corner-specific props to avoid mixing with shorthand
    borderTopLeftRadius: '6px',
    borderTopRightRadius: '6px',
    borderBottomLeftRadius: '6px',
    borderBottomRightRadius: '6px',
    color: 'rgba(255, 255, 255, 0.85)',
    outline: 'none',
    cursor: 'pointer',
  } as React.CSSProperties,

  inputOpen: {
    borderBottomLeftRadius: 0,
    borderBottomRightRadius: 0,
    borderColor: 'rgba(100, 140, 255, 0.4)',
  } as React.CSSProperties,

  inputDisabled: {
    opacity: 0.5,
    cursor: 'not-allowed',
    background: 'rgba(255, 255, 255, 0.02)',
  } as React.CSSProperties,

  clearButton: {
    position: 'absolute' as const,
    right: '6px',
    top: '50%',
    transform: 'translateY(-50%)',
    width: '16px',
    height: '16px',
    padding: 0,
    background: 'rgba(255, 255, 255, 0.1)',
    border: 'none',
    borderRadius: '50%',
    color: 'rgba(255, 255, 255, 0.5)',
    fontSize: '10px',
    lineHeight: 1,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  } as React.CSSProperties,

  dropdown: {
    position: 'absolute' as const,
    top: '100%',
    left: 0,
    right: 0,
    maxHeight: '200px',
    overflowY: 'auto' as const,
    background: '#2a2a2a',
    // Use non-shorthand border props to avoid React warning
    borderWidth: '1px',
    borderStyle: 'solid',
    borderColor: 'rgba(255, 255, 255, 0.15)',
    borderTopWidth: 0,
    // Use corner-specific props only
    borderTopLeftRadius: 0,
    borderTopRightRadius: 0,
    borderBottomLeftRadius: '6px',
    borderBottomRightRadius: '6px',
    zIndex: 100,
    boxShadow: '0 4px 12px rgba(0, 0, 0, 0.3)',
  } as React.CSSProperties,

  option: {
    padding: '8px 10px',
    fontSize: '12px',
    color: 'rgba(255, 255, 255, 0.8)',
    cursor: 'pointer',
    transition: 'background 0.1s ease',
  } as React.CSSProperties,

  optionHighlighted: {
    background: 'rgba(100, 140, 255, 0.2)',
  } as React.CSSProperties,

  optionSelected: {
    background: 'rgba(100, 140, 255, 0.15)',
    fontWeight: 500,
  } as React.CSSProperties,

  noResults: {
    padding: '8px 10px',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.4)',
    fontStyle: 'italic' as const,
  } as React.CSSProperties,

  loading: {
    padding: '8px 10px',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,
};

interface SearchableDropdownProps {
  value: string;
  onChange: (value: string) => void;
  /** Options can be strings OR {value, label} objects */
  options: OptionInput[];
  loading?: boolean;
  placeholder?: string;
  width?: number | string;
  disabled?: boolean;
  disabledPlaceholder?: string;
  /** Unique id for the input element (required for accessibility - label association) */
  inputId?: string;
  /** Name attribute for the input element */
  inputName?: string;
}

export function SearchableDropdown({
  value,
  onChange,
  options,
  loading = false,
  placeholder = '',
  width = '80px',
  disabled = false,
  disabledPlaceholder,
  inputId,
  inputName,
}: SearchableDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [highlightedIndex, setHighlightedIndex] = useState(-1);
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Normalize the incoming value prop (could be string or object)
  const normalizedValue = typeof value === 'string' ? value : normalizeValue(value as OptionInput);

  // Filter options based on search term (search both value and label)
  const filteredOptions = options.filter((opt) => {
    const label = normalizeLabel(opt).toLowerCase();
    const val = normalizeValue(opt).toLowerCase();
    const search = searchTerm.toLowerCase();
    return label.includes(search) || val.includes(search);
  });

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
        setSearchTerm('');
        setHighlightedIndex(-1);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Handle keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!isOpen) {
        if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          setIsOpen(true);
        }
        return;
      }

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setHighlightedIndex((prev) =>
            prev < filteredOptions.length - 1 ? prev + 1 : prev
          );
          break;
        case 'ArrowUp':
          e.preventDefault();
          setHighlightedIndex((prev) => (prev > 0 ? prev - 1 : 0));
          break;
        case 'Enter':
          e.preventDefault();
          if (highlightedIndex >= 0 && highlightedIndex < filteredOptions.length) {
            onChange(normalizeValue(filteredOptions[highlightedIndex]));
            setIsOpen(false);
            setSearchTerm('');
            setHighlightedIndex(-1);
          }
          break;
        case 'Escape':
          setIsOpen(false);
          setSearchTerm('');
          setHighlightedIndex(-1);
          break;
      }
    },
    [isOpen, filteredOptions, highlightedIndex, onChange]
  );

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchTerm(e.target.value);
    setHighlightedIndex(0);
    if (!isOpen) {
      setIsOpen(true);
    }
  };

  const handleOptionClick = (option: OptionInput) => {
    onChange(normalizeValue(option));
    setIsOpen(false);
    setSearchTerm('');
    setHighlightedIndex(-1);
  };

  const handleClear = (e: React.MouseEvent) => {
    e.stopPropagation();
    onChange('');
    setSearchTerm('');
    inputRef.current?.focus();
  };

  const handleInputFocus = () => {
    if (!disabled) {
      setIsOpen(true);
    }
  };

  // Find the option that matches current value to display its label
  const selectedOption = options.find((opt) => normalizeValue(opt) === normalizedValue);
  const displayLabel = selectedOption ? normalizeLabel(selectedOption) : normalizedValue;
  const displayValue = isOpen ? searchTerm : displayLabel;
  const effectivePlaceholder = disabled && disabledPlaceholder ? disabledPlaceholder : placeholder;

  return (
    <div ref={containerRef} style={styles.container}>
      <div style={styles.inputWrapper}>
        <input
          ref={inputRef}
          type="search"
          id={inputId}
          name={inputName ?? inputId}
          value={displayValue}
          onChange={handleInputChange}
          onFocus={handleInputFocus}
          onKeyDown={handleKeyDown}
          placeholder={effectivePlaceholder}
          disabled={disabled}
          // Disable browser autofill/autocomplete (Edge "Save info" popup)
          autoComplete="new-password"
          autoCorrect="off"
          autoCapitalize="off"
          spellCheck={false}
          inputMode="search"
          aria-autocomplete="list"
          data-lpignore="true"
          data-form-type="other"
          style={{
            ...styles.input,
            width,
            ...(isOpen ? styles.inputOpen : {}),
            ...(disabled ? styles.inputDisabled : {}),
          }}
        />
        {normalizedValue && !isOpen && (
          <button
            type="button"
            onClick={handleClear}
            style={styles.clearButton}
            aria-label="Clear"
          >
            ×
          </button>
        )}
      </div>

      {isOpen && !disabled && (
        <div style={styles.dropdown}>
          {loading ? (
            <div style={styles.loading}>Loading...</div>
          ) : filteredOptions.length === 0 ? (
            <div style={styles.noResults}>
              {searchTerm ? 'No matches' : 'No options'}
            </div>
          ) : (
            filteredOptions.map((option, index) => (
              <div
                key={normalizeValue(option)}
                onClick={() => handleOptionClick(option)}
                onMouseEnter={() => setHighlightedIndex(index)}
                style={{
                  ...styles.option,
                  ...(index === highlightedIndex ? styles.optionHighlighted : {}),
                  ...(normalizeValue(option) === normalizedValue ? styles.optionSelected : {}),
                }}
              >
                {normalizeLabel(option)}
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
}
