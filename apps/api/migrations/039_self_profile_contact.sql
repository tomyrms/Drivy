-- Profil personnel, suite de 038 (21 octobre 2026, issue #64) : e-mail de contact, date de naissance et adresse postale du compte.
-- L'e-mail de contact n'est pas l'adresse de connexion : celle-ci reste chez le fournisseur d'identité et n'est jamais modifiée ici.
-- Ces champs appartiennent au compte Drivy ; le dossier d'élève d'une école garde les siens et n'est ni copié ni modifié.
ALTER TABLE drivy.person ADD COLUMN contact_email text CHECK(contact_email IS NULL OR char_length(contact_email) BETWEEN 3 AND 254);
ALTER TABLE drivy.person ADD COLUMN birth_date date CHECK(birth_date IS NULL OR birth_date>=DATE '1900-01-01');
ALTER TABLE drivy.person ADD COLUMN postal_address jsonb CHECK(postal_address IS NULL OR (jsonb_typeof(postal_address)='object'
  AND postal_address ?& ARRAY['line1','postalCode','locality','countryCode'] AND octet_length(postal_address::text)<=2000));
GRANT UPDATE(contact_email,birth_date,postal_address) ON drivy.person TO drivy_app;
