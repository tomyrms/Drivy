import { useContext, type ComponentProps } from 'react';
import { Dialog as DialogPrimitive } from '@base-ui/react/dialog';
import { XIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { UiSuspendedContext } from '@/ui-suspension';

function Dialog(props: DialogPrimitive.Root.Props) {
  const suspended = useContext(UiSuspendedContext);
  return <DialogPrimitive.Root {...props} open={suspended ? false : props.open} onOpenChange={(open, details) => {
    if (suspended) { details.cancel(); return; }
    props.onOpenChange?.(open, details);
  }} />;
}
function DialogTrigger(props: DialogPrimitive.Trigger.Props) { return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />; }
function DialogPortal(props: DialogPrimitive.Portal.Props) { return <DialogPrimitive.Portal {...props} />; }
function DialogClose(props: DialogPrimitive.Close.Props) { return <DialogPrimitive.Close data-slot="dialog-close" {...props} />; }
function DialogOverlay({ className, ...props }: DialogPrimitive.Backdrop.Props) {
  const suspended = useContext(UiSuspendedContext);
  return <DialogPrimitive.Backdrop data-slot="dialog-overlay" className={cn('ui-dialog-overlay', className)} {...props} {...(suspended ? { hidden: true } : {})} />;
}

/** One mounted form at every width; CSS adapts the panel without losing input. */
function DialogContent({ className, children, showCloseButton = true, ...props }: DialogPrimitive.Popup.Props & { showCloseButton?: boolean }) {
  const suspended = useContext(UiSuspendedContext);
  return <DialogPortal>
    <DialogOverlay />
    <DialogPrimitive.Popup data-slot="dialog-content" className={cn('ui-dialog-content', className)} {...props} {...(suspended ? { hidden: true } : {})} finalFocus={suspended ? false : props.finalFocus}>
      {children}
      {showCloseButton && <DialogPrimitive.Close render={<Button variant="ghost" size="icon" className="ui-dialog-close" />}>
        <XIcon aria-hidden="true" /><span className="visually-hidden">Fermer</span>
      </DialogPrimitive.Close>}
    </DialogPrimitive.Popup>
  </DialogPortal>;
}
function DialogHeader({ className, ...props }: ComponentProps<'div'>) {
  return <div data-slot="dialog-header" className={cn('ui-dialog-header', className)} {...props} />;
}
function DialogFooter({ className, showCloseButton = false, children, ...props }: ComponentProps<'div'> & { showCloseButton?: boolean }) {
  return <div data-slot="dialog-footer" className={cn('ui-dialog-footer', className)} {...props}>
    {children}{showCloseButton && <DialogClose render={<Button variant="outline" />}>Fermer</DialogClose>}
  </div>;
}
function DialogTitle({ className, ...props }: DialogPrimitive.Title.Props) {
  return <DialogPrimitive.Title data-slot="dialog-title" className={cn('ui-dialog-title', className)} {...props} />;
}
function DialogDescription({ className, ...props }: DialogPrimitive.Description.Props) {
  return <DialogPrimitive.Description data-slot="dialog-description" className={cn('ui-dialog-description', className)} {...props} />;
}

export { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogOverlay, DialogPortal, DialogTitle, DialogTrigger };
