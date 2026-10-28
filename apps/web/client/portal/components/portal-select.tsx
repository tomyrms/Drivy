import { cn } from '../../lib/utils';
import { Combobox, ComboboxContent, ComboboxEmpty, ComboboxInput, ComboboxItem, ComboboxList } from '../../components/ui/combobox';
import { Field, FieldDescription, FieldError, FieldLabel } from '../../components/ui/field';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../components/ui/select';

export interface PortalSelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface PortalSelectProps {
  id: string;
  label: string;
  options: readonly PortalSelectOption[];
  value: string | null;
  onValueChange: (value: string | null) => void;
  searchable?: boolean;
  disabled?: boolean;
  error?: string;
  description?: string;
  placeholder?: string;
  emptyText?: string;
  name?: string;
  className?: string;
}

/** A labelled single-value field. Search never creates an option or writes a command. */
export function PortalSelect({ id, label, options, value, onValueChange, searchable = false, disabled = false,
  error, description, placeholder = 'Sélectionner', emptyText = 'Aucun résultat', name, className }: PortalSelectProps) {
  // Preserve a selected identifier when a refreshed list no longer includes it.
  const items = value !== null && !options.some(option => option.value === value)
    ? [...options, { value, label: 'Sélection indisponible', disabled: true }]
    : options;
  const selected = items.find(option => option.value === value) ?? null;
  const describedBy = [description ? `${id}-description` : null, error ? `${id}-error` : null].filter(Boolean).join(' ') || undefined;
  return <Field className={cn('portal-select', className)} data-invalid={Boolean(error)}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    {searchable
      ? <Combobox<PortalSelectOption> items={items} value={selected} name={name} disabled={disabled}
          itemToStringLabel={option => option.label} itemToStringValue={option => option.value}
          isItemEqualToValue={(option, current) => option.value === current.value}
          onValueChange={option => onValueChange(option?.value ?? null)}>
          <ComboboxInput id={id} aria-invalid={Boolean(error)} aria-describedby={describedBy} placeholder={placeholder}
            disabled={disabled} autoComplete="off" />
          <ComboboxContent>
            <ComboboxEmpty>{emptyText}</ComboboxEmpty>
            <ComboboxList>{(option: PortalSelectOption) => <ComboboxItem key={option.value} value={option} disabled={option.disabled}>
              <span className="portal-select-option-label">{option.label}</span>
            </ComboboxItem>}</ComboboxList>
          </ComboboxContent>
        </Combobox>
      : <Select<string> items={items} value={value} onValueChange={onValueChange} name={name} disabled={disabled}>
          <SelectTrigger id={id} aria-invalid={Boolean(error)} aria-describedby={describedBy}>
            <SelectValue placeholder={placeholder} />
          </SelectTrigger>
          <SelectContent alignItemWithTrigger={false}>
            {items.length === 0 && <div className="portal-select-empty" role="status">{emptyText}</div>}
            {items.map(option => <SelectItem key={option.value} value={option.value} disabled={option.disabled}>
              <span className="portal-select-option-label">{option.label}</span>
            </SelectItem>)}
          </SelectContent>
        </Select>}
    {description && <FieldDescription id={`${id}-description`}>{description}</FieldDescription>}
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}
