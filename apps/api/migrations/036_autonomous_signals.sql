-- Signalements autonomes (21 octobre 2026, issue #56). Les compétences d'une formation servent à son évaluation ; elles ne
-- décident plus quels signalements existent. Un signalement qualifié se définit par son thème et son statut ; la compétence
-- devient facultative. Les migrations 009 et 026 restent telles qu'appliquées : leurs deux contraintes sont remplacées ici.
-- Décision : docs/implementation/signalements-autonomes-20261021.md.

-- Les contraintes d'origine n'ont pas de nom choisi : elles sont retrouvées par leur définition, et la migration échoue si
-- l'une d'elles manque ou existe en double, plutôt que d'en retirer une autre.
DO $$
DECLARE
 live_qualified text[];
 theme_link text[];
BEGIN
 SELECT array_agg(conname) INTO live_qualified FROM pg_constraint
  WHERE conrelid='drivy.geo_observation'::regclass AND contype='c'
   AND pg_get_constraintdef(oid) LIKE '%event_kind <> ''QUALIFIED''::text%competency_id IS NOT NULL%event_status IS NOT NULL%';
 SELECT array_agg(conname) INTO theme_link FROM pg_constraint
  WHERE conrelid='drivy.geo_observation'::regclass AND contype='c'
   AND pg_get_constraintdef(oid) LIKE '%theme_key IS NULL%competency_id IS NOT NULL%';
 IF cardinality(live_qualified) IS DISTINCT FROM 1 OR cardinality(theme_link) IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'contraintes d''observation inattendues : % / %',live_qualified,theme_link;
 END IF;
 EXECUTE format('ALTER TABLE drivy.geo_observation DROP CONSTRAINT %I',live_qualified[1]);
 EXECUTE format('ALTER TABLE drivy.geo_observation DROP CONSTRAINT %I',theme_link[1]);
END $$;

-- Un signalement qualifié pendant la leçon garde un statut et nomme ce qui est observé : son thème, ou, pour les observations
-- antérieures, sa compétence. Aucune ligne existante ne change : elles avaient toutes une compétence.
ALTER TABLE drivy.geo_observation ADD CONSTRAINT geo_observation_live_qualified
 CHECK(origin<>'LIVE' OR event_kind<>'QUALIFIED' OR (event_status IS NOT NULL AND (competency_id IS NOT NULL OR theme_key IS NOT NULL)));
-- Le thème qualifie un signalement : jamais un repère. Il ne demande plus de compétence.
ALTER TABLE drivy.geo_observation ADD CONSTRAINT geo_observation_theme_key
 CHECK(theme_key IS NULL OR (theme_key ~ '^[a-z][a-z0-9-]{0,39}$' AND event_kind IS DISTINCT FROM 'MARKER'));
