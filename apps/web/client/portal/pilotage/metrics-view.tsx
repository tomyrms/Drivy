import type { ReactNode } from 'react';
import { ReadFeedback } from '../components/feedback';
import { useMetricDefinitions, useMetrics, type MetricDefinition, type MetricsAnswer, type MetricsRequest } from './metrics-api';

/**
 * Lecture d'un domaine pour une période, avec le dictionnaire des mesures. Rien n'est affiché tant que les deux lectures
 * ne sont pas prêtes : un libellé manquant ou un chiffre d'une autre période ne remplace jamais une erreur.
 */
export function MetricsView({ request, label, children }: {
  request: MetricsRequest;
  label: string;
  children: (answer: MetricsAnswer, definitions: ReadonlyMap<string, MetricDefinition>) => ReactNode;
}) {
  const metrics = useMetrics(request);
  const definitions = useMetricDefinitions();
  const failed = [metrics, definitions].find(item => item.status === 'error');
  if (failed) return <ReadFeedback loaded={failed} label={label} />;
  if (metrics.status !== 'ready' || definitions.status !== 'ready' || !metrics.data || !definitions.data) {
    return <ReadFeedback loaded={metrics.status === 'ready' ? definitions : metrics} label={label} />;
  }
  return <>{children(metrics.data, definitions.data)}</>;
}

/** Période, portée et fraîcheur d'une lecture, en une ligne. */
export function ScopeLine({ period, scope, answer }: { period: string; scope: string; answer: MetricsAnswer }) {
  const computed = new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone: answer.timeZone }).format(new Date(answer.computedAt));
  return <p className="pilotage-scope">{period} · {scope} · calculé à {computed}</p>;
}
