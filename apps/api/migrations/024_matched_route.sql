-- Couche recalée sur la route d'un trajet privé. C'est un dérivé des mesures, jamais une mesure :
-- capture_chunk reste la seule source, et cette ligne disparaît dès que la source change.
-- Une ligne par trajet ; son contenu (géométrie recalée) est chiffré comme les lots.
CREATE TABLE drivy.capture_matched_route (
 capture_id uuid PRIMARY KEY,school_id uuid NOT NULL,
 reconstruction_version integer NOT NULL CHECK(reconstruction_version>0),algorithm_version integer NOT NULL CHECK(algorithm_version>0),
 status text NOT NULL CHECK(status IN('PROCESSING','READY','EMPTY','FAILED')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 lease_id uuid,lease_until timestamptz,retry_after timestamptz,
 failure_code text CHECK(failure_code IS NULL OR failure_code ~ '^[A-Z_]{1,40}$'),
 provider text CHECK(provider IS NULL OR provider IN('mapbox','osrm')),
 encrypted_route bytea,key_id text,span_count integer NOT NULL DEFAULT 0 CHECK(span_count>=0),
 matched_at timestamptz,updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(school_id,capture_id) REFERENCES drivy.capture_session(school_id,id) ON DELETE CASCADE,
 CHECK((status='READY')=(encrypted_route IS NOT NULL AND key_id IS NOT NULL)),
 CHECK(encrypted_route IS NULL OR octet_length(encrypted_route) BETWEEN 29 AND 4194304),
 CHECK((status='PROCESSING')=(lease_id IS NOT NULL AND lease_until IS NOT NULL))
);
ALTER TABLE drivy.capture_matched_route ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.capture_matched_route FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
 EXECUTE format('CREATE POLICY matched_route_owner ON drivy.capture_matched_route FOR ALL TO %I USING(true) WITH CHECK(true)',current_user);
END $$;
-- Lecture : exactement les comptes qui lisent le trajet lui-même (la sous-requête passe par la RLS de capture_session).
CREATE POLICY matched_route_read ON drivy.capture_matched_route FOR SELECT TO drivy_app
 USING(EXISTS(SELECT 1 FROM drivy.capture_session c WHERE c.school_id=capture_matched_route.school_id AND c.id=capture_id));
GRANT SELECT ON drivy.capture_matched_route TO drivy_app;

-- Réserve le calcul pour un seul appelant à la fois. Rend le bail, ou NULL s'il n'y a rien à calculer :
-- résultat déjà là, calcul en cours, nouvel essai pas encore dû, ou trajet qui n'est plus dans l'état lu.
-- L'accès du compte au trajet est vérifié par la route avant cet appel ; la fonction n'expose aucune donnée.
CREATE FUNCTION drivy.claim_matched_route(target uuid,expected_reconstruction integer,algorithm integer,lease_seconds integer) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 DECLARE c drivy.capture_session%ROWTYPE; r drivy.capture_matched_route%ROWTYPE; lease uuid:=gen_random_uuid();
 BEGIN
  IF lease_seconds NOT BETWEEN 10 AND 900 OR algorithm<1 THEN RETURN NULL; END IF;
  -- Deux lectures simultanées d'un même trajet : une seule réserve le calcul, l'autre attend puis voit le bail.
  PERFORM pg_advisory_xact_lock(hashtextextended('drivy.matched_route:'||target::text,0));
  SELECT * INTO c FROM drivy.capture_session WHERE id=target FOR SHARE;
  IF NOT FOUND OR c.publication_state<>'PRIVATE' OR c.finalized_at IS NULL OR c.sync_state NOT IN('SYNCED','PARTIAL')
     OR c.reconstruction_version<>expected_reconstruction THEN RETURN NULL; END IF;
  SELECT * INTO r FROM drivy.capture_matched_route WHERE capture_id=target FOR UPDATE;
  IF NOT FOUND THEN
   INSERT INTO drivy.capture_matched_route(capture_id,school_id,reconstruction_version,algorithm_version,status,attempts,lease_id,lease_until)
    VALUES(target,c.school_id,c.reconstruction_version,algorithm,'PROCESSING',1,lease,now()+make_interval(secs=>lease_seconds));
   RETURN lease;
  END IF;
  IF r.reconstruction_version=c.reconstruction_version AND r.algorithm_version=algorithm THEN
   IF r.status IN('READY','EMPTY') THEN RETURN NULL; END IF;
   IF r.status='PROCESSING' AND r.lease_until>now() THEN RETURN NULL; END IF;
   IF r.status='FAILED' AND r.retry_after IS NOT NULL AND r.retry_after>now() THEN RETURN NULL; END IF;
   UPDATE drivy.capture_matched_route SET status='PROCESSING',attempts=r.attempts+1,lease_id=lease,lease_until=now()+make_interval(secs=>lease_seconds),
    failure_code=NULL,retry_after=NULL,updated_at=now() WHERE capture_id=target;
  ELSE
   -- La source ou l'algorithme a changé : l'ancien résultat ne vaut plus rien.
   UPDATE drivy.capture_matched_route SET reconstruction_version=c.reconstruction_version,algorithm_version=algorithm,status='PROCESSING',attempts=1,
    lease_id=lease,lease_until=now()+make_interval(secs=>lease_seconds),encrypted_route=NULL,key_id=NULL,span_count=0,matched_at=NULL,provider=NULL,
    failure_code=NULL,retry_after=NULL,updated_at=now() WHERE capture_id=target;
  END IF;
  RETURN lease;
 END $$;

-- Dépose le résultat du calcul réservé. Sans le bail courant (calcul repris par un autre, trajet modifié), rien n'est écrit.
CREATE FUNCTION drivy.complete_matched_route(target uuid,lease uuid,outcome text,route bytea,key text,spans integer,engine text,failure text,retry_seconds integer) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF outcome NOT IN('READY','EMPTY','FAILED') OR (outcome='READY' AND (route IS NULL OR key IS NULL)) THEN RETURN false; END IF;
  UPDATE drivy.capture_matched_route SET status=outcome,
    encrypted_route=CASE WHEN outcome='READY' THEN route END,key_id=CASE WHEN outcome='READY' THEN key END,
    span_count=CASE WHEN outcome='READY' THEN greatest(0,coalesce(spans,0)) ELSE 0 END,provider=engine,
    failure_code=CASE WHEN outcome='FAILED' THEN failure END,
    retry_after=CASE WHEN outcome='FAILED' THEN now()+make_interval(secs=>greatest(30,least(604800,coalesce(retry_seconds,300)))) END,
    matched_at=CASE WHEN outcome<>'FAILED' THEN now() END,lease_id=NULL,lease_until=NULL,updated_at=now()
   WHERE capture_id=target AND status='PROCESSING' AND lease_id=lease;
  RETURN FOUND;
 END $$;
REVOKE ALL ON FUNCTION drivy.claim_matched_route(uuid,integer,integer,integer),drivy.complete_matched_route(uuid,uuid,text,bytea,text,integer,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.claim_matched_route(uuid,integer,integer,integer),drivy.complete_matched_route(uuid,uuid,text,bytea,text,integer,text,text,integer) TO drivy_app;

-- Une borne resserrée détruit des mesures ; un retrait ou une suppression retire le trajet.
-- Le dérivé part avec sa source, dans la même transaction.
CREATE FUNCTION drivy.capture_matched_route_purge() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.reconstruction_version<>OLD.reconstruction_version OR NEW.publication_state<>'PRIVATE' THEN
   DELETE FROM drivy.capture_matched_route WHERE capture_id=NEW.id;
  END IF;
  RETURN NULL;
 END $$;
CREATE TRIGGER capture_matched_route_purge AFTER UPDATE ON drivy.capture_session FOR EACH ROW EXECUTE FUNCTION drivy.capture_matched_route_purge();
