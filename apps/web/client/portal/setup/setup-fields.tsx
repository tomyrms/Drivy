import { useEffect, useId, useState, type ComponentProps, type ReactNode } from 'react';
import { ChevronRight } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Field, FieldDescription, FieldError, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { InputGroup, InputGroupAddon, InputGroupInput, InputGroupText } from '../../components/ui/input-group';
import { Label } from '../../components/ui/label';
import { Textarea } from '../../components/ui/textarea';

/**
 * Labelled controls of the guide. `name` carries the draft path (`formations.0.priceCents`) so that a server issue
 * can move the focus to its field, as in the historical guide.
 */
type TextFieldProps = {
  name: string; label: string; value: string; onChange: (value: string) => void; error?: string | null; description?: string;
  optional?: boolean; suffix?: string; prefix?: string; className?: string;
} & Omit<ComponentProps<'input'>, 'name' | 'value' | 'onChange' | 'prefix'>;

export function TextField({ name, label, value, onChange, error, description, optional = false, suffix, prefix, className, ...input }: TextFieldProps) {
  const id = useId();
  const describedBy = [description ? `${id}-description` : null, error ? `${id}-error` : null].filter(Boolean).join(' ') || undefined;
  const common = { id, name, value, 'aria-invalid': !!error || undefined, 'aria-describedby': describedBy, onChange: (event: { target: { value: string } }) => onChange(event.target.value), ...input };
  return <Field data-invalid={!!error || undefined} className={className}>
    <FieldLabel htmlFor={id}>{label}{optional && <span className="setup-optional">facultatif</span>}</FieldLabel>
    {suffix || prefix
      ? <InputGroup>
          {prefix && <InputGroupAddon><InputGroupText>{prefix}</InputGroupText></InputGroupAddon>}
          <InputGroupInput {...common} />
          {suffix && <InputGroupAddon align="inline-end"><InputGroupText>{suffix}</InputGroupText></InputGroupAddon>}
        </InputGroup>
      : <Input {...common} />}
    {description && <FieldDescription id={`${id}-description`}>{description}</FieldDescription>}
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}

export function TextAreaField({ name, label, value, onChange, error, rows = 4, maxLength, optional = false, disabled }: {
  name: string; label: string; value: string; onChange: (value: string) => void; error?: string | null; rows?: number; maxLength?: number; optional?: boolean; disabled?: boolean;
}) {
  const id = useId();
  return <Field data-invalid={!!error || undefined}>
    <FieldLabel htmlFor={id}>{label}{optional && <span className="setup-optional">facultatif</span>}</FieldLabel>
    <Textarea id={id} name={name} rows={rows} maxLength={maxLength} value={value} disabled={disabled} aria-invalid={!!error || undefined}
      aria-describedby={error ? `${id}-error` : undefined} onChange={event => onChange(event.target.value)} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}

export function CheckRow({ label, checked, onChange, disabled }: { label: string; checked: boolean; onChange: (value: boolean) => void; disabled?: boolean }) {
  const id = useId();
  return <div className="setup-check">
    <Checkbox id={id} checked={checked} disabled={disabled} onCheckedChange={value => onChange(value === true)} />
    <Label htmlFor={id}>{label}</Label>
  </div>;
}

/** Secondary content, closed by default; opened when one of its fields is the target of a review issue. */
export function Disclosure({ title, open: wanted = false, children, meta }: { title: string; open?: boolean; children: ReactNode; meta?: ReactNode }) {
  const [open, setOpen] = useState(wanted);
  useEffect(() => { if (wanted) setOpen(true); }, [wanted]);
  return <Collapsible open={open} onOpenChange={setOpen} className="setup-disclosure">
    <CollapsibleTrigger render={<Button variant="ghost" className="setup-disclosure-trigger" />}>
      <ChevronRight aria-hidden="true" /><span>{title}</span>{meta}
    </CollapsibleTrigger>
    <CollapsibleContent className="setup-disclosure-content">{children}</CollapsibleContent>
  </Collapsible>;
}
