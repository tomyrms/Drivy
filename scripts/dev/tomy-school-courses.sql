-- Données de démonstration internes, exclusivement pour l'école ciblée par seed_context.
-- Fragment à inclure dans la transaction contrôlée du seed parent, avec ON_ERROR_STOP.
-- Préconditions : migrations 001..046 et suivantes ; tables temporaires seed_context
-- (school_id uuid, actor_id uuid = membership ADMIN), seed_people
-- (person_id, membership_id, learner_id, training_id uuid, role text, ordinal int).
-- seed_people contient au moins 16 élèves actifs, dont 4 B et 4 A/A1, et 3 moniteurs.
-- Les personnes synthétiques ont toutes leurs préférences de notification désactivées.
-- Aucun appel aux commandes métier/outbox, aucune modification des données existantes.
-- Le parent possède BEGIN/COMMIT et le verrou d'exécution ; ne pas exécuter seul.

DO $$
BEGIN
 IF (SELECT count(*) FROM seed_context)<>1 THEN
  RAISE EXCEPTION 'Le contexte doit désigner une seule école';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM seed_context c JOIN drivy.school s ON s.id=c.school_id
   JOIN drivy.membership m ON m.id=c.actor_id AND m.school_id=s.id
   JOIN drivy.person p ON p.id=m.person_id
   WHERE s.name='Tomy School' AND s.status='ACTIVE' AND m.status='ACTIVE'
    AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)) THEN
  RAISE EXCEPTION 'École ou appartenance administrateur incorrectes';
 END IF;
 IF EXISTS(SELECT 1 FROM seed_people p CROSS JOIN seed_context c
   LEFT JOIN drivy.membership m ON m.id=p.membership_id
   LEFT JOIN drivy.person d ON d.id=p.person_id
   LEFT JOIN drivy.notification_preference n ON n.person_id=p.person_id
   WHERE m.id IS NULL OR m.school_id<>c.school_id OR m.person_id<>p.person_id
    OR m.status<>'ACTIVE' OR d.status IS DISTINCT FROM 'ACTIVE'
    OR NOT p.role=ANY(m.roles) OR n.person_id IS NULL
    OR n.course_offers OR n.course_reminders OR n.course_changes OR n.course_staff_alerts
    OR EXISTS(SELECT 1 FROM drivy.push_device pd WHERE pd.person_id=p.person_id AND pd.revoked_at IS NULL)) THEN
  RAISE EXCEPTION 'Personnes synthétiques incomplètes ou notifications actives';
 END IF;
 IF (SELECT count(*) FROM seed_people WHERE role='INSTRUCTOR')<3
  OR (SELECT count(DISTINCT learner_id) FROM seed_people WHERE role='LEARNER')<16 THEN
  RAISE EXCEPTION 'Trois moniteurs et seize élèves synthétiques requis';
 END IF;
 IF EXISTS(SELECT 1 FROM seed_people p CROSS JOIN seed_context c
   LEFT JOIN drivy.learner_profile l ON l.id=p.learner_id
   LEFT JOIN drivy.training t ON t.id=p.training_id
   WHERE p.role='LEARNER' AND (l.id IS NULL OR l.school_id<>c.school_id
    OR l.person_id<>p.person_id OR l.archived_at IS NOT NULL OR t.id IS NULL
    OR t.school_id<>c.school_id OR t.learner_id<>l.id OR t.status<>'ACTIVE')) THEN
  RAISE EXCEPTION 'Dossiers ou formations synthétiques incohérents';
 END IF;
 IF (SELECT drivy.course_offer_response_minutes(c.school_id) FROM seed_context c) IS NULL THEN
  RAISE EXCEPTION 'Liste d’attente désactivée : conserver ce choix et adapter le seed';
 END IF;
END $$;

-- UUID déterministes par école, préfixe identifiable et bits de version/variant valides.
CREATE OR REPLACE FUNCTION pg_temp.tomy_course_id(label text) RETURNS uuid
LANGUAGE sql STABLE AS $$
 SELECT ('e311'||substr(h,1,4)||'-'||substr(h,5,4)||'-4'||substr(h,9,3)
   ||'-8'||substr(h,12,3)||'-'||substr(h,15,12))::uuid
 FROM (SELECT md5('tomy-school-courses-311:'||school_id::text||':'||label) h FROM seed_context) x
$$;

CREATE TEMP TABLE seed_course_context ON COMMIT DROP AS
SELECT c.school_id,c.actor_id,s.time_zone,
 coalesce((SELECT (x.created_at AT TIME ZONE s.time_zone)::date+35
   FROM drivy.course_series x WHERE x.id=pg_temp.tomy_course_id('series:1')),
   (now() AT TIME ZONE s.time_zone)::date-extract(isodow FROM now() AT TIME ZONE s.time_zone)::int+1) AS monday,
 coalesce(p.version,1) AS policy_version,coalesce(p.self_cancel_hours,24) AS self_cancel_hours
FROM seed_context c JOIN drivy.school s ON s.id=c.school_id
LEFT JOIN LATERAL (SELECT version,self_cancel_hours FROM drivy.course_policy_version
 WHERE school_id=c.school_id ORDER BY version DESC LIMIT 1) p ON true;

CREATE TEMP TABLE seed_course_learners ON COMMIT DROP AS
SELECT p.*,o.category_code,row_number() OVER(ORDER BY p.ordinal)::int AS learner_number,
 row_number() OVER(PARTITION BY CASE WHEN o.category_code IN('A','A1') THEN 'MOTO' ELSE o.category_code END
  ORDER BY p.ordinal)::int AS category_number
FROM seed_people p JOIN drivy.training t ON t.id=p.training_id
JOIN drivy.offering_version o ON o.id=t.offering_id WHERE p.role='LEARNER';

DO $$ BEGIN
 IF (SELECT count(*) FROM seed_course_learners WHERE category_code='B')<4
  OR (SELECT count(*) FROM seed_course_learners WHERE category_code IN('A','A1'))<4 THEN
  RAISE EXCEPTION 'Quatre élèves B et quatre élèves A/A1 requis pour les ateliers';
 END IF;
END $$;

INSERT INTO drivy.course_type(id,school_id,title,description,created_by,created_at)
SELECT pg_temp.tomy_course_id('type:'||v.key),c.school_id,v.title,v.description,c.actor_id,
 (c.monday-40)::timestamp AT TIME ZONE c.time_zone
FROM seed_course_context c CROSS JOIN (VALUES
 ('b','Atelier conduite B','Préparation en salle : observation, priorités et anticipation.'),
 ('a','Atelier moto A / A1','Préparation aux exercices de maniabilité et à la conduite en groupe.'),
 ('theory','Théorie accompagnée','Révision collective du code et échange autour des situations routières.')
) v(key,title,description)
ON CONFLICT(id) DO NOTHING;

CREATE TEMP TABLE seed_courses ON COMMIT DROP AS
SELECT v.*,pg_temp.tomy_course_id('series:'||v.n) AS id,
 CASE v.kind WHEN 'first-aid' THEN '0c0a5e00-0000-4000-8000-000000000002'::uuid
  WHEN 'awareness' THEN '0c0a5e00-0000-4000-8000-000000000001'::uuid
  ELSE pg_temp.tomy_course_id('type:'||v.kind) END AS type_id,
 p.membership_id AS instructor_id,p.person_id AS instructor_person_id
FROM (VALUES
 (1,'first-aid','PUBLISHED','Premiers secours — groupe du matin','Salle Léman',8,1,1,
  'Gestes de premiers secours, protection et alerte. Trois séances, dix heures au total.',12000),
 (2,'awareness','PUBLISHED','Sensibilisation — session du soir','Salle Lavaux',8,1,2,
  'Observation, circulation, dynamique et sécurité : quatre soirées de deux heures.',25000),
 (3,'first-aid','PUBLISHED','Premiers secours — vendredi et samedi','Salle Léman',6,1,1,
  'Formation sur deux jours : vendredi en soirée et samedi en deux blocs.',12000),
 (4,'awareness','PUBLISHED','Sensibilisation — prochaine session','Salle Lavaux',8,1,2,
  'Quatre soirées pour mieux anticiper les risques et partager la route.',25000),
 (5,'b','PUBLISHED','Priorités et anticipation — catégorie B','Salle Léman',8,1,3,
  'Analyse de situations, priorités et préparation aux parcours urbains.',8000),
 (6,'a','PUBLISHED','Maniabilité et sécurité — catégories A / A1','Piste de formation',8,1,3,
  'Atelier pratique de maniabilité. Casque, gants et équipement complet requis.',15000),
 (7,'theory','DRAFT','Théorie accompagnée — carrefours et signalisation','Salle Lavaux',10,1,1,
  'Révision collective des carrefours, panneaux et règles de priorité.',6000),
 (8,'a','CANCELLED','Maniabilité moto — groupe du samedi','Piste de formation',8,1,3,
  'Atelier de maniabilité et de freinage pour les catégories A et A1.',15000)
) v(n,kind,status,title,location,capacity,min_participants,instructor_number,description,price_cents)
JOIN seed_people p ON p.role='INSTRUCTOR' AND p.ordinal=v.instructor_number;

INSERT INTO drivy.course_series(id,school_id,type_id,version,status,title,description,location,conditions,
 teaching_language,responsible_membership_id,capacity,min_participants,policy_version,self_cancel_hours,
 created_by,created_at,updated_at,published_at,cancelled_at,cancel_reason)
SELECT s.id,c.school_id,s.type_id,CASE s.status WHEN 'DRAFT' THEN 1 WHEN 'CANCELLED' THEN 3 ELSE 2 END,
 s.status,s.title,s.description,s.location,
 'Inscription pour toutes les séances. Règlement sur place. Annulation libre jusqu’à '
  ||c.self_cancel_hours||' h avant la première séance ; contacter l’école ensuite.',
 'fr',s.instructor_id,s.capacity,s.min_participants,c.policy_version,c.self_cancel_hours,c.actor_id,
 (c.monday-35)::timestamp AT TIME ZONE c.time_zone,
 (CASE WHEN s.status='CANCELLED' THEN c.monday-1 ELSE c.monday-28 END)::timestamp AT TIME ZONE c.time_zone,
 CASE WHEN s.status<>'DRAFT' THEN (c.monday-28)::timestamp AT TIME ZONE c.time_zone END,
 CASE WHEN s.status='CANCELLED' THEN (c.monday-1)::timestamp AT TIME ZONE c.time_zone END,
 CASE WHEN s.status='CANCELLED' THEN 'Piste indisponible pour travaux ; nouvelles dates proposées aux participants.' END
FROM seed_courses s CROSS JOIN seed_course_context c
ON CONFLICT(id) DO NOTHING;

CREATE TEMP TABLE seed_course_occurrences ON COMMIT DROP AS
SELECT pg_temp.tomy_course_id('occurrence:'||v.series_number||':'||v.position) AS id,s.id AS series_id,
 s.n AS series_number,v.position,s.instructor_id,s.instructor_person_id,c.time_zone,
 ((c.monday+v.day_offset)+v.start_time::time) AT TIME ZONE c.time_zone AS starts_at,
 ((c.monday+v.day_offset)+v.end_time::time) AT TIME ZONE c.time_zone AS ends_at
FROM (VALUES
 (1,1,-10,'18:00','21:00'),(1,2,-9,'09:00','12:00'),(1,3,-9,'13:00','17:00'),
 (2,1,-7,'18:00','20:00'),(2,2,-6,'18:00','20:00'),(2,3,-5,'18:00','20:00'),(2,4,-4,'18:00','20:00'),
 (3,1,11,'18:00','21:00'),(3,2,12,'09:00','12:00'),(3,3,12,'13:00','17:00'),
 (4,1,7,'18:00','20:00'),(4,2,8,'18:00','20:00'),(4,3,9,'18:00','20:00'),(4,4,10,'18:00','20:00'),
 (5,1,-2,'09:00','11:00'),(6,1,19,'09:00','12:00'),(7,1,16,'18:00','20:00'),(8,1,5,'14:00','17:00')
) v(series_number,position,day_offset,start_time,end_time)
JOIN seed_courses s ON s.n=v.series_number CROSS JOIN seed_course_context c;

INSERT INTO drivy.course_occurrence(id,school_id,series_id,position,starts_at,ends_at,time_zone,
 instructor_membership_id,attendance_required)
SELECT o.id,c.school_id,o.series_id,o.position,o.starts_at,o.ends_at,o.time_zone,o.instructor_id,true
FROM seed_course_occurrences o CROSS JOIN seed_course_context c
ON CONFLICT(id) DO NOTHING;

CREATE TEMP TABLE seed_course_enrollments ON COMMIT DROP AS
SELECT pg_temp.tomy_course_id('enrollment:'||s.n||':'||p.learner_id) AS id,s.id AS series_id,
 s.n AS series_number,s.type_id,p.learner_id,p.person_id,
 CASE WHEN s.n IN(5,6,8) THEN p.category_number ELSE p.learner_number-v.first_number+1 END AS participant_number,
 CASE WHEN s.status='CANCELLED' THEN 'CANCELLED' ELSE 'ACTIVE' END AS status,
 s.price_cents,
 (SELECT min(o.starts_at) FROM seed_course_occurrences o WHERE o.series_id=s.id) AS first_start
FROM seed_courses s JOIN (VALUES(1,1,4),(2,1,6),(3,5,10),(4,7,12),(5,1,4),(6,1,4),(8,1,2))
 v(series_number,first_number,last_number) ON v.series_number=s.n
JOIN seed_course_learners p ON
 (s.n NOT IN(5,6,8) AND p.learner_number BETWEEN v.first_number AND v.last_number)
 OR (s.n=5 AND p.category_code='B' AND p.category_number BETWEEN v.first_number AND v.last_number)
 OR (s.n IN(6,8) AND p.category_code IN('A','A1') AND p.category_number BETWEEN v.first_number AND v.last_number);

INSERT INTO drivy.course_enrollment(id,school_id,series_id,learner_id,version,status,source,
 policy_version,self_cancel_hours,self_cancel_deadline,created_by,created_at,
 cancelled_at,cancelled_by,cancel_kind,cancel_reason)
SELECT e.id,c.school_id,e.series_id,e.learner_id,CASE WHEN e.status='CANCELLED' THEN 2 ELSE 1 END,
 e.status,'STAFF',c.policy_version,c.self_cancel_hours,e.first_start-make_interval(hours=>c.self_cancel_hours),
 c.actor_id,(c.monday-21)::timestamp AT TIME ZONE c.time_zone,
 CASE WHEN e.status='CANCELLED' THEN (c.monday-1)::timestamp AT TIME ZONE c.time_zone END,
 CASE WHEN e.status='CANCELLED' THEN c.actor_id END,
 CASE WHEN e.status='CANCELLED' THEN 'SERIES_CANCELLED' END,
 CASE WHEN e.status='CANCELLED' THEN 'Piste indisponible pour travaux ; nouvelles dates proposées aux participants.' END
FROM seed_course_enrollments e CROSS JOIN seed_course_context c
ON CONFLICT(id) DO NOTHING;

-- Série 3 complète : aucune proposition ni événement ne peut être émis au chargement.
INSERT INTO drivy.course_waitlist_entry(id,school_id,series_id,learner_id,queued_at,status)
SELECT pg_temp.tomy_course_id('waitlist:3:'||p.learner_id),c.school_id,s.id,p.learner_id,
 ((c.monday-2)::timestamp+make_interval(mins=>p.learner_number)) AT TIME ZONE c.time_zone,'WAITING'
FROM seed_course_learners p JOIN seed_courses s ON s.n=3 CROSS JOIN seed_course_context c
WHERE p.learner_number BETWEEN 11 AND 13
ON CONFLICT(id) DO NOTHING;

-- Occupations identiques à celles des commandes. Le conflit d'exclusion reste bloquant :
-- ON CONFLICT(id) ne masque jamais une collision avec une leçon ou un autre cours.
INSERT INTO drivy.reservation(id,school_id,course_occurrence_id,resource_id,resource_role,during,active)
SELECT pg_temp.tomy_course_id('reservation:instructor:'||o.id),c.school_id,o.id,m.person_id,'INSTRUCTOR',
 tstzrange(o.starts_at,o.ends_at,'[)'),s.status<>'CANCELLED'
FROM seed_course_occurrences wanted JOIN drivy.course_occurrence o ON o.id=wanted.id
JOIN drivy.course_series s ON s.id=o.series_id
JOIN drivy.membership m ON m.id=o.instructor_membership_id CROSS JOIN seed_course_context c
WHERE s.status<>'DRAFT'
ON CONFLICT(id) DO NOTHING;

INSERT INTO drivy.reservation(id,school_id,course_occurrence_id,course_enrollment_id,resource_id,resource_role,during,active)
SELECT pg_temp.tomy_course_id('reservation:learner:'||e.id||':'||o.id),c.school_id,o.id,e.id,l.person_id,'LEARNER',
 tstzrange(o.starts_at,o.ends_at,'[)'),e.status='ACTIVE' AND s.status<>'CANCELLED'
FROM seed_course_enrollments wanted JOIN drivy.course_enrollment e ON e.id=wanted.id
JOIN drivy.learner_profile l ON l.id=e.learner_id JOIN drivy.course_series s ON s.id=e.series_id
JOIN drivy.course_occurrence o ON o.series_id=e.series_id CROSS JOIN seed_course_context c
ON CONFLICT(id) DO NOTHING;

CREATE TEMP TABLE seed_course_attendance ON COMMIT DROP AS
SELECT e.id AS enrollment_id,o.id AS occurrence_id,e.series_number,e.participant_number,o.position,
 CASE WHEN e.series_number=2 AND o.position=4 AND e.participant_number=5 THEN 'ABSENT'
  WHEN e.series_number=2 AND o.position=4 AND e.participant_number=6 THEN 'EXCUSED'
  WHEN e.series_number=5 AND e.participant_number=4 THEN 'ABSENT' ELSE 'PRESENT' END AS status,
 CASE WHEN e.series_number=1 AND e.participant_number=2 AND o.position=1 THEN 2 ELSE 1 END AS version,
 o.ends_at+interval '15 minutes' AS recorded_at
FROM seed_course_enrollments e JOIN seed_course_occurrences o ON o.series_id=e.series_id
WHERE e.series_number IN(1,2,5);

INSERT INTO drivy.course_attendance(school_id,enrollment_id,occurrence_id,status,version,recorded_by,recorded_at)
SELECT c.school_id,a.enrollment_id,a.occurrence_id,a.status,a.version,c.actor_id,a.recorded_at
FROM seed_course_attendance a CROSS JOIN seed_course_context c
ON CONFLICT(enrollment_id,occurrence_id) DO NOTHING;

INSERT INTO drivy.course_attendance_history(id,school_id,enrollment_id,occurrence_id,status,version,recorded_by,recorded_at,note)
SELECT pg_temp.tomy_course_id('attendance:'||a.enrollment_id||':'||a.occurrence_id||':'||v.n),
 c.school_id,a.enrollment_id,a.occurrence_id,CASE WHEN a.version=2 AND v.n=1 THEN 'ABSENT' ELSE a.status END,
 v.n,c.actor_id,a.recorded_at-CASE WHEN a.version=2 AND v.n=1 THEN interval '10 minutes' ELSE interval '0' END,
 CASE WHEN a.version=2 AND v.n=2 THEN 'Arrivée confirmée sur la feuille signée.'
  WHEN a.status='EXCUSED' THEN 'Absence annoncée au secrétariat.' END
FROM seed_course_attendance a CROSS JOIN LATERAL generate_series(1,a.version) v(n) CROSS JOIN seed_course_context c
ON CONFLICT(id) DO NOTHING;

INSERT INTO drivy.course_payment_record(id,school_id,enrollment_id,amount_cents,method,recorded_by,recorded_at,
 voided_at,voided_by,void_reason,note)
SELECT pg_temp.tomy_course_id('payment:'||e.id),c.school_id,e.id,
 CASE WHEN e.series_number IN(3,6,8) THEN e.price_cents/2 WHEN e.series_number=4 THEN 10000 ELSE e.price_cents END,
 'ON_SITE',c.actor_id,
 CASE WHEN e.series_number IN(1,2,5) THEN e.first_start+interval '10 minutes'
  ELSE (c.monday-3)::timestamp AT TIME ZONE c.time_zone END,
 CASE WHEN e.series_number=8 THEN (c.monday-1)::timestamp AT TIME ZONE c.time_zone END,
 CASE WHEN e.series_number=8 THEN c.actor_id END,
 CASE WHEN e.series_number=8 THEN 'Saisie annulée : règlement rattaché à une autre session.' END,
 CASE WHEN e.series_number IN(3,4,6,8) THEN 'Acompte reçu au secrétariat.' ELSE 'Règlement reçu sur place.' END
FROM seed_course_enrollments e CROSS JOIN seed_course_context c
WHERE e.series_number=1 OR (e.series_number=2 AND e.participant_number<>4)
 OR (e.series_number IN(3,4) AND e.participant_number<=3)
 OR (e.series_number=5 AND e.participant_number<>2)
 OR (e.series_number=6 AND e.participant_number<=2)
 OR (e.series_number=8 AND e.participant_number=1)
ON CONFLICT(id) DO NOTHING;

-- Une correction conservée, sans effet sur les présences ou les validations.
INSERT INTO drivy.course_payment_record(id,school_id,enrollment_id,amount_cents,method,recorded_by,recorded_at,
 voided_at,voided_by,void_reason,note)
SELECT pg_temp.tomy_course_id('payment:corrected:'||e.id),c.school_id,e.id,10000,'ON_SITE',c.actor_id,
 e.first_start+interval '2 minutes',e.first_start+interval '5 minutes',c.actor_id,
 'Montant incomplet saisi ; règlement de CHF 120 enregistré séparément.','Règlement reçu sur place.'
FROM seed_course_enrollments e CROSS JOIN seed_course_context c
WHERE e.series_number=1 AND e.participant_number=1
ON CONFLICT(id) DO NOTHING;

INSERT INTO drivy.course_completion(id,school_id,learner_id,type_id,series_id,validated_by,validated_at,note)
SELECT pg_temp.tomy_course_id('completion:'||e.id),c.school_id,e.learner_id,e.type_id,e.series_id,c.actor_id,
 (SELECT max(o.ends_at)+interval '1 hour' FROM seed_course_occurrences o WHERE o.series_id=e.series_id),
 'Toutes les séances obligatoires ont été suivies ; validation enregistrée par le secrétariat.'
FROM seed_course_enrollments e CROSS JOIN seed_course_context c
WHERE (e.series_number=1 AND e.participant_number<=3)
 OR (e.series_number=2 AND e.participant_number<=4)
 OR (e.series_number=5 AND e.participant_number<=2)
ON CONFLICT(id) DO NOTHING;

-- Garde de cohérence : le seed s'arrête au lieu de réparer/réécrire une donnée étrangère.
DO $$ BEGIN
 IF (SELECT count(*) FROM seed_courses)<>8 OR (SELECT count(*) FROM seed_course_enrollments)<>32 THEN
  RAISE EXCEPTION 'Volume ou distribution des personnes incompatible';
 END IF;
 IF EXISTS(SELECT 1 FROM seed_courses wanted JOIN drivy.course_series s ON s.id=wanted.id
   CROSS JOIN seed_course_context c WHERE s.school_id<>c.school_id OR s.type_id<>wanted.type_id)
  OR EXISTS(SELECT 1 FROM seed_course_enrollments wanted JOIN drivy.course_enrollment e ON e.id=wanted.id
   CROSS JOIN seed_course_context c WHERE e.school_id<>c.school_id OR e.series_id<>wanted.series_id OR e.learner_id<>wanted.learner_id)
  OR EXISTS(SELECT 1 FROM seed_course_occurrences wanted JOIN drivy.course_occurrence o ON o.id=wanted.id
   CROSS JOIN seed_course_context c WHERE o.school_id<>c.school_id OR o.series_id<>wanted.series_id OR o.position<>wanted.position) THEN
  RAISE EXCEPTION 'Collision d’identifiants de cours';
 END IF;
 IF EXISTS(SELECT 1 FROM drivy.course_series s JOIN seed_courses wanted ON wanted.id=s.id
   WHERE (SELECT count(*) FROM drivy.course_enrollment e WHERE e.series_id=s.id AND e.status='ACTIVE')
    +(SELECT count(*) FROM drivy.course_seat_offer o WHERE o.series_id=s.id AND o.status='ACTIVE' AND o.expires_at>now())>s.capacity) THEN
  RAISE EXCEPTION 'Capacité de cours dépassée';
 END IF;
 IF EXISTS(SELECT 1 FROM drivy.course_completion x JOIN seed_courses s ON s.id=x.series_id
   JOIN drivy.course_enrollment e ON e.series_id=x.series_id AND e.learner_id=x.learner_id
   WHERE x.revoked_at IS NULL AND EXISTS(SELECT 1 FROM drivy.course_occurrence o
    LEFT JOIN drivy.course_attendance a ON a.occurrence_id=o.id AND a.enrollment_id=e.id
    WHERE o.series_id=x.series_id AND o.attendance_required AND (o.ends_at>now() OR a.status IS DISTINCT FROM 'PRESENT'))) THEN
  RAISE EXCEPTION 'Validation sans toutes les présences requises';
 END IF;
 IF EXISTS(SELECT 1 FROM drivy.course_event_outbox e JOIN seed_courses s ON s.id=e.series_id WHERE e.delivered_at IS NULL)
  OR EXISTS(SELECT 1 FROM drivy.push_notification p JOIN seed_courses s ON s.id=p.series_id WHERE p.status='PENDING') THEN
  RAISE EXCEPTION 'Notification de cours en attente : contrôler avant de continuer';
 END IF;
END $$;

-- Compteurs limités aux identifiants du fragment, aucune donnée nominative en sortie.
SELECT 'course_type' AS entity,count(*) AS count FROM drivy.course_type
 WHERE id IN(pg_temp.tomy_course_id('type:b'),pg_temp.tomy_course_id('type:a'),pg_temp.tomy_course_id('type:theory'))
UNION ALL SELECT 'course_series',count(*) FROM drivy.course_series WHERE id IN(SELECT id FROM seed_courses)
UNION ALL SELECT 'course_occurrence',count(*) FROM drivy.course_occurrence WHERE series_id IN(SELECT id FROM seed_courses)
UNION ALL SELECT 'course_enrollment',count(*) FROM drivy.course_enrollment WHERE id IN(SELECT id FROM seed_course_enrollments)
UNION ALL SELECT 'course_waitlist_entry',count(*) FROM drivy.course_waitlist_entry WHERE series_id IN(SELECT id FROM seed_courses)
UNION ALL SELECT 'course_attendance',count(*) FROM drivy.course_attendance WHERE enrollment_id IN(SELECT id FROM seed_course_enrollments)
UNION ALL SELECT 'course_attendance_history',count(*) FROM drivy.course_attendance_history WHERE enrollment_id IN(SELECT id FROM seed_course_enrollments)
UNION ALL SELECT 'course_payment_record',count(*) FROM drivy.course_payment_record WHERE enrollment_id IN(SELECT id FROM seed_course_enrollments)
UNION ALL SELECT 'course_completion',count(*) FROM drivy.course_completion WHERE series_id IN(SELECT id FROM seed_courses)
UNION ALL SELECT 'reservation',count(*) FROM drivy.reservation WHERE course_occurrence_id IN(SELECT id FROM seed_course_occurrences)
ORDER BY entity;
