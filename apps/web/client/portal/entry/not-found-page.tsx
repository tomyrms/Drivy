import { useEffect } from 'react';
import { Compass } from 'lucide-react';
import { buttonVariants } from '../../components/ui/button';
import { entryRoutes, type EntryRoutes } from './entry-model';
import { EntryFrame } from './entry-frame';

/** Unknown address below `/app` (#319). The console route parser keeps its own controlled fallback. */
export function PortalNotFoundPage({ routes = entryRoutes }: { routes?: EntryRoutes }) {
  useEffect(() => { document.title = 'Page introuvable · Drivy'; }, []);
  return <EntryFrame home={routes.account}>
    <section className="entry-auth entry-not-found" aria-labelledby="not-found-title">
      <header className="entry-auth-header">
        <span className="entry-icon-tile entry-icon-large"><Compass aria-hidden="true" /></span>
        <h1 id="not-found-title" tabIndex={-1} ref={heading => heading?.focus()}>Page introuvable</h1>
        <p className="entry-muted">Cette adresse ne correspond à aucune page de Drivy.</p>
      </header>
      <a className={buttonVariants({ size: 'lg' })} href={routes.account}>Retrouver mes écoles</a>
    </section>
  </EntryFrame>;
}
