import { useEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { ArrowLeft, ArrowRight } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Skeleton } from '../../components/ui/skeleton';
import type { LaneOutcome } from '../../command-lane';
import { useConsole, type Loaded } from '../../console/context';
import type { FieldChange } from './formation-diff';
import './formations.css';

/** Lecture en cours ou en échec : jamais une page vide ni un état indéfini. */
export function ReadFeedback({ loaded, label = 'Chargement' }: { loaded: Pick<Loaded<unknown>, 'status' | 'error' | 'reload' | 'needsLogin'>; label?: string }) {
  const context = useConsole();
  if (loaded.status === 'loading') return <div className="cat-loading" role="status" aria-label={label}><Skeleton className="h-8 w-56" /><Skeleton className="h-24 w-full" /><Skeleton className="h-24 w-full" /></div>;
  if (loaded.status !== 'error') return null;
  return <Alert variant="destructive"><AlertTitle>Lecture impossible</AlertTitle><AlertDescription>{loaded.error}</AlertDescription>
    <div className="cat-alert-actions"><Button variant="outline" onClick={loaded.reload}>Réessayer</Button>{loaded.needsLogin && <Button variant="outline" onClick={() => context.login()}>Se reconnecter</Button>}</div></Alert>;
}

/** Titre d'une édition : reçoit le focus une seule fois à l'ouverture, jamais pendant la saisie. */
export function useFocusOnMount<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  useEffect(() => { ref.current?.focus(); }, []);
  return ref;
}

/** Rend ses enfants dans l'emplacement d'actions de la rangée d'onglets, ou à la place si la fiche n'en fournit pas. */
export function ActionSlot({ slot, children }: { slot: HTMLElement | null | undefined; children: ReactNode }) {
  return slot ? createPortal(children, slot) : <>{children}</>;
}

export function BackButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  return <Button variant="ghost" className="cat-back" onClick={onClick}><ArrowLeft data-icon="inline-start" />{children}</Button>;
}

/** Repère du permis : le code de la catégorie, jamais une icône inventée. */
export function PermitMark({ code }: { code: string }) {
  return <span className="cat-mark" aria-hidden="true">{code.slice(0, 4)}</span>;
}

/** Seuls les états inhabituels reçoivent un badge. */
export function StateBadge({ badge }: { badge: { tone: 'neutral' | 'warning'; label: string } | null }) {
  return badge ? <Badge variant="secondary" className="cat-badge" data-tone={badge.tone}>{badge.label}</Badge> : null;
}

/** Valeur d'avant et d'après, lisible sans comparer deux textes. */
export function ChangeList({ rows }: { rows: readonly FieldChange[] }) {
  return <dl className="cat-changes">{rows.map(row => <div key={row.label}>
    <dt>{row.label}</dt>
    <dd>{row.before ? <><span className="cat-before">{row.before}</span><ArrowRight aria-hidden="true" /><span className="visually-hidden"> devient </span></> : null}<strong>{row.after}</strong></dd>
  </div>)}</dl>;
}

/**
 * Relecture avant envoi : la saisie reste en place derrière, rien n'est confirmé avant la réponse de l'école. `outcome` porte le refus
 * d'une intention de la voie de commandes ; `runner` reste accepté pour les appelants qui n'ont pas encore migré.
 */
export function ReviewDialog({ open, title, description, confirmLabel, busy, disabled = false, runner, outcome, onClose, onConfirm, children }: {
  open: boolean; title: string; description?: string | undefined; confirmLabel: string; busy: boolean; disabled?: boolean;
  runner?: { readonly outcome: LaneOutcome | null }; outcome?: LaneOutcome | null; onClose: () => void; onConfirm: () => void; children: ReactNode;
}) {
  const notice = outcome !== undefined ? outcome : runner?.outcome ?? null;
  return <Dialog open={open} onOpenChange={(next, details) => { if (busy) { details.cancel(); return; } if (!next) onClose(); }}>
    <DialogContent showCloseButton={!busy} className="cat-dialog">
      <DialogHeader><DialogTitle>{title}</DialogTitle>{description && <DialogDescription>{description}</DialogDescription>}</DialogHeader>
      <div className="cat-dialog-body">{children}</div>
      {notice?.tone === 'error' && <Alert variant="destructive"><AlertTitle>{notice.title}</AlertTitle><AlertDescription>{notice.message}</AlertDescription></Alert>}
      <DialogFooter>
        <Button variant="outline" disabled={busy} onClick={onClose}>Retour</Button>
        <Button disabled={busy || disabled} aria-busy={busy} onClick={onConfirm}>{busy ? 'Enregistrement…' : confirmLabel}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>;
}
