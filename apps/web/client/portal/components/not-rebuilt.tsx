import { ArrowRight } from 'lucide-react';
import { choosePresentation } from '../../presentation';
import { Button } from '../../components/ui/button';

/** A destination without its rebuilt page yet: say so and offer the historical presentation, never import it. */
export function NotRebuilt({ title }: { title: string }) {
  return <section className="portal-not-rebuilt">
    <h1 tabIndex={-1}>{title}</h1>
    <p>Cette page n’a pas encore sa nouvelle présentation.</p>
    <Button variant="outline" onClick={() => { choosePresentation('legacy'); window.location.reload(); }}>Ouvrir l’ancienne présentation<ArrowRight aria-hidden="true" /></Button>
  </section>;
}
