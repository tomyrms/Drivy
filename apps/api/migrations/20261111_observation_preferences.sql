-- Préférences de signalements du compte et politique de visibilité de l'école (11 novembre 2026, R08 : #465, #466, #467).
-- L'école garde sa politique (visibilité imposée ou personnalisable) et ses valeurs de référence ; le compte garde son ordre manuel,
-- sa visibilité personnelle, son choix manuel/intelligent et son apprentissage, communs à ses écoles et à ses appareils.
-- Contrat et décisions : docs/implementation/r08-contrat-serveur-20261111.md.

-- 1. Politique de l'école. Absente ou fausse : visibilité imposée. Toutes les écoles existantes démarrent donc imposées, avec la
--    configuration qu'elles ont déjà (la ligne d'école n'est pas modifiée).
ALTER TABLE drivy.observation_theme_settings ADD COLUMN IF NOT EXISTS personalization_allowed boolean NOT NULL DEFAULT false;
GRANT UPDATE(personalization_allowed) ON drivy.observation_theme_settings TO drivy_app;

-- 2. Le droit de gestion scolaire est réservé à l'administrateur de l'école. Un ancien grant MANAGE_OBSERVATION_THEMES d'un moniteur
--    reste dans la liste des droits (rien n'est supprimé) mais ne donne plus aucun pouvoir : les politiques RLS de 026 appellent
--    cette fonction, elles suivent donc la nouvelle règle sans être réécrites.
CREATE OR REPLACE FUNCTION drivy.can_manage_observation_themes(school uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.current_school_member(school) AND EXISTS(SELECT 1 FROM drivy.membership m
  WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
$$;

-- Moniteur ou administrateur de l'école ouverte : la règle commune des ressources personnelles.
CREATE FUNCTION drivy.observation_staff(school uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.current_school_member(school) AND EXISTS(SELECT 1 FROM drivy.membership m
  WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
  AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[])
$$;
REVOKE ALL ON FUNCTION drivy.observation_staff(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.observation_staff(uuid) TO drivy_app;

-- 3. Préférences du compte : une ligne par personne, créée à la première personnalisation (version 2). Sans ligne : mode manuel,
--    aucune personnalisation (version 1). Aucune clé d'école : changer ou quitter une école ne touche à rien.
--    theme_order / hidden_themes : NULL tant que la personne n'a rien établi (elle suit alors les références de l'école ouverte) ;
--    hidden_themes est conservé en réserve quand l'école impose sa visibilité.
--    learning_generation / learning_since : borne durable de l'apprentissage. Aucun calcul ne lit un geste observé avant elle.
CREATE TABLE IF NOT EXISTS drivy.person_observation_preference (
 person_id uuid PRIMARY KEY REFERENCES drivy.person(id),
 version integer NOT NULL CHECK(version > 1),
 theme_order text[],
 hidden_themes text[],
 mode text NOT NULL DEFAULT 'MANUAL' CHECK(mode IN('MANUAL','SMART')),
 ranked_order text[] NOT NULL DEFAULT '{}',
 ranked_on date,
 learning_generation integer NOT NULL DEFAULT 0 CHECK(learning_generation >= 0),
 learning_since timestamptz,
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(theme_order IS NULL OR (cardinality(theme_order) BETWEEN 1 AND 64 AND array_position(theme_order,NULL) IS NULL)),
 CHECK(hidden_themes IS NULL OR (theme_order IS NOT NULL AND array_position(hidden_themes,NULL) IS NULL
  AND hidden_themes <@ theme_order AND cardinality(hidden_themes) < cardinality(theme_order))),
 CHECK(cardinality(ranked_order) <= 64 AND array_position(ranked_order,NULL) IS NULL)
);
ALTER TABLE drivy.person_observation_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.person_observation_preference FORCE ROW LEVEL SECURITY;
DO $$ BEGIN EXECUTE format('CREATE POLICY person_observation_preference_owner ON drivy.person_observation_preference FOR ALL TO %I USING(true) WITH CHECK(true)',current_user); END $$;
-- Chacun ne lit et n'écrit que sa propre ligne, et seulement depuis une école où il est moniteur ou administrateur : ni un collègue,
-- ni l'administration, ni un élève.
CREATE POLICY person_observation_preference_own ON drivy.person_observation_preference TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.observation_staff(nullif(current_setting('app.school_id',true),'')::uuid))
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.observation_staff(nullif(current_setting('app.school_id',true),'')::uuid));
GRANT SELECT,INSERT ON drivy.person_observation_preference TO drivy_app;
GRANT UPDATE(version,theme_order,hidden_themes,mode,ranked_order,ranked_on,learning_generation,learning_since,updated_at) ON drivy.person_observation_preference TO drivy_app;

-- Preuves d'opération et audit des nouvelles commandes.
CREATE POLICY observation_preferences_operation ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.observation_staff(school_id) AND command_type IN('SAVE_OBSERVATION_PRESENTATION','RESET_OBSERVATION_PRESENTATION','RESET_OBSERVATION_LEARNING'));
CREATE POLICY observation_preferences_audit ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.observation_staff(school_id) AND action IN('ObservationPresentationSaved','ObservationPresentationReset','ObservationLearningReset'));

-- 4. Usages du compte courant, toutes écoles où il est encore actif, par thème, leçon et jour du fuseau du classement, jusqu'à la
--    veille. Seuls comptent les gestes faits dans la palette pendant une leçon et toujours présents, observés à partir de la borne
--    d'apprentissage du compte : un geste observé avant elle n'est jamais relu, même reçu après (file hors ligne). La fonction ne rend
--    que des compteurs de ses propres gestes ; une école dont l'accès est retiré n'est plus lue.
CREATE FUNCTION drivy.observation_account_usage(zone text) RETURNS TABLE(theme_key text,lesson_id uuid,day date,uses integer,palette_position integer)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT o.theme_key,o.lesson_id,(coalesce(o.observed_at,o.created_at) AT TIME ZONE zone)::date,count(*)::int,min(o.palette_position)::int
 FROM drivy.geo_observation o JOIN drivy.membership m ON m.school_id=o.school_id AND m.id=o.author_membership_id
 WHERE drivy.current_school_member(nullif(current_setting('app.school_id',true),'')::uuid)
  AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
  AND o.theme_key IS NOT NULL AND o.removed_at IS NULL AND o.origin='LIVE' AND o.event_kind='QUALIFIED'
  AND o.created_at>=now()-interval '400 days'
  AND coalesce(o.observed_at,o.created_at)>=coalesce((SELECT p.learning_since FROM drivy.person_observation_preference p WHERE p.person_id=m.person_id),'-infinity'::timestamptz)
  AND (coalesce(o.observed_at,o.created_at) AT TIME ZONE zone)::date<(now() AT TIME ZONE zone)::date
 GROUP BY 1,2,3
$$;
REVOKE ALL ON FUNCTION drivy.observation_account_usage(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.observation_account_usage(text) TO drivy_app;

-- 5. Configurations héritées des écoles où la personne est encore moniteur ou administrateur : la référence de l'école et le
--    classement que cette personne y avait. Sert uniquement à proposer le choix de reprise quand elles divergent.
CREATE FUNCTION drivy.observation_adoption_candidates() RETURNS TABLE(school_id uuid,school_name text,theme_order text[],hidden_themes text[],ranking_mode text,ranked_order text[])
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.school_id,s.name,t.theme_order,t.hidden_themes,r.mode,r.ranked_order
 FROM drivy.membership m JOIN drivy.school s ON s.id=m.school_id AND s.status<>'ARCHIVED'
  LEFT JOIN drivy.observation_theme_settings t ON t.school_id=m.school_id
  LEFT JOIN drivy.observation_ranking r ON r.school_id=m.school_id AND r.membership_id=m.id
 WHERE drivy.current_school_member(nullif(current_setting('app.school_id',true),'')::uuid)
  AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]
 ORDER BY s.name,m.school_id
$$;
REVOKE ALL ON FUNCTION drivy.observation_adoption_candidates() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.observation_adoption_candidates() TO drivy_app;

-- 6. Reprise de l'existant : le classement intelligent d'une personne passe sur son compte. Répétable et sans écrasement :
--    - un compte déjà initialisé n'est jamais touché ;
--    - une seule configuration utile, ou plusieurs identiques (mêmes mode et ordre appris), se reprend ;
--    - des classements contradictoires (par exemple intelligent dans une école, manuel dans une autre, ou deux ordres appris
--      différents) ne sont pas départagés ici : la personne choisit à sa première personnalisation ;
--    - un choix manuel seul ne crée rien (c'est déjà le comportement d'un compte neuf).
--    L'ordre manuel et la visibilité du compte restent vides : tant que la personne n'a rien établi, elle suit l'école ouverte.
--    Les anciennes lignes drivy.observation_ranking sont conservées telles quelles, en lecture seule.
CREATE FUNCTION drivy.adopt_legacy_observation_rankings() RETURNS integer LANGUAGE sql AS $$
 WITH legacy AS (
  SELECT m.person_id,r.mode,CASE WHEN r.mode='SMART' THEN r.ranked_order ELSE '{}'::text[] END AS ranked_order,CASE WHEN r.mode='SMART' THEN r.ranked_on END AS ranked_on
  FROM drivy.observation_ranking r JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.membership_id
   JOIN drivy.person p ON p.id=m.person_id AND p.status='ACTIVE'
  WHERE m.status='ACTIVE' AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]
 ), choices AS (
  SELECT person_id,mode,ranked_order,max(ranked_on) AS ranked_on FROM legacy GROUP BY person_id,mode,ranked_order
 ), unique_choice AS (
  SELECT c.* FROM choices c WHERE (SELECT count(*) FROM choices x WHERE x.person_id=c.person_id)=1
 ), adopted AS (
  INSERT INTO drivy.person_observation_preference(person_id,version,mode,ranked_order,ranked_on)
  SELECT person_id,2,mode,ranked_order,ranked_on FROM unique_choice WHERE mode='SMART'
  ON CONFLICT(person_id) DO NOTHING RETURNING 1
 )
 SELECT count(*)::int FROM adopted
$$;
REVOKE ALL ON FUNCTION drivy.adopt_legacy_observation_rankings() FROM PUBLIC;
SELECT drivy.adopt_legacy_observation_rankings();

-- L'ancienne table n'est plus écrite : le classement vit sur le compte. Elle reste lisible pour la reprise ci-dessus.
REVOKE INSERT,UPDATE ON drivy.observation_ranking FROM drivy_app;
