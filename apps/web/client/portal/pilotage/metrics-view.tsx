import type { ReactNode } from 'react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { ReadFeedback } from '../components/feedback';
import { useMetricDefinitions, useMetrics, type MetricDefinition, type MetricsAnswer, type MetricsRequest } from './metrics-api';

const clock = (answer: MetricsAnswer) => new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone: answer.timeZone }).format(new Date(answer.computedAt));

/**
 * Lecture d'un domaine pour une période, avec le dictionnaire des mesures. Rien n'est affiché tant que les deux lectures ne sont pas prêtes :
 * un libellé manquant ou un chiffre d'une autre période ne remplace jamais une erreur. Quand une mise à jour échoue alors que des chiffres
 * de la même portée sont déjà là, ils restent affichés avec l'heure de leur calcul : une erreur ne fait pas disparaître ce qui est connu,
 * et ne le remplace pas par zéro.
 */
export function MetricsView({ request, label, children }: {
  request: MetricsRequest;
  label: string;
  children: (answer: MetricsAnswer, definitions: ReadonlyMap<string, MetricDefinition>) => ReactNode;
}) {
  const metrics = useMetrics(request);
  const definitions = useMetricDefinitions();
  const failed = [metrics, definitions].find(item => item.status === 'error');
  if (failed) {
    if (metrics.data === undefined || definitions.data === undefined) return <ReadFeedback loaded={failed} label={label} />;
    return <>
      <Alert variant="destructive"><AlertTitle>La mise à jour a échoué</AlertTitle>
        <AlertDescription>Les chiffres affichés ont été calculés à {clock(metrics.data)}. {failed.error}</AlertDescription>
        <div className="mt-3"><Button variant="outline" onClick={failed.reload}>Réessayer</Button></div>
      </Alert>
      {children(metrics.data, definitions.data)}
    </>;
  }
  if (metrics.status !== 'ready' || definitions.status !== 'ready' || !metrics.data || !definitions.data) {
    return <ReadFeedback loaded={metrics.status === 'ready' ? definitions : metrics} label={label} />;
  }
  return <>{children(metrics.data, definitions.data)}</>;
}

/** Période, portée et fraîcheur d'une lecture, en une ligne. */
export function ScopeLine({ period, scope, answer }: { period: string; scope: string; answer: MetricsAnswer }) {
  return <p className="pilotage-scope">{period} · {scope} · calculé à {clock(answer)}</p>;
}
