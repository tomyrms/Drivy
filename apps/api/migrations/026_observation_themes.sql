-- Signalements configurables (12 octobre 2026). Le catalogue des quinze thèmes vit dans le code du service (observation-themes.ts) ;
-- la base ne garde que ce qui appartient à l'école : l'ordre, l'affichage et qui peut les régler.
-- Contrat et décisions : docs/implementation/signalements-configurables-20261012.md.

-- Le droit rejoint la liste existante : aucun second mécanisme de permission.
ALTER TABLE drivy.membership DROP CONSTRAINT membership_grants_check;
ALTER TABLE drivy.membership ADD CONSTRAINT membership_grants_check CHECK (grants <@ ARRAY['permit_review','cash_record','CONFIGURE_CATALOG','SELL_SERVICES','MANAGE_COURSES','TAKE_ATTENDANCE','VALIDATE_REQUIREMENT','REVIEW_REGULATORY_PROFILE','MANAGE_LEARNER_ARCHIVES','VIEW_SCHOOL_METRICS','VIEW_FINANCIAL_METRICS','EXPORT_MANAGEMENT','MANAGE_OBSERVATION_THEMES']::text[]);

-- Une seule règle pour la table et pour la commande : administrateur, ou moniteur portant le droit.
CREATE FUNCTION drivy.can_manage_observation_themes(school uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.current_school_member(school) AND EXISTS(SELECT 1 FROM drivy.membership m
  WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
  AND ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND 'MANAGE_OBSERVATION_THEMES'=ANY(m.grants))))
$$;
REVOKE ALL ON FUNCTION drivy.can_manage_observation_themes(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.can_manage_observation_themes(uuid) TO drivy_app;

-- Une ligne par école, créée à la première modification (version 2). Sans ligne, l'école a la configuration d'origine (version 1).
-- theme_order porte toutes les clés dans l'ordre choisi ; hidden_themes celles qui ne sont pas proposées pendant la leçon.
CREATE TABLE drivy.observation_theme_settings (
 school_id uuid PRIMARY KEY REFERENCES drivy.school(id),
 version integer NOT NULL CHECK(version > 1),
 theme_order text[] NOT NULL,
 hidden_themes text[] NOT NULL DEFAULT '{}',
 updated_by uuid NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(school_id,updated_by) REFERENCES drivy.membership(school_id,id),
 CHECK(cardinality(theme_order) BETWEEN 1 AND 64 AND array_position(theme_order,NULL) IS NULL),
 -- Au moins un thème reste affiché.
 CHECK(hidden_themes <@ theme_order AND cardinality(hidden_themes) < cardinality(theme_order))
);
ALTER TABLE drivy.observation_theme_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.observation_theme_settings FORCE ROW LEVEL SECURITY;
DO $$ BEGIN EXECUTE format('CREATE POLICY observation_theme_settings_owner ON drivy.observation_theme_settings FOR ALL TO %I USING(true) WITH CHECK(true)',current_user); END $$;
-- Lecture : l'équipe de l'école. Un élève n'en a pas besoin : ses observations portent déjà leur thème.
CREATE POLICY observation_theme_settings_read ON drivy.observation_theme_settings FOR SELECT TO drivy_app
 USING(drivy.current_school_member(school_id) AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id=observation_theme_settings.school_id
  AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]));
CREATE POLICY observation_theme_settings_insert ON drivy.observation_theme_settings FOR INSERT TO drivy_app
 WITH CHECK(drivy.can_manage_observation_themes(school_id) AND updated_by=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY observation_theme_settings_update ON drivy.observation_theme_settings FOR UPDATE TO drivy_app
 USING(drivy.can_manage_observation_themes(school_id))
 WITH CHECK(drivy.can_manage_observation_themes(school_id) AND updated_by=nullif(current_setting('app.membership_id',true),'')::uuid);
GRANT SELECT,INSERT ON drivy.observation_theme_settings TO drivy_app;
GRANT UPDATE(version,theme_order,hidden_themes,updated_by,updated_at) ON drivy.observation_theme_settings TO drivy_app;
CREATE POLICY observation_theme_settings_operation ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.can_manage_observation_themes(school_id) AND command_type='SAVE_OBSERVATION_THEMES');
CREATE POLICY observation_theme_settings_audit ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.can_manage_observation_themes(school_id) AND action='ObservationThemesSaved');

-- Chaque observation qualifiée garde la clé de son thème : elle ne dépend ni de l'ordre, ni de l'affichage, ni du texte relu.
ALTER TABLE drivy.geo_observation ADD COLUMN theme_key text
 CHECK(theme_key IS NULL OR (theme_key ~ '^[a-z][a-z0-9-]{0,39}$' AND competency_id IS NOT NULL));
GRANT UPDATE(theme_key) ON drivy.geo_observation TO drivy_app;

-- Reprise de l'existant : seulement là où le texte est encore exactement le titre de la tuile touchée. Un texte relu ne dit plus
-- quelle tuile l'a produit ; ces observations restent sans clé et gardent leur compétence, comme avant. La version ne change pas :
-- aucune donnée du moniteur n'est modifiée.
UPDATE drivy.geo_observation o SET theme_key=x.key
 FROM drivy.competency_definition c,(VALUES
  ('vehicule','Maîtrise du véhicule','vehicle'),('observation','Observation et contrôles','observation'),
  ('priorites','Priorité à droite','right-priority'),('priorites','Signalisation','signage'),('priorites','Céder le passage','give-way'),
  ('intersections','Intersections et giratoires','intersections'),('vitesse','Vitesse','speed'),('vitesse','Adaptation de la vitesse','speed'),
  ('placement','Placement sur la chaussée','placement'),('manoeuvres','Manœuvres','manoeuvres'),('parking','Stationnement','manoeuvres'),
  ('autoroute','Autoroute','motorway'),('motorway','Autoroute','motorway'),
  ('anticipation','Anticipation','anticipation'),('anticipation','Anticipation et partage de la route','anticipation')
 ) AS x(competency_key,title,key)
 WHERE c.school_id=o.school_id AND c.id=o.competency_id AND c.stable_key=x.competency_key AND o.text=x.title
  AND o.event_kind='QUALIFIED' AND o.removed_at IS NULL AND o.theme_key IS NULL;
