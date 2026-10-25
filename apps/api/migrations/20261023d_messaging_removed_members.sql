-- Messagerie #65 : liste des membres retirés du général, pour les administrateurs du groupe.
-- Seulement les personnes encore membres actives de l'école dont l'adhésion courante est retirée.
-- Ordre des verrous identique aux commandes du général : sources de droits, puis conversation générale.
CREATE FUNCTION drivy.messaging_general_removed_members(school uuid, after_person uuid, page_size integer)
RETURNS TABLE(person_id uuid, display_name text, photo_version integer, removed_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 IF page_size IS NULL OR page_size<1 OR page_size>101 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 PERFORM drivy.messaging_lock_rights(school,actor,NULL::uuid);
 PERFORM 1 FROM drivy.messaging_conversation WHERE school_id=school AND kind='GENERAL' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF NOT drivy.messaging_is_group_admin(school,actor) THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 RETURN QUERY
  SELECT p.id,p.display_name,
    CASE WHEN p.photo_version>0 AND drivy.person_photo_visible(p.id) THEN p.photo_version END,
    r.removed_at
  FROM drivy.messaging_general_removal r
  JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.membership_id AND m.person_id=r.person_id
  JOIN drivy.person p ON p.id=m.person_id
  WHERE r.school_id=school AND m.status='ACTIVE' AND p.status='ACTIVE'
    AND NOT drivy.messaging_general_participant(school,p.id)
    AND (after_person IS NULL OR p.id>after_person)
  ORDER BY p.id LIMIT page_size;
END $$;
REVOKE ALL ON FUNCTION drivy.messaging_general_removed_members(uuid,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_general_removed_members(uuid,uuid,integer) TO drivy_app;
