-- Bascule vers le recalage hébergé : seuls les dérivés sont supprimés.
-- Les anciens PROCESSING ne portent pas leur moteur : ils doivent tous perdre leur bail.
-- Aucun changement de capture_chunk, capture_session ou des notices déjà adoptées.
DELETE FROM drivy.capture_matched_route WHERE provider='mapbox' OR status='PROCESSING';

-- Un ancien binaire ne doit plus réserver un calcul sans identifier son moteur.
DROP FUNCTION drivy.claim_matched_route(uuid,integer,integer,integer);
CREATE FUNCTION drivy.claim_matched_route(target uuid,expected_reconstruction integer,algorithm integer,lease_seconds integer,engine text) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 DECLARE c drivy.capture_session%ROWTYPE; r drivy.capture_matched_route%ROWTYPE; lease uuid:=gen_random_uuid();
 BEGIN
  IF lease_seconds IS NULL OR lease_seconds NOT BETWEEN 10 AND 900 OR algorithm IS NULL OR algorithm<2
     OR engine IS DISTINCT FROM 'osrm' THEN RETURN NULL; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('drivy.matched_route:'||target::text,0));
  SELECT * INTO c FROM drivy.capture_session WHERE id=target FOR SHARE;
  IF NOT FOUND OR c.publication_state<>'PRIVATE' OR c.finalized_at IS NULL OR c.sync_state NOT IN('SYNCED','PARTIAL')
     OR c.reconstruction_version IS DISTINCT FROM expected_reconstruction THEN RETURN NULL; END IF;
  SELECT * INTO r FROM drivy.capture_matched_route WHERE capture_id=target FOR UPDATE;
  IF NOT FOUND THEN
   INSERT INTO drivy.capture_matched_route(capture_id,school_id,reconstruction_version,algorithm_version,status,attempts,lease_id,lease_until,provider)
    VALUES(target,c.school_id,c.reconstruction_version,algorithm,'PROCESSING',1,lease,now()+make_interval(secs=>lease_seconds),engine);
   RETURN lease;
  END IF;
  IF r.reconstruction_version=c.reconstruction_version AND r.algorithm_version=algorithm AND r.provider=engine THEN
   IF r.status IN('READY','EMPTY') THEN RETURN NULL; END IF;
   IF r.status='PROCESSING' AND r.lease_until>now() THEN RETURN NULL; END IF;
   IF r.status='FAILED' AND r.retry_after IS NOT NULL AND r.retry_after>now() THEN RETURN NULL; END IF;
   UPDATE drivy.capture_matched_route SET status='PROCESSING',attempts=r.attempts+1,lease_id=lease,lease_until=now()+make_interval(secs=>lease_seconds),
    failure_code=NULL,retry_after=NULL,updated_at=now() WHERE capture_id=target;
  ELSE
   -- Une autre source, version ou provenance invalide aussi un résultat vide et un bail non expiré.
   UPDATE drivy.capture_matched_route SET reconstruction_version=c.reconstruction_version,algorithm_version=algorithm,status='PROCESSING',attempts=1,
    lease_id=lease,lease_until=now()+make_interval(secs=>lease_seconds),encrypted_route=NULL,key_id=NULL,span_count=0,matched_at=NULL,provider=engine,
    failure_code=NULL,retry_after=NULL,updated_at=now() WHERE capture_id=target;
  END IF;
  RETURN lease;
 END $$;
REVOKE ALL ON FUNCTION drivy.claim_matched_route(uuid,integer,integer,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.claim_matched_route(uuid,integer,integer,integer,text) TO drivy_app;

-- Le moteur est fixé à la réservation, pas accepté à la livraison du résultat.
-- Un calcul d'avant la purge, même terminé après celle-ci, ne retrouve jamais son bail.
CREATE OR REPLACE FUNCTION drivy.complete_matched_route(target uuid,lease uuid,outcome text,route bytea,key text,spans integer,engine text,failure text,retry_seconds integer) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF engine IS DISTINCT FROM 'osrm' OR outcome IS NULL OR outcome NOT IN('READY','EMPTY','FAILED')
     OR (outcome='READY' AND (route IS NULL OR key IS NULL)) THEN RETURN false; END IF;
  UPDATE drivy.capture_matched_route SET status=outcome,
    encrypted_route=CASE WHEN outcome='READY' THEN route END,key_id=CASE WHEN outcome='READY' THEN key END,
    span_count=CASE WHEN outcome='READY' THEN greatest(0,coalesce(spans,0)) ELSE 0 END,
    failure_code=CASE WHEN outcome='FAILED' THEN failure END,
    retry_after=CASE WHEN outcome='FAILED' THEN now()+make_interval(secs=>greatest(30,least(604800,coalesce(retry_seconds,300)))) END,
    matched_at=CASE WHEN outcome<>'FAILED' THEN now() END,lease_id=NULL,lease_until=NULL,updated_at=now()
   WHERE capture_id=target AND status='PROCESSING' AND lease_id=lease AND provider=engine AND algorithm_version>=2;
  RETURN FOUND;
 END $$;
REVOKE ALL ON FUNCTION drivy.complete_matched_route(uuid,uuid,text,bytea,text,integer,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.complete_matched_route(uuid,uuid,text,bytea,text,integer,text,text,integer) TO drivy_app;
