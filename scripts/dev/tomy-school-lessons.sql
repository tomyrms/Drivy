-- Fragment d'amorçage de Tomy School, demandé par le porteur le 29 octobre 2026.
-- À inclure dans la transaction du script parent, après sauvegarde et catalogue/personnes.
-- Le parent fixe ON_ERROR_STOP, lock_timeout, statement_timeout et décide ROLLBACK/COMMIT.
-- Il fournit pg_temp.seed_uuid(text), UUID déterministe avec bits version 4 / variant 8.
-- Contexte TEMP requis : seed_context(school_id uuid, actor_id uuid), une seule ligne ;
-- actor_id est un membership ADMIN actif. seed_people(person_id,membership_id,learner_id,
-- training_id,role,ordinal) : 20–24 LEARNER, 3 INSTRUCTOR, ordinal positif unique par rôle.
-- Les formations élèves sont ACTIVE, commencées au moins 14 jours avant l'amorçage,
-- avec offre/curriculum/procédure approuvés et au moins deux compétences. Les prestations
-- INDIVIDUAL_LESSON de 30–90 min et leurs conditions couvrent toute la fenêtre ±14 jours.
-- seed_catalogue est fourni par le parent ; les produits sont relus par catégorie/validité
-- dans les tables réelles, sans supposer que formation_id désigne une prestation.
-- Exécution opérateur disposant des droits requis ; ce fichier ne change ni rôle ni RLS.
-- Aucun trajet/GPS, consentement, vérification humaine de permis, paiement, notification,
-- invitation, événement outbox ou faux reçu de commande API n'est créé.
-- Tous les textes scolaires ci-dessous sont fictifs ; ils ne portent pas de suffixe « test ».

SET LOCAL TIME ZONE 'Europe/Zurich';

DO $guard$
DECLARE s uuid; a uuid; learners integer; instructors integer;
BEGIN
  IF (SELECT count(*) FROM seed_context) <> 1 THEN RAISE EXCEPTION 'seed_context must contain exactly one school'; END IF;
  SELECT school_id, actor_id INTO STRICT s, a FROM seed_context;
  PERFORM 1 FROM drivy.school WHERE id=s AND name='Tomy School' AND status='ACTIVE' AND time_zone='Europe/Zurich' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Expected active Tomy School in Europe/Zurich'; END IF;
  IF NOT EXISTS (SELECT 1 FROM drivy.membership WHERE school_id=s AND id=a AND status='ACTIVE' AND 'ADMIN'=ANY(roles)) THEN
    RAISE EXCEPTION 'seed_context.actor_id must be the active school administrator membership';
  END IF;
  SELECT count(*) FILTER(WHERE upper(role)='LEARNER'), count(*) FILTER(WHERE upper(role)='INSTRUCTOR')
    INTO learners,instructors FROM seed_people;
  IF learners NOT BETWEEN 20 AND 24 OR instructors<>3 THEN RAISE EXCEPTION 'Expected 20–24 learners and three instructors'; END IF;
  IF EXISTS (SELECT 1 FROM seed_people WHERE ordinal IS NULL OR ordinal<1)
     OR EXISTS (SELECT 1 FROM seed_people GROUP BY upper(role),ordinal HAVING count(*)>1) THEN
    RAISE EXCEPTION 'seed_people requires a positive unique ordinal per role';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people p LEFT JOIN drivy.membership m ON m.school_id=s AND m.id=p.membership_id
    LEFT JOIN drivy.person person ON person.id=p.person_id
    WHERE upper(p.role) IN('LEARNER','INSTRUCTOR') AND (m.id IS NULL OR m.person_id<>p.person_id
      OR m.status<>'ACTIVE' OR person.status IS DISTINCT FROM 'ACTIVE' OR NOT upper(p.role)=ANY(m.roles))) THEN
    RAISE EXCEPTION 'Seed people must belong to this school with their declared active role';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_people p LEFT JOIN drivy.training t ON t.school_id=s AND t.id=p.training_id
    LEFT JOIN drivy.learner_profile lp ON lp.school_id=s AND lp.id=p.learner_id
    LEFT JOIN drivy.offering_version o ON o.school_id=s AND o.id=t.offering_id
    LEFT JOIN drivy.curriculum_version cv ON cv.school_id=s AND cv.id=o.curriculum_version_id
    LEFT JOIN drivy.school_policy_version policy ON policy.school_id=s AND policy.id=o.policy_version_id
    WHERE upper(p.role)='LEARNER' AND (t.id IS NULL OR t.learner_id IS DISTINCT FROM p.learner_id OR lp.person_id IS DISTINCT FROM p.person_id
      OR lp.archived_at IS NOT NULL OR t.status<>'ACTIVE' OR o.enabled IS DISTINCT FROM true
      OR cv.approved IS DISTINCT FROM true OR policy.approved IS DISTINCT FROM true
      OR (SELECT count(*) FROM drivy.competency_definition c WHERE c.school_id=s AND c.curriculum_version_id=cv.id)<2)) THEN
    RAISE EXCEPTION 'Each learner needs an active matching training and an approved curriculum with two competencies';
  END IF;
END $guard$;

-- La date du premier amorçage est conservée par la plage déterministe ; un rejeu ultérieur
-- ne fait pas glisser le calendrier. Aucun UPDATE n'est appliqué aux plages déjà présentes.
CREATE TEMP TABLE tomy_lesson_clock ON COMMIT DROP AS
SELECT coalesce((SELECT (a.created_at AT TIME ZONE 'Europe/Zurich')::date FROM drivy.availability_rule a
  WHERE a.id=pg_temp.seed_uuid('tomy311:availability:'||c.school_id||':1:week')),current_date) AS day
FROM seed_context c;

CREATE TEMP TABLE tomy_lesson_staff ON COMMIT DROP AS
SELECT p.*,row_number() OVER(ORDER BY ordinal,membership_id)::integer AS staff_no
FROM seed_people p WHERE upper(role)='INSTRUCTOR';
CREATE TEMP TABLE tomy_lesson_learners ON COMMIT DROP AS
SELECT p.*,row_number() OVER(ORDER BY p.ordinal,p.learner_id)::integer AS learner_no,
  i.membership_id AS instructor_id,i.person_id AS instructor_person_id
FROM seed_people p JOIN tomy_lesson_staff i ON i.staff_no=1+((p.ordinal-1)%3)
WHERE upper(p.role)='LEARNER';

INSERT INTO drivy.availability_rule(id,school_id,instructor_membership_id,weekdays,local_start,local_end,valid_from,created_at)
SELECT pg_temp.seed_uuid('tomy311:availability:'||c.school_id||':'||i.staff_no||':'||x.key),c.school_id,i.membership_id,
  x.weekdays,x.starts,x.ends,k.day-30,k.day::timestamptz
FROM seed_context c CROSS JOIN tomy_lesson_clock k CROSS JOIN tomy_lesson_staff i
CROSS JOIN (VALUES ('week',ARRAY[1,2,3,4,5],time '08:00',time '21:00'),
                   ('saturday',ARRAY[6],time '08:00',time '18:00')) x(key,weekdays,starts,ends)
ON CONFLICT DO NOTHING;

INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from,created_at)
SELECT pg_temp.seed_uuid('tomy311:assignment:'||c.school_id||':'||p.training_id||':'||p.instructor_id),
  c.school_id,p.training_id,p.instructor_id,(k.day-30)::timestamptz,(k.day-30)::timestamptz
FROM seed_context c CROSS JOIN tomy_lesson_clock k CROSS JOIN tomy_lesson_learners p
WHERE NOT EXISTS (SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=c.school_id AND a.training_id=p.training_id
  AND a.instructor_membership_id=p.instructor_id AND a.valid_from<=(k.day-14)::timestamptz
  AND (a.valid_until IS NULL OR a.valid_until>=(k.day+15)::timestamptz))
ON CONFLICT DO NOTHING;

-- Indisponibilités en dehors des créneaux de leçon et des cours du soir. Une fermeture
-- incompatible avec une réservation existante est ignorée ; aucun rendez-vous n'est déplacé.
INSERT INTO drivy.closure(id,school_id,instructor_membership_id,starts_at,ends_at,reason,created_at)
SELECT pg_temp.seed_uuid('tomy311:closure:'||c.school_id||':'||i.staff_no),c.school_id,i.membership_id,
  slot.starts,slot.ends,CASE i.staff_no WHEN 1 THEN 'Rendez-vous personnel' WHEN 2 THEN 'Journée de formation continue' ELSE 'Congé' END,k.day::timestamptz
FROM seed_context c CROSS JOIN tomy_lesson_clock k CROSS JOIN tomy_lesson_staff i
CROSS JOIN LATERAL (SELECT CASE WHEN i.staff_no=1 THEN k.day+3 ELSE
  (SELECT weekday.day FROM (SELECT d::date AS day,row_number() OVER(ORDER BY d) AS day_no
    FROM generate_series((k.day+1)::timestamp,(k.day+14)::timestamp,interval '1 day') d
    WHERE extract(isodow FROM d)<=5) weekday WHERE weekday.day_no=9) END AS day) absence
CROSS JOIN LATERAL (SELECT (absence.day+CASE WHEN i.staff_no=1 THEN time '17:00' ELSE time '08:00' END) AT TIME ZONE 'Europe/Zurich' AS starts,
  (absence.day+time '18:00') AT TIME ZONE 'Europe/Zurich' AS ends) slot
WHERE NOT EXISTS (SELECT 1 FROM drivy.reservation r WHERE r.school_id=c.school_id AND r.resource_id=i.person_id
  AND r.active AND r.during && tstzrange(slot.starts,slot.ends,'[)'))
AND NOT EXISTS (SELECT 1 FROM drivy.lesson l WHERE l.school_id=c.school_id AND l.instructor_membership_id=i.membership_id
  AND l.status='PLANNED' AND tstzrange(l.planned_start,l.planned_end+make_interval(mins=>l.buffer_minutes_snapshot),'[)')
    && tstzrange(slot.starts,slot.ends,'[)'))
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE tomy_lesson_slots ON COMMIT DROP AS
WITH weekdays AS (
  SELECT d::date AS day,CASE WHEN d::date<k.day THEN 0 ELSE 1 END AS half,
    row_number() OVER(PARTITION BY d::date<k.day ORDER BY d)::integer AS day_no
  FROM tomy_lesson_clock k CROSS JOIN LATERAL generate_series((k.day-14)::timestamp,(k.day+14)::timestamp,interval '1 day') d
  WHERE d::date<>k.day AND extract(isodow FROM d)<=5
), slots AS (
  SELECT w.day,w.half,(w.day+x.clock) AT TIME ZONE 'Europe/Zurich' AS starts
  FROM weekdays w CROSS JOIN (VALUES(time '09:00'),(time '11:00'),(time '14:00')) x(clock)
  WHERE day_no IN(1,3,5,6,8,10)
)
SELECT row_number() OVER(ORDER BY starts)::integer AS ordinal,day,half,starts FROM slots;

-- Leçon et enfants sont atomiques. Si l'identifiant déterministe existe, le bloc entier
-- est sauté : aucun bilan, prix, statut, champ privé ou horaire modifié depuis n'est rétabli.
DO $lessons$
DECLARE
  s uuid; actor uuid; anchor date; total_learners integer; slot record; pupil record; product record; training record;
  lesson_id uuid; inserted_id uuid; draft_id uuid; account_id uuid; revision_id uuid;
  ends timestamptz; state text; selection jsonb; evaluations jsonb; snapshot jsonb; prepared_goals jsonb;
  worked text; observed text; following text; is_private boolean; anomaly text;
  comp_ids uuid[]; comp_labels text[]; created integer:=0; skipped integer:=0;
BEGIN
  SELECT school_id,actor_id INTO STRICT s,actor FROM seed_context;
  SELECT day INTO STRICT anchor FROM tomy_lesson_clock;
  SELECT count(*) INTO total_learners FROM tomy_lesson_learners;
  FOR slot IN SELECT * FROM tomy_lesson_slots ORDER BY ordinal LOOP
    lesson_id:=pg_temp.seed_uuid('tomy311:lesson:'||s||':'||slot.ordinal);
    IF EXISTS(SELECT 1 FROM drivy.lesson WHERE id=lesson_id) THEN CONTINUE; END IF;
    SELECT * INTO STRICT pupil FROM tomy_lesson_learners WHERE learner_no=1+(((slot.ordinal-1)*CASE WHEN total_learners%5=0 THEN 7 ELSE 5 END)%total_learners);
    SELECT t.*,o.category_code,o.curriculum_version_id,o.policy_version_id INTO STRICT training
      FROM drivy.training t JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
      WHERE t.school_id=s AND t.id=pupil.training_id;
    IF training.started_on IS NULL OR training.started_on>slot.day THEN
      RAISE EXCEPTION 'Training start must cover the four-week lesson window';
    END IF;
    SELECT p.* INTO product FROM drivy.service_product_version p
      JOIN drivy.commercial_terms_version terms ON terms.school_id=p.school_id AND terms.id=p.terms_version_id
      WHERE p.school_id=s AND p.type='INDIVIDUAL_LESSON' AND p.category_code=training.category_code
      AND p.enabled AND p.duration_minutes BETWEEN 30 AND 90 AND p.valid_from<=slot.day AND (p.valid_until IS NULL OR p.valid_until>=slot.day)
      AND terms.approved AND terms.valid_from<=slot.day AND (terms.valid_until IS NULL OR terms.valid_until>=slot.day)
      ORDER BY p.duration_minutes,p.version DESC,p.id LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'A valid 30–90 minute individual lesson product and approved terms are required'; END IF;
    ends:=slot.starts+make_interval(mins=>product.duration_minutes);
    IF NOT EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=s AND a.training_id=pupil.training_id
      AND a.instructor_membership_id=pupil.instructor_id AND a.valid_from<=slot.starts AND (a.valid_until IS NULL OR a.valid_until>=ends)) THEN
      skipped:=skipped+1; CONTINUE;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM drivy.availability_rule a WHERE a.school_id=s AND a.instructor_membership_id=pupil.instructor_id
        AND a.removed_at IS NULL AND extract(isodow FROM slot.day)::integer=ANY(a.weekdays)
        AND a.valid_from<=slot.day AND (a.valid_until IS NULL OR a.valid_until>=slot.day)
        AND (slot.starts AT TIME ZONE 'Europe/Zurich')::time>=a.local_start
        AND ((ends+interval '10 minutes') AT TIME ZONE 'Europe/Zurich')::time<=a.local_end)
      OR EXISTS(SELECT 1 FROM drivy.closure c WHERE c.school_id=s AND c.instructor_membership_id=pupil.instructor_id AND c.removed_at IS NULL
        AND tstzrange(c.starts_at,c.ends_at,'[)') && tstzrange(slot.starts,ends+interval '10 minutes','[)'))
      OR EXISTS(SELECT 1 FROM drivy.reservation r WHERE r.school_id=s AND r.active
        AND ((r.resource_id=pupil.instructor_person_id AND r.during && tstzrange(slot.starts,ends+interval '10 minutes','[)'))
          OR (r.resource_id=pupil.person_id AND r.during && tstzrange(slot.starts,ends,'[)'))))
      OR EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id AND m.id=l.instructor_membership_id
        WHERE l.school_id=s AND l.status<>'CANCELLED'
        AND ((m.person_id=pupil.instructor_person_id AND tstzrange(l.planned_start,l.planned_end+make_interval(mins=>l.buffer_minutes_snapshot),'[)')
          && tstzrange(slot.starts,ends+interval '10 minutes','[)')) OR (l.learner_person_id=pupil.person_id
          AND tstzrange(l.planned_start,l.planned_end,'[)') && tstzrange(slot.starts,ends,'[)')))) THEN
      skipped:=skipped+1; CONTINUE;
    END IF;
    state:=CASE WHEN slot.ordinal IN(6,30) THEN 'CANCELLED' WHEN slot.ordinal=15 THEN 'NO_SHOW'
      WHEN slot.half=0 THEN 'COMPLETED' ELSE 'PLANNED' END;
    is_private:=state='COMPLETED' AND slot.ordinal%7=0;
    selection:=jsonb_build_object('mode','UNIT_PRICE','serviceProductVersionId',product.id,'quantity',1,
      'entitlementLotId',NULL,'acceptedTermsVersionId',product.terms_version_id);
    -- Un historique pédagogique ne vaut pas contrôle humain du permis. Ce rappel explicite
    -- évite d'inventer cette validation, y compris si le dossier est seulement minimal.
    anomaly:=CASE WHEN state='COMPLETED' THEN 'Contrôle du permis à rapprocher du dossier administratif.' ELSE NULL END;
    inserted_id:=NULL;
    INSERT INTO drivy.lesson(id,school_id,version,training_id,learner_id,learner_person_id,instructor_membership_id,
      planned_start,planned_end,time_zone,meeting_point,status,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,
      commercial_selection,actual_start,actual_end,completion_anomaly_reason,cancel_reason_code,cancel_comment,no_show_reason,report_private,created_at)
    VALUES(lesson_id,s,CASE WHEN state='PLANNED' THEN 1 ELSE 2 END,pupil.training_id,pupil.learner_id,pupil.person_id,pupil.instructor_id,
      slot.starts,ends,'Europe/Zurich',(ARRAY['Devant l’école','Gare de Lausanne, sortie nord','Place du Marché, Renens'])[1+((slot.ordinal-1)%3)],
      state,product.unit_price_cents,10,training.policy_version_id,selection,
      CASE WHEN state='COMPLETED' THEN slot.starts END,CASE WHEN state='COMPLETED' THEN ends END,anomaly,
      CASE WHEN state='CANCELLED' THEN 'LEARNER_REQUEST' END,CASE WHEN state='CANCELLED' THEN 'Empêchement signalé la veille ; nouveau créneau à convenir.' END,
      CASE WHEN state='NO_SHOW' THEN 'Élève absent au point de rendez-vous ; reprise de contact à prévoir.' END,is_private,
      least(anchor::timestamptz,slot.starts-interval '5 days'))
    ON CONFLICT DO NOTHING RETURNING id INTO inserted_id;
    IF inserted_id IS NULL THEN CONTINUE; END IF;
    created:=created+1;

    -- Même état que les commandes actuelles : réalisation désactive ses occupations ;
    -- absence constatée après la fin conserve l'occupation écoulée ; annulation la veille la libère.
    INSERT INTO drivy.reservation(id,school_id,lesson_id,resource_id,resource_role,during,active) VALUES
      (pg_temp.seed_uuid('tomy311:reservation:'||lesson_id||':learner'),s,lesson_id,pupil.person_id,'LEARNER',tstzrange(slot.starts,ends,'[)'),state IN('PLANNED','NO_SHOW')),
      (pg_temp.seed_uuid('tomy311:reservation:'||lesson_id||':instructor'),s,lesson_id,pupil.instructor_person_id,'INSTRUCTOR',tstzrange(slot.starts,ends+interval '10 minutes','[)'),state IN('PLANNED','NO_SHOW'))
    ON CONFLICT DO NOTHING;
    IF (SELECT count(*) FROM drivy.reservation r WHERE r.school_id=s AND r.lesson_id=inserted_id)<>2 THEN
      RAISE EXCEPTION 'Both lesson reservations must be present';
    END IF;
    INSERT INTO drivy.lesson_commercial_revision(school_id,lesson_id,revision,operation_id,commercial_selection,price_cents,duration_minutes,actor_membership_id,reason,created_at)
    VALUES(s,lesson_id,1,pg_temp.seed_uuid('tomy311:commercial-operation:'||lesson_id),selection,product.unit_price_cents,product.duration_minutes,actor,
      'Prix convenu à la réservation.',least(anchor::timestamptz,slot.starts-interval '5 days')) ON CONFLICT DO NOTHING;

    SELECT array_agg(c.id ORDER BY c.sort_order,c.id),array_agg(c.label ORDER BY c.sort_order,c.id) INTO comp_ids,comp_labels
      FROM (SELECT id,label,sort_order FROM drivy.competency_definition WHERE school_id=s AND curriculum_version_id=training.curriculum_version_id ORDER BY sort_order,id LIMIT 2) c;
    prepared_goals:=jsonb_build_array(jsonb_build_object('label',comp_labels[1],'competencyId',comp_ids[1]),
      jsonb_build_object('label',comp_labels[2],'competencyId',comp_ids[2]));
    -- Le trigger de leçon vient de créer cette préparation vide : aucune ancienne préparation n'est éditée.
    UPDATE drivy.lesson_preparation p SET goals=prepared_goals,version=2 WHERE p.school_id=s AND p.lesson_id=inserted_id;

    IF state<>'PLANNED' THEN
      account_id:=pg_temp.seed_uuid('tomy311:account:'||lesson_id);
      INSERT INTO drivy.lesson_account(id,school_id,lesson_id,planned_price_cents)
        VALUES(account_id,s,lesson_id,product.unit_price_cents) ON CONFLICT DO NOTHING;
    END IF;
    IF state<>'COMPLETED' THEN CONTINUE; END IF;
    INSERT INTO drivy.charge_entry(id,school_id,account_id,kind,amount_signed_cents,reason,operation_id,created_at)
    VALUES(pg_temp.seed_uuid('tomy311:charge:'||lesson_id),s,account_id,'INITIAL',product.unit_price_cents,
      'Prix unitaire convenu à la réservation ; leçon réalisée.',pg_temp.seed_uuid('tomy311:complete-operation:'||lesson_id),ends) ON CONFLICT DO NOTHING;

    worked:=CASE training.category_code WHEN 'BE' THEN 'Attelage, contrôles de l’ensemble et marche arrière avec la remorque.'
      WHEN 'A' THEN 'Placement dans les virages, freinage progressif et recherche du regard.'
      WHEN 'A1' THEN 'Équilibre à faible allure, démarrages et contrôles avant de changer de direction.'
      ELSE (ARRAY['Approche des giratoires et anticipation des priorités en circulation urbaine.',
        'Démarrages en côte, arrêts précis et coordination des commandes.',
        'Stationnement en marche arrière et observation autour du véhicule.'])[1+(slot.ordinal%3)] END;
    observed:=(ARRAY['Les consignes sont comprises. Le regard doit se porter plus tôt vers la prochaine zone de décision.',
      'Bonne progression dans les situations répétées. Un rappel reste utile avant les changements de direction.',
      'Conduite plus régulière et commandes mieux dosées. Garder une marge de sécurité lorsque le trafic se densifie.',
      'Les repères sont retrouvés sans aide sur les passages connus ; travailler leur transfert dans un nouvel environnement.'])[1+(slot.ordinal%4)];
    following:=CASE training.category_code WHEN 'BE' THEN 'Reprendre les marches arrière en courbe et les contrôles avant de repartir.'
      WHEN 'A' THEN 'Consolider les trajectoires et adapter l’allure à la visibilité.'
      WHEN 'A1' THEN 'Enchaîner des changements de direction en gardant le regard loin.'
      ELSE (ARRAY['Reprendre les contrôles avant de quitter un stationnement.',
        'Pratiquer les priorités de droite sur un itinéraire moins familier.',
        'Préparer une séquence de conduite plus autonome avec bilan des décisions.'])[1+(slot.ordinal%3)] END;
    evaluations:=jsonb_build_array(
      jsonb_build_object('competencyId',comp_ids[1],'level',CASE WHEN slot.ordinal%4=0 THEN 'INDEPENDENT' ELSE 'GUIDED' END,
        'context',comp_labels[1]||' : exercice répété avec des repères stables et une allure adaptée.'),
      jsonb_build_object('competencyId',comp_ids[2],'level',CASE WHEN slot.ordinal%3=0 THEN 'DISCOVERING' ELSE 'GUIDED' END,
        'context',comp_labels[2]||' : un rappel reste utile lorsque plusieurs informations arrivent en même temps.'));
    SELECT jsonb_agg(jsonb_build_object('id',c.id,'label',c.label,'version',c.version,'curriculumVersionId',c.curriculum_version_id) ORDER BY c.id)
      INTO snapshot FROM drivy.competency_definition c WHERE c.school_id=s AND c.id=ANY(comp_ids);
    draft_id:=pg_temp.seed_uuid('tomy311:report-draft:'||lesson_id);
    INSERT INTO drivy.report_draft(id,school_id,lesson_id,author_membership_id,version,base_publication_version,worked_on,observation_text,next_step,observations,created_at)
    VALUES(draft_id,s,lesson_id,pupil.instructor_id,CASE WHEN is_private THEN 1 ELSE 2 END,CASE WHEN is_private THEN 0 ELSE 1 END,
      worked,observed,following,evaluations,ends) ON CONFLICT DO NOTHING;
    IF NOT is_private THEN
      revision_id:=pg_temp.seed_uuid('tomy311:report-revision:'||lesson_id);
      INSERT INTO drivy.report_revision(id,school_id,lesson_id,author_membership_id,sequence,published_at,worked_on,observation_text,next_step,observations,competency_snapshot,operation_id)
      VALUES(revision_id,s,lesson_id,pupil.instructor_id,1,ends+interval '10 minutes',worked,observed,following,evaluations,snapshot,
        pg_temp.seed_uuid('tomy311:share-operation:'||lesson_id)) ON CONFLICT DO NOTHING;
      UPDATE drivy.lesson SET version=3,publication_version=1,current_published_revision_id=revision_id WHERE id=inserted_id AND school_id=s;
    END IF;
    INSERT INTO drivy.geo_observation(id,school_id,version,lesson_id,training_id,author_membership_id,draft_id,competency_id,
      text,origin,observed_at,event_kind,event_status,private,created_at) VALUES
      (pg_temp.seed_uuid('tomy311:observation:'||lesson_id||':1'),s,2,lesson_id,pupil.training_id,pupil.instructor_id,draft_id,comp_ids[1],
        'Prendre le temps de vérifier l’environnement avant de commencer la manœuvre.','LIVE',slot.starts+interval '8 minutes','QUALIFIED','ATTENTION',false,slot.starts+interval '8 minutes'),
      (pg_temp.seed_uuid('tomy311:observation:'||lesson_id||':2'),s,2,lesson_id,pupil.training_id,pupil.instructor_id,draft_id,comp_ids[2],
        'Le regard se porte plus loin ; la décision est prise avec une meilleure marge.','LIVE',slot.starts+interval '18 minutes','QUALIFIED','POSITIVE',false,slot.starts+interval '18 minutes'),
      (pg_temp.seed_uuid('tomy311:observation:'||lesson_id||':3'),s,2,lesson_id,pupil.training_id,pupil.instructor_id,draft_id,NULL,
        'Pause courte pour reprendre les repères et reformuler l’objectif de la prochaine séquence.','LIVE',slot.starts+interval '25 minutes','MARKER',NULL,slot.ordinal%5=0,slot.starts+interval '25 minutes')
    ON CONFLICT DO NOTHING;
  END LOOP;
  -- Compteurs seuls : aucun nom, contenu de bilan, identifiant personnel ou donnée de position dans la sortie.
  RAISE NOTICE 'Tomy School lessons: % added, % occupied or unassigned slots skipped',created,skipped;
END $lessons$;
