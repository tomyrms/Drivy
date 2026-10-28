-- #253 / S12 : échéance lisible avant une réservation individuelle.
-- Nullable et sans backfill : aucun texte historique interprété, aucun frais calculé.
ALTER TABLE drivy.school_policy_version ADD COLUMN cancellation_rules jsonb;
ALTER TABLE drivy.school_policy_version ADD CONSTRAINT school_policy_cancellation_rules_valid CHECK (
 cancellation_rules IS NULL OR COALESCE(
  CASE WHEN jsonb_typeof(cancellation_rules)='object' THEN
   cancellation_rules ?& ARRAY['cancellationHours','lateAction']
   AND (cancellation_rules - 'cancellationHours' - 'lateAction')='{}'::jsonb
   AND cancellation_rules->>'lateAction' IN ('CONTACT','NO_FEE')
   AND CASE WHEN jsonb_typeof(cancellation_rules->'cancellationHours')='number' THEN
    (cancellation_rules->>'cancellationHours')::numeric BETWEEN 0 AND 8760
    AND trunc((cancellation_rules->>'cancellationHours')::numeric)=(cancellation_rules->>'cancellationHours')::numeric
   ELSE cancellation_rules->'cancellationHours'='null'::jsonb END
  ELSE false END,
 false)
);
COMMENT ON COLUMN drivy.school_policy_version.cancellation_rules IS
 'Règle structurée relue par l’école pour une version de procédure. NULL si inconnue. Lecture de l’échéance uniquement, sans frais automatique.';
