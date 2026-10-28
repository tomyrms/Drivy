import { useContext, useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { Select } from '@base-ui/react/select';
import { Combobox } from '@base-ui/react/combobox';
import { Field, FieldLabel, FieldDescription, FieldError } from './components/ui/field';
import { UiSuspendedContext } from './ui-suspension';
import './choice-field.css';

export type ChoiceOption<T extends string> = { value: T; label: string; disabled?: boolean };
export interface ChoiceFieldProps<T extends string> {
  id?: string;
  name?: string;
  label: string;
  value: T | '';
  onChange: (value: T) => void;
  options: readonly ChoiceOption<T>[];
  hint?: string | undefined;
  error?: string | null | undefined;
  disabled?: boolean | undefined;
  required?: boolean | undefined;
  placeholder?: string;
  appearance?: 'default' | 'filter';
  /** Filter inside the popup. Large lists are searchable by default. */
  search?: boolean;
}

function Chevron() {
  return <svg className="choice-chevron" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="m6 8 4 4 4-4" /></svg>;
}
function Check() {
  return <svg className="choice-check" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="m4.5 10 3.5 3.5 7.5-7.5" /></svg>;
}
function FieldCopy({ id, hint, error }: { id: string; hint?: string | undefined; error?: string | null | undefined }) {
  return <>{hint && <FieldDescription className="caption field-hint" id={`${id}-hint`}>{hint}</FieldDescription>}
    {error && <FieldError className="field-error" id={`${id}-error`}>{error}</FieldError>}</>;
}
const descriptions = (id: string, hint?: string, error?: string | null) =>
  [hint ? `${id}-hint` : '', error ? `${id}-error` : ''].filter(Boolean).join(' ') || undefined;

/** Portals escape clipping, but remain inside a native dialog's modal top layer. */
function useChoiceEnvironment(disabled: boolean | undefined) {
  const suspended = useContext(UiSuspendedContext);
  const frame = useRef<HTMLDivElement>(null);
  const [inheritedDisabled, setInheritedDisabled] = useState(false);
  const [portalContainer, setPortalContainer] = useState<HTMLElement | undefined>(undefined);
  useLayoutEffect(() => {
    const element = frame.current;
    if (!element) return;
    setPortalContainer(element.closest<HTMLElement>('dialog, [data-slot="dialog-content"]') ?? undefined);
    const fieldsets: HTMLFieldSetElement[] = [];
    for (let parent = element.parentElement; parent; parent = parent.parentElement) {
      if (parent instanceof HTMLFieldSetElement) fieldsets.push(parent);
    }
    const refresh = () => setInheritedDisabled(fieldsets.some(fieldset => {
      const firstLegend = [...fieldset.children].find(child => child instanceof HTMLLegendElement);
      return fieldset.disabled && !firstLegend?.contains(element);
    }));
    refresh();
    const observer = new MutationObserver(refresh);
    fieldsets.forEach(fieldset => observer.observe(fieldset, { attributes: true, attributeFilter: ['disabled'] }));
    return () => observer.disconnect();
  }, []);
  return { frame, portalContainer, suspended, unavailable: suspended || !!disabled || inheritedDisabled };
}

/** Single choice. The search string is temporary UI state and is never emitted as a value. */
export function SelectField<T extends string>({ id: suppliedId, name, label, value, onChange, options, hint, error, disabled, required,
  placeholder = 'Choisir', appearance = 'default', search = options.length > 7 }: ChoiceFieldProps<T>) {
  const generatedId = useId(), id = suppliedId ?? generatedId;
  const { frame, portalContainer, unavailable, suspended } = useChoiceEnvironment(disabled);
  const [open, setOpen] = useState(false), [query, setQuery] = useState('');
  const input = useRef<HTMLInputElement>(null);
  const selected = options.find(option => option.value === value) ?? null;
  const labelId = `${id}-label`, describedBy = descriptions(id, hint, error);
  useEffect(() => { if (unavailable) setOpen(false); }, [unavailable]);
  // Escape first closes this menu, even when the browser would otherwise cancel its parent dialog.
  useEffect(() => {
    if (!open || !portalContainer) return;
    const cancel = (event: Event) => { event.preventDefault(); event.stopPropagation(); setOpen(false); };
    portalContainer.addEventListener('cancel', cancel, true);
    return () => portalContainer.removeEventListener('cancel', cancel, true);
  }, [open, portalContainer]);
  const changeOpen = (next: boolean) => { setOpen(next && !unavailable); if (next) setQuery(''); };
  const choose = (next: ChoiceOption<T> | null) => {
    if (!unavailable && next && !next.disabled && options.some(option => option.value === next.value && !option.disabled)) onChange(next.value);
  };
  const triggerProps = { id, className: 'choice-trigger', 'aria-labelledby': labelId, 'aria-describedby': describedBy,
    'aria-invalid': error ? true as const : undefined };
  const triggerCopy = <><span className={selected ? 'choice-value' : 'choice-value choice-placeholder'}>{selected?.label ?? placeholder}</span><Chevron /></>;
  let control: ReactNode;
  if (search) {
    control = <Combobox.Root<ChoiceOption<T>> items={options} value={selected} onValueChange={choose} disabled={unavailable}
      name={name} required={required} open={open && !unavailable} onOpenChange={changeOpen} inputValue={query} onInputValueChange={setQuery}
      itemToStringLabel={option => option.label} itemToStringValue={option => option.value} isItemEqualToValue={(a, b) => a.value === b.value}>
      <Combobox.Trigger {...triggerProps}>{triggerCopy}</Combobox.Trigger>
      <Combobox.Portal container={portalContainer}>
        <Combobox.Positioner className="choice-positioner" {...(suspended ? { hidden: true } : {})} sideOffset={6} align="start" positionMethod="fixed">
          <Combobox.Popup className="choice-popup" initialFocus={input}>
            <div className="choice-search-wrap"><Combobox.Input ref={input} className="choice-search" aria-label={`Rechercher : ${label}`} placeholder="Rechercher…" /></div>
            <Combobox.Empty className="choice-empty">Aucun résultat</Combobox.Empty>
            <Combobox.List className="choice-list">{(option: ChoiceOption<T>) => <Combobox.Item key={option.value} value={option} disabled={option.disabled} className="choice-option">
              <span>{option.label}</span><Combobox.ItemIndicator className="choice-indicator"><Check /></Combobox.ItemIndicator>
            </Combobox.Item>}</Combobox.List>
          </Combobox.Popup>
        </Combobox.Positioner>
      </Combobox.Portal>
    </Combobox.Root>;
  } else {
    control = <Select.Root<T> value={selected?.value ?? null} items={options} name={name} required={required} disabled={unavailable}
      open={open && !unavailable} onOpenChange={changeOpen} modal={false}
      onValueChange={next => choose(options.find(option => option.value === next) ?? null)}>
      <Select.Trigger {...triggerProps}>{triggerCopy}</Select.Trigger>
      <Select.Portal container={portalContainer}>
        <Select.Positioner className="choice-positioner" {...(suspended ? { hidden: true } : {})} sideOffset={6} align="start" positionMethod="fixed" alignItemWithTrigger={false}>
          <Select.Popup className="choice-popup"><Select.List className="choice-list"><Select.Group>
            {options.map(option => <Select.Item key={option.value} value={option.value} disabled={option.disabled} className="choice-option">
              <Select.ItemText>{option.label}</Select.ItemText><Select.ItemIndicator className="choice-indicator"><Check /></Select.ItemIndicator>
            </Select.Item>)}
            {options.length === 0 && <p className="choice-empty">Aucun choix disponible</p>}
          </Select.Group></Select.List></Select.Popup>
        </Select.Positioner>
      </Select.Portal>
    </Select.Root>;
  }
  return <Field ref={frame} data-invalid={!!error} data-disabled={unavailable} className={`field choice-field${error ? ' invalid' : ''}${appearance === 'filter' ? ' choice-filter' : ''}`}>
    <FieldLabel id={labelId} htmlFor={id}>{label}{required === false && <span className="optional">Facultatif</span>}</FieldLabel>
    {control}<FieldCopy id={id} hint={hint} error={error} />
  </Field>;
}

/** Two to four short alternatives: real radio inputs keep native keyboard and form behavior. */
export function SegmentField<T extends string>({ id: suppliedId, name, label, value, onChange, options, hint, error, disabled, required,
  appearance = 'default' }: ChoiceFieldProps<T>) {
  const generatedId = useId(), id = suppliedId ?? generatedId;
  return <fieldset id={id} className={`field choice-field segment-field${error ? ' invalid' : ''}${appearance === 'filter' ? ' choice-filter' : ''}`}
    disabled={disabled} aria-describedby={descriptions(id, hint, error)} aria-invalid={error ? true : undefined} tabIndex={error ? -1 : undefined}>
    <legend>{label}{required === false && <span className="optional">Facultatif</span>}</legend>
    <div className="segment-options">{options.map(option => <label className="segment-option" key={option.value}>
      <input type="radio" name={name ?? id} value={option.value} checked={value === option.value} disabled={disabled || option.disabled} required={required}
        onChange={() => onChange(option.value)} /><span>{option.label}</span>
    </label>)}</div>
    <FieldCopy id={id} hint={hint} error={error} />
  </fieldset>;
}
