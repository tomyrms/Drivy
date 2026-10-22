-- Purge unique des tracés recalés calculés avant la découpe des lots (issue #91, 22 octobre 2026).
-- Le format ne change pas (algorithme 2) : l'app déjà installée continue de les afficher.
-- Ces lignes sont des dérivés recalculables ; les mesures (capture_chunk) ne sont pas touchées.
DELETE FROM drivy.capture_matched_route WHERE status IN ('READY','EMPTY','FAILED');
