-- Additive content for the owner's explicitly designated school. Run only through the scoped operator wrapper.
CREATE TEMP TABLE seed_catalogue(formation_id uuid,kind text PRIMARY KEY,offering_id uuid,ordinal int);
DO $$
DECLARE ctx record; item record; off_id uuid; curriculum_id uuid; policy_id uuid; terms_id uuid;
BEGIN
 SELECT * INTO STRICT ctx FROM seed_context;
 FOR item IN SELECT * FROM (VALUES
  ('B',1,50,11000,'Conduite automobile'),('A',2,45,10000,'Conduite moto'),
  ('A1',3,50,9500,'Conduite moto légère'),('BE',4,60,13000,'Conduite avec remorque')
 ) AS x(category,ordinal,duration,price,label) LOOP
  SELECT o.id INTO off_id FROM drivy.offering_version o
   WHERE o.school_id=ctx.school_id AND o.category_code=item.category AND o.enabled
   AND o.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key)
   ORDER BY o.created_at,o.id LIMIT 1;
  IF off_id IS NULL THEN
   curriculum_id=pg_temp.seed_uuid('tomy311:curriculum:'||item.category)::uuid;
   policy_id=pg_temp.seed_uuid('tomy311:policy:'||item.category)::uuid;
   off_id=pg_temp.seed_uuid('tomy311:offering:'||item.category)::uuid;
   INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at)
    SELECT curriculum_id,ctx.school_id,item.category,coalesce(max(revision),0)+1,true,'Programme pédagogique de l’école',ctx.actor_id,now()
    FROM drivy.curriculum_version WHERE school_id=ctx.school_id AND category_code=item.category;
   INSERT INTO drivy.competency_definition(id,school_id,curriculum_version_id,stable_key,label,description,sort_order)
    SELECT pg_temp.seed_uuid('tomy311:competency:'||item.category||':'||n)::uuid,ctx.school_id,curriculum_id,'skill-'||n,label,description,n*10
    FROM (VALUES
     (1,'Préparation du véhicule','Contrôler le véhicule, préparer son poste et vérifier les équipements avant le départ.'),
     (2,'Observation et anticipation','Observer loin, utiliser les rétroviseurs et identifier les situations qui demandent de ralentir.'),
     (3,'Démarrage et arrêt','Démarrer progressivement et choisir un emplacement adapté pour immobiliser le véhicule.'),
     (4,'Trajectoire et position','Maintenir une trajectoire régulière et une position qui laisse une marge de sécurité.'),
     (5,'Intersections et priorités','Adapter son allure à la visibilité et contrôler chaque direction avant de s’engager.'),
     (6,'Manœuvres à faible vitesse','Préparer la manœuvre, surveiller l’environnement et corriger progressivement la trajectoire.'),
     (7,'Circulation hors localité','Adapter sa vitesse aux conditions et anticiper les changements de rythme.'),
     (8,'Conduite autonome','Préparer un itinéraire, prendre des décisions et expliquer ses choix après la séance.')
    ) AS skills(n,label,description);
   INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at,cancellation_rules)
    SELECT policy_id,ctx.school_id,item.category,coalesce(max(version),0)+1,
     'Un entretien initial permet de fixer les objectifs. Le moniteur vérifie les documents nécessaires avant toute conduite. Les séances alternent pratique et bilan, au rythme de l’élève.',
     'Prévenir l’école au moins 24 heures avant le rendez-vous. Pour une annulation tardive, contacter le secrétariat afin de convenir de la suite.',
     ARRAY[]::text[],true,'Organisation des séances',ctx.actor_id,now(),'{"cancellationHours":24,"lateAction":"CONTACT"}'::jsonb
    FROM drivy.school_policy_version WHERE school_id=ctx.school_id AND category_code=item.category;
   INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents,label)
    VALUES(off_id,ctx.school_id,'tomy311-'||lower(item.category),item.category,1,true,curriculum_id,policy_id,item.duration,item.price,NULL);
  END IF;
  INSERT INTO seed_catalogue VALUES(off_id,item.category,off_id,item.ordinal);
 END LOOP;
 terms_id=pg_temp.seed_uuid('tomy311:commercial-terms')::uuid;
 INSERT INTO drivy.commercial_terms_version(id,school_id,version,label,terms_text,valid_from,approved,approval_reason,approved_by,approved_at,created_by)
  SELECT terms_id,ctx.school_id,coalesce(max(version),0)+1,'Conditions des prestations',
   'Le prix indiqué est en francs suisses et correspond à la prestation choisie. La durée et le point de rendez-vous sont confirmés lors de la réservation. Prévenir l’école au moins 24 heures avant le rendez-vous. Pour une annulation tardive, contacter le secrétariat afin de convenir de la suite. Le règlement peut être effectué par carte, virement ou espèces auprès de l’école.',
   current_date-90,true,'Conditions des prestations complémentaires',ctx.actor_id,now(),ctx.actor_id
  FROM drivy.commercial_terms_version WHERE school_id=ctx.school_id ON CONFLICT(id) DO NOTHING;
 INSERT INTO drivy.service_product_version(id,school_id,version,product_key,label,type,category_code,duration_minutes,unit_label,unit_price_cents,valid_from,terms_version_id,enabled)
  SELECT pg_temp.seed_uuid('tomy311:product:'||product_key)::uuid,ctx.school_id,1,'tomy311-'||product_key,label,type,category,duration,unit,price,current_date-90,terms_id,true
  FROM (VALUES
   ('b-double','Conduite B · séance approfondie','INDIVIDUAL_LESSON','B',90,'séance',19000),
   ('b-exam','Accompagnement à l’examen B','EXAM_SUPPORT','B',120,'accompagnement',24000),
   ('a-manoeuvres','Moto · maîtrise à basse vitesse','INDIVIDUAL_LESSON','A',90,'séance',18000),
   ('a1-lesson','Conduite A1','INDIVIDUAL_LESSON','A1',50,'leçon',9500),
   ('be-lesson','Conduite BE','INDIVIDUAL_LESSON','BE',60,'leçon',13000),
   ('be-exam','Accompagnement à l’examen BE','EXAM_SUPPORT','BE',120,'accompagnement',26000),
   ('awareness','Sensibilisation · cycle complet','COLLECTIVE_COURSE','B',480,'cycle',24000),
   ('first-aid','Premiers secours','COLLECTIVE_COURSE',NULL,600,'cours',15000),
   ('moto','Atelier moto · anticipation et trajectoires','COLLECTIVE_COURSE','A',120,'atelier',12000),
   ('theory','Théorie · priorités et intersections','COLLECTIVE_COURSE','B',120,'atelier',4500),
   ('confidence','Reprise de conduite','INDIVIDUAL_LESSON','B',60,'séance',12000),
   ('assessment','Entretien et bilan de départ','EXTERNAL_SERVICE',NULL,30,'entretien',3500)
  ) AS products(product_key,label,type,category,duration,unit,price) ON CONFLICT(id) DO NOTHING;
END $$;
