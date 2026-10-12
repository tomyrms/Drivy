-- Classement intelligent des signalements (13 octobre 2026). L'ordre manuel reste celui de l'école (observation_theme_settings) :
-- cette table ne garde que la préférence d'un moniteur et le dernier classement calculé pour lui. Les statistiques d'usage ne sont
-- pas recopiées : elles se lisent dans geo_observation, déjà protégée contre les doublons par la preuve d'opération.
-- Méthode et contrat : docs/implementation/classement-intelligent-20261013.md.

-- Une ligne par adhésion, créée au premier réglage (version 2). Sans ligne : mode manuel (version 1).
-- ranked_order : classement des thèmes affichés au jour ranked_on (date locale de l'école) ; il sert de point de départ au suivant.
CREATE TABLE drivy.observation_ranking (
 school_id uuid NOT NULL,
 membership_id uuid NOT NULL,
 version integer NOT NULL CHECK(version > 1),
 mode text NOT NULL CHECK(mode IN('MANUAL','SMART')),
 ranked_order text[] NOT NULL DEFAULT '{}',
 ranked_on date,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(school_id,membership_id),
 FOREIGN KEY(school_id,membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(cardinality(ranked_order) <= 64 AND array_position(ranked_order,NULL) IS NULL)
);
ALTER TABLE drivy.observation_ranking ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.observation_ranking FORCE ROW LEVEL SECURITY;
DO $$ BEGIN EXECUTE format('CREATE POLICY observation_ranking_owner ON drivy.observation_ranking FOR ALL TO %I USING(true) WITH CHECK(true)',current_user); END $$;
-- Chacun ne lit et n'écrit que son propre classement, dans son école : ni un collègue, ni l'administration.
CREATE POLICY observation_ranking_own ON drivy.observation_ranking TO drivy_app
 USING(drivy.current_school_member(school_id) AND EXISTS(
  SELECT 1 FROM drivy.membership m WHERE m.school_id=observation_ranking.school_id AND m.id=membership_id
   AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
   AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]))
 WITH CHECK(drivy.current_school_member(school_id) AND EXISTS(
  SELECT 1 FROM drivy.membership m WHERE m.school_id=observation_ranking.school_id AND m.id=membership_id
   AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
   AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]));
GRANT SELECT,INSERT ON drivy.observation_ranking TO drivy_app;
GRANT UPDATE(version,mode,ranked_order,ranked_on,updated_at) ON drivy.observation_ranking TO drivy_app;
CREATE POLICY observation_ranking_operation ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND command_type IN('SAVE_OBSERVATION_RANKING','REFRESH_OBSERVATION_RANKING'));
CREATE POLICY observation_ranking_audit ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND action IN('ObservationRankingSaved','ObservationRankingRefreshed'));

-- Rang de la tuile dans « Signaler » au moment du geste, noté par le service : il corrige le biais de position (une tuile qu'il
-- faut aller chercher en défilant est moins utilisée à habitude égale). Absent pour l'existant et hors de la palette.
ALTER TABLE drivy.geo_observation ADD COLUMN palette_position smallint CHECK(palette_position IS NULL OR palette_position BETWEEN 1 AND 64);

-- Lecture des usages d'un moniteur sur la fenêtre du classement.
CREATE INDEX geo_observation_author_theme ON drivy.geo_observation(school_id,author_membership_id,created_at)
 WHERE theme_key IS NOT NULL AND removed_at IS NULL;

-- Usages du compte courant dans une école, par thème, leçon et jour local, jusqu'à la veille : seulement les signalements faits dans
-- la palette pendant une leçon et toujours présents. La fonction ne rend que des compteurs de ses propres gestes ; elle ne dépend pas
-- de l'attribution actuelle de l'élève, pour qu'un changement de moniteur n'efface pas les habitudes de celui qui a signalé.
CREATE FUNCTION drivy.observation_theme_usage(school uuid,zone text) RETURNS TABLE(theme_key text,lesson_id uuid,day date,uses integer,palette_position integer)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT o.theme_key,o.lesson_id,(coalesce(o.observed_at,o.created_at) AT TIME ZONE zone)::date,count(*)::int,min(o.palette_position)::int
 FROM drivy.geo_observation o JOIN drivy.membership m ON m.school_id=o.school_id AND m.id=o.author_membership_id
 WHERE o.school_id=school AND drivy.current_school_member(school) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
  AND o.theme_key IS NOT NULL AND o.removed_at IS NULL AND o.origin='LIVE' AND o.event_kind='QUALIFIED'
  AND o.created_at>=now()-interval '400 days' AND (coalesce(o.observed_at,o.created_at) AT TIME ZONE zone)::date<(now() AT TIME ZONE zone)::date
 GROUP BY 1,2,3
$$;
REVOKE ALL ON FUNCTION drivy.observation_theme_usage(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.observation_theme_usage(uuid,text) TO drivy_app;
