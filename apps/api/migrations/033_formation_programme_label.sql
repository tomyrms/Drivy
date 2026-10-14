-- Formations et tarifs (14 octobre 2026) : nom facultatif d'un parcours pédagogique.
-- Un permis peut porter plusieurs parcours (offering_key distincts). Aucune ligne existante n'est modifiée :
-- NULL signifie « parcours sans nom », jamais un nom déduit d'un tarif ou d'une clé.
ALTER TABLE drivy.offering_version ADD COLUMN label text
 CHECK(label IS NULL OR (char_length(label) BETWEEN 1 AND 120 AND label=btrim(label)));
