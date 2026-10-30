-- Données entièrement synthétiques pour Tomy School ; aucun compte de connexion ni consentement.
-- Fragment à inclure dans LA transaction du coordinateur après sauvegarde vérifiée.
-- Entrées temporaires : seed_context(school_id uuid, actor_id uuid) : une ligne, actor_id = membership ADMIN.
-- seed_catalogue(formation_id uuid, kind text, offering_id uuid, ordinal int) : B/A/A1/BE, une offre par catégorie.
-- pg_temp.seed_uuid(text) : UUID déterministe au format version 4 / variante RFC, fourni par le coordinateur.
-- Ce fichier n'ouvre/ne valide aucune transaction et ne modifie ni RLS, ni rôles, ni déclencheurs.
-- Sortie temporaire : seed_people ; les affectations/leçons sont créées par le fragment planning.

DO $guard$
DECLARE context_count integer; target uuid; actor uuid;
BEGIN
  SELECT count(*) INTO context_count FROM seed_context;
  IF context_count <> 1 THEN RAISE EXCEPTION 'seed_context_requires_one_row'; END IF;
  SELECT school_id, actor_id INTO target, actor FROM seed_context;
  IF current_user = 'drivy_app' THEN RAISE EXCEPTION 'seed_requires_authorized_maintenance_connection'; END IF;
  IF NOT EXISTS (SELECT 1 FROM drivy.school WHERE id=target AND status='ACTIVE' AND lower(btrim(name))='tomy school') THEN
    RAISE EXCEPTION 'seed_target_is_not_active_tomy_school';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
    WHERE m.id=actor AND m.school_id=target AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)) THEN
    RAISE EXCEPTION 'seed_actor_must_be_active_school_admin';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='drivy' AND table_name='learner_profile' AND column_name='display_name') THEN
    RAISE EXCEPTION 'seed_requires_single_person_identity_migration_041';
  END IF;
  IF (SELECT count(*) FROM seed_catalogue WHERE kind IN ('B','A','A1','BE')) <> 4
    OR (SELECT count(DISTINCT kind) FROM seed_catalogue WHERE kind IN ('B','A','A1','BE')) <> 4 THEN
    RAISE EXCEPTION 'seed_requires_four_distinct_catalogue_categories';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_catalogue c LEFT JOIN drivy.offering_version o ON o.id=c.offering_id
    LEFT JOIN drivy.curriculum_version cv ON cv.id=o.curriculum_version_id AND cv.school_id=o.school_id
    LEFT JOIN drivy.school_policy_version pv ON pv.id=o.policy_version_id AND pv.school_id=o.school_id
    WHERE c.kind IN ('B','A','A1','BE') AND (o.id IS NULL OR o.school_id<>target OR o.category_code<>c.kind
      OR NOT o.enabled OR cv.id IS NULL OR NOT cv.approved OR pv.id IS NULL OR NOT pv.approved)) THEN
    RAISE EXCEPTION 'seed_catalogue_must_be_enabled_approved_and_school_scoped';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM drivy.profile_field_policy WHERE school_id=target AND status='PUBLISHED' AND effective_from<=now()) THEN
    RAISE EXCEPTION 'seed_requires_existing_applicable_profile_policy';
  END IF;
  -- Membership INSERT initialise_profile_context() traite toute l'école. Refuser si cela toucherait l'existant.
  IF EXISTS (SELECT 1 FROM drivy.learner_profile WHERE school_id=target AND administrative_policy_id IS NULL) THEN
    RAISE EXCEPTION 'seed_would_initialize_existing_learner_context';
  END IF;
  IF EXISTS (SELECT 1 FROM drivy.membership m CROSS JOIN (VALUES ('STUDENT'),('STAFF')) k(kind)
    WHERE m.school_id=target AND m.status='ACTIVE'
      AND ((k.kind='STUDENT' AND 'LEARNER'=ANY(m.roles)) OR (k.kind='STAFF' AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]))
      AND NOT EXISTS (SELECT 1 FROM drivy.onboarding_progress op WHERE op.membership_id=m.id AND op.kind=k.kind)) THEN
    RAISE EXCEPTION 'seed_would_initialize_existing_member_onboarding';
  END IF;
END
$guard$;

CREATE TEMP TABLE seed_people_details (
  role text NOT NULL CHECK(role IN ('LEARNER','INSTRUCTOR')), ordinal integer NOT NULL CHECK(ordinal>0),
  first_name text NOT NULL, last_name text NOT NULL, email_slug text NOT NULL,
  birth_date date NOT NULL, street text NOT NULL, postal_code text NOT NULL, locality text NOT NULL,
  category text, wish text, PRIMARY KEY(role,ordinal)
) ON COMMIT DROP;

INSERT INTO seed_people_details VALUES
('LEARNER',1,'Léa','Morel','lea.morel','2005-03-14','Rue des Cerisiers 12','1004','Lausanne','B','Gagner en confiance dans les giratoires.'),
('LEARNER',2,'Noah','Perrin','noah.perrin','2004-11-02','Chemin des Tilleuls 8','1007','Lausanne','B','Préparer les insertions sur autoroute.'),
('LEARNER',3,'Emma','Rochat','emma.rochat','2006-06-23','Avenue des Alpes 24','1020','Renens','B','Mieux anticiper les priorités à droite.'),
('LEARNER',4,'Gabriel','Favre','gabriel.favre','2003-01-19','Rue du Parc 6','1008','Prilly','B','Travailler le stationnement en créneau.'),
('LEARNER',5,'Mila','Berger','mila.berger','2005-09-08','Chemin des Cèdres 15','1024','Ecublens','B','Prendre les bonnes décisions aux intersections.'),
('LEARNER',6,'Louis','Girard','louis.girard','2002-12-17','Route du Lac 32','1095','Lutry','B','Améliorer les contrôles avant un changement de voie.'),
('LEARNER',7,'Chloé','Dubois','chloe.dubois','2007-02-05','Rue de la Gare 9','1030','Bussigny','B','Conduire plus sereinement en ville.'),
('LEARNER',8,'Arthur','Blanc','arthur.blanc','2004-08-30','Chemin des Vignes 4','1009','Pully','B','Rendre les départs en côte plus réguliers.'),
('LEARNER',9,'Alice','Meyer','alice.meyer','2001-05-12','Avenue des Peupliers 18','1010','Lausanne','B','Mieux doser le freinage à faible allure.'),
('LEARNER',10,'Hugo','Schneider','hugo.schneider','2006-10-21','Rue du Collège 7','1023','Crissier','B','Préparer un trajet de manière autonome.'),
('LEARNER',11,'Jade','Fontaine','jade.fontaine','2003-07-04','Chemin des Prés 21','1040','Echallens','B','Améliorer l’observation des passages piétons.'),
('LEARNER',12,'Nathan','Borel','nathan.borel','2005-04-27','Route des Chênes 14','1052','Le Mont-sur-Lausanne','B','Adapter mon allure aux routes étroites.'),
('LEARNER',13,'Inès','Laurent','ines.laurent','2000-09-16','Rue des Jardins 10','1025','Saint-Sulpice','B','Travailler les manœuvres en marche arrière.'),
('LEARNER',14,'Ethan','Richard','ethan.richard','2004-02-11','Chemin du Verger 3','1066','Epalinges','B','Améliorer l’anticipation sur les routes de campagne.'),
('LEARNER',15,'Louise','Monnier','louise.monnier','2006-12-09','Avenue du Léman 22','1005','Lausanne','B','Aborder les carrefours complexes avec méthode.'),
('LEARNER',16,'Adam','Gauthier','adam.gauthier','1999-06-01','Rue des Rosiers 16','1110','Morges','B','Être plus précis dans le placement du véhicule.'),
('LEARNER',17,'Clara','Vuille','clara.vuille','1998-08-18','Chemin de la Forêt 5','1012','Lausanne','A','Travailler le regard et les trajectoires en courbe.'),
('LEARNER',18,'Maxime','Dumas','maxime.dumas','1995-03-25','Route des Vergers 28','1032','Romanel-sur-Lausanne','A','Améliorer ma maîtrise à basse vitesse.'),
('LEARNER',19,'Sarah','Rey','sarah.rey','1997-10-06','Rue du Midi 11','1800','Vevey','A','Préparer le freinage d’urgence progressivement.'),
('LEARNER',20,'Lucas','Aubert','lucas.aubert','1993-01-29','Chemin des Saules 19','1073','Savigny','A','Anticiper les risques sur les itinéraires urbains.'),
('LEARNER',21,'Zoé','Martin','zoe.martin','2007-05-20','Rue de la Fontaine 2','1022','Chavannes-près-Renens','A1','Rendre les demi-tours plus fluides.'),
('LEARNER',22,'Samuel','Henry','samuel.henry','2006-07-13','Chemin des Lilas 13','1026','Denges','A1','Gagner en aisance dans la circulation.'),
('LEARNER',23,'Camille','Marchand','camille.marchand','1988-11-07','Route du Village 26','1070','Puidoux','BE','Comprendre le placement de la remorque en manœuvre.'),
('LEARNER',24,'Thomas','Chevalier','thomas.chevalier','1990-04-03','Chemin des Champs 17','1131','Tolochenaz','BE','Préparer les marches arrière avec un ensemble attelé.'),
('INSTRUCTOR',1,'Sophie','Delcourt','sophie.delcourt','1986-02-24','Rue des Acacias 5','1006','Lausanne',NULL,NULL),
('INSTRUCTOR',2,'Julien','Mercier','julien.mercier','1982-09-15','Chemin des Mélèzes 10','1020','Renens',NULL,NULL),
('INSTRUCTOR',3,'Nadia','Costa','nadia.costa','1989-06-08','Avenue du Parc 14','1110','Morges',NULL,NULL);

CREATE TEMP TABLE seed_people (
  person_id uuid NOT NULL PRIMARY KEY, membership_id uuid NOT NULL UNIQUE,
  learner_id uuid UNIQUE, training_id uuid UNIQUE, role text NOT NULL CHECK(role IN ('LEARNER','INSTRUCTOR')),
  ordinal integer NOT NULL CHECK(ordinal>0), UNIQUE(role,ordinal)
) ON COMMIT DROP;
INSERT INTO seed_people
SELECT pg_temp.seed_uuid('tomy311:person:'||c.school_id::text||':'||d.role||':'||d.ordinal),
  pg_temp.seed_uuid('tomy311:membership:'||c.school_id::text||':'||d.role||':'||d.ordinal),
  CASE WHEN d.role='LEARNER' THEN pg_temp.seed_uuid('tomy311:learner:'||c.school_id::text||':'||d.role||':'||d.ordinal) END,
  CASE WHEN d.role='LEARNER' THEN pg_temp.seed_uuid('tomy311:training:'||c.school_id::text||':'||d.role||':'||d.ordinal) END,
  d.role,d.ordinal
FROM seed_people_details d CROSS JOIN seed_context c;

-- Une relance garde le contenu déjà saisi. Toute collision avec une identité réelle ou un autre périmètre arrête le lot.
DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.identity_link i ON i.person_id=s.person_id)
    OR EXISTS (SELECT 1 FROM seed_people s JOIN drivy.push_device d ON d.person_id=s.person_id) THEN
    RAISE EXCEPTION 'seed_person_has_identity_or_push_binding';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.notification_preference p ON p.person_id=s.person_id
    WHERE p.course_offers OR p.course_reminders OR p.course_changes OR p.course_staff_alerts OR p.messaging_mentions) THEN
    RAISE EXCEPTION 'seed_person_notification_preferences_changed';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.person p ON p.id=s.person_id
    LEFT JOIN drivy.membership m ON m.id=s.membership_id CROSS JOIN seed_context c
    WHERE m.id IS NULL OR m.school_id<>c.school_id OR m.person_id<>s.person_id OR m.status<>'ACTIVE'
      OR m.roles<>ARRAY[s.role]::text[] OR p.status<>'ACTIVE') THEN
    RAISE EXCEPTION 'seed_person_collision_or_existing_access_changed';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.membership m ON m.id=s.membership_id CROSS JOIN seed_context c
    WHERE m.school_id<>c.school_id OR m.person_id<>s.person_id OR m.roles<>ARRAY[s.role]::text[]) THEN
    RAISE EXCEPTION 'seed_membership_collision';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.membership m ON m.person_id=s.person_id CROSS JOIN seed_context c WHERE m.school_id<>c.school_id) THEN
    RAISE EXCEPTION 'seed_person_belongs_to_another_school';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.learner_profile l ON l.id=s.learner_id CROSS JOIN seed_context c
    WHERE l.school_id<>c.school_id OR l.person_id<>s.person_id) THEN
    RAISE EXCEPTION 'seed_learner_collision';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.training t ON t.id=s.training_id
    JOIN seed_people_details d USING(role,ordinal) JOIN seed_catalogue cat ON cat.kind=d.category CROSS JOIN seed_context c
    WHERE t.school_id<>c.school_id OR t.learner_id<>s.learner_id OR t.offering_id<>cat.offering_id OR t.status<>'ACTIVE') THEN
    RAISE EXCEPTION 'seed_training_collision_or_existing_context_changed';
  END IF;
END
$guard$;

INSERT INTO drivy.person(id,display_name,first_name,last_name,locale,contact_email,birth_date,postal_address)
SELECT s.person_id,d.first_name||' '||d.last_name,d.first_name,d.last_name,'fr-CH',d.email_slug||'@example.com',d.birth_date,
  jsonb_build_object('line1',d.street,'postalCode',d.postal_code,'locality',d.locality,'countryCode','CH')
FROM seed_people s JOIN seed_people_details d USING(role,ordinal)
ON CONFLICT(id) DO NOTHING;

-- Aucun numéro potentiellement attribué à une vraie personne, aucune photo ou identité OIDC fabriquée.
INSERT INTO drivy.membership(id,school_id,person_id,roles,grants)
SELECT s.membership_id,c.school_id,s.person_id,ARRAY[s.role]::text[],'{}'::text[]
FROM seed_people s CROSS JOIN seed_context c
ON CONFLICT(id) DO NOTHING;

-- Les préférences fermées évitent les notifications automatiques pour ces personnes synthétiques.
INSERT INTO drivy.notification_preference(person_id,course_offers,course_reminders,course_changes,course_staff_alerts,messaging_mentions)
SELECT person_id,false,false,false,false,false FROM seed_people
ON CONFLICT(person_id) DO NOTHING;

CREATE TEMP TABLE seed_people_new_learners(id uuid PRIMARY KEY) ON COMMIT DROP;
WITH added AS (
  INSERT INTO drivy.learner_profile(id,school_id,person_id,profile_id,entry_source,created_at)
  SELECT s.learner_id,c.school_id,s.person_id,pg_temp.seed_uuid('tomy311:profile:'||s.learner_id::text),'STAFF_ASSISTED',
    (current_date-(120-s.ordinal*3))::timestamptz
  FROM seed_people s CROSS JOIN seed_context c WHERE s.role='LEARNER'
  ON CONFLICT(id) DO NOTHING RETURNING id
) INSERT INTO seed_people_new_learners SELECT id FROM added;
-- Le BEFORE INSERT initialise l'auteur au membre élève : corriger seulement les lignes que ce fragment vient d'ajouter.
UPDATE drivy.learner_profile l SET entered_by_membership_id=c.actor_id
FROM seed_people_new_learners n CROSS JOIN seed_context c WHERE l.id=n.id AND l.school_id=c.school_id;

CREATE TEMP TABLE seed_people_new_trainings(id uuid PRIMARY KEY) ON COMMIT DROP;
WITH added AS (
  INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on,created_at)
  SELECT s.training_id,c.school_id,s.learner_id,o.id,o.offering_key,'ACTIVE',current_date-(120-s.ordinal*3),
    (current_date-(120-s.ordinal*3))::timestamptz
  FROM seed_people s JOIN seed_people_details d USING(role,ordinal)
  JOIN seed_catalogue cat ON cat.kind=d.category JOIN drivy.offering_version o ON o.id=cat.offering_id
  CROSS JOIN seed_context c WHERE s.role='LEARNER' AND o.school_id=c.school_id
  ON CONFLICT(id) DO NOTHING RETURNING id
) INSERT INTO seed_people_new_trainings SELECT id FROM added;

-- training INSERT crée le souhait vide. Un texte court est ajouté seulement pour ces nouvelles formations.
UPDATE drivy.training_wish w SET id=pg_temp.seed_uuid('tomy311:wish:'||w.training_id::text),text=d.wish
FROM seed_people_new_trainings n JOIN seed_people s ON s.training_id=n.id
JOIN seed_people_details d USING(role,ordinal)
WHERE w.training_id=n.id AND w.school_id=(SELECT school_id FROM seed_context);

DO $verify$
BEGIN
  IF (SELECT count(*) FROM seed_people WHERE role='LEARNER')<>24 OR (SELECT count(*) FROM seed_people WHERE role='INSTRUCTOR')<>3 THEN
    RAISE EXCEPTION 'seed_people_export_incomplete';
  END IF;
  IF (SELECT count(*) FROM seed_people s JOIN drivy.membership m ON m.id=s.membership_id AND m.person_id=s.person_id
    WHERE m.school_id=(SELECT school_id FROM seed_context))<>27 THEN RAISE EXCEPTION 'seed_memberships_incomplete'; END IF;
  IF (SELECT count(*) FROM seed_people s JOIN drivy.training t ON t.id=s.training_id AND t.learner_id=s.learner_id
    WHERE t.school_id=(SELECT school_id FROM seed_context) AND s.role='LEARNER')<>24 THEN RAISE EXCEPTION 'seed_trainings_incomplete'; END IF;
  IF EXISTS (SELECT 1 FROM seed_people s JOIN drivy.identity_link i ON i.person_id=s.person_id) THEN
    RAISE EXCEPTION 'seed_must_not_create_identity_links';
  END IF;
  IF (SELECT count(*) FROM seed_people s JOIN drivy.notification_preference p ON p.person_id=s.person_id
    WHERE NOT p.course_offers AND NOT p.course_reminders AND NOT p.course_changes AND NOT p.course_staff_alerts AND NOT p.messaging_mentions)<>27 THEN
    RAISE EXCEPTION 'seed_notification_preferences_incomplete';
  END IF;
END
$verify$;
