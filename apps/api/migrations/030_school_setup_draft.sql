-- Le brouillon accompagne SchoolSetup sans devenir une configuration active.
-- NULL signifie absence de saisie : GET projette les valeurs existantes sans écrire.
ALTER TABLE drivy.school_setup ADD COLUMN draft_version integer NOT NULL DEFAULT 1 CHECK(draft_version>0);
ALTER TABLE drivy.school_setup ADD COLUMN draft_step text NOT NULL DEFAULT 'IDENTITY'
 CHECK(draft_step IN('IDENTITY','PRIVACY','PROFILE','FORMATIONS','PRICING','REVIEW'));
ALTER TABLE drivy.school_setup ADD COLUMN draft_content jsonb
 CHECK(draft_content IS NULL OR (jsonb_typeof(draft_content)='object' AND octet_length(draft_content::text)<=1048576));
ALTER TABLE drivy.school_setup ADD COLUMN draft_updated_at timestamptz;
ALTER TABLE drivy.school_setup ADD COLUMN draft_updated_by uuid;
ALTER TABLE drivy.school_setup ADD COLUMN draft_applied_at timestamptz;
ALTER TABLE drivy.school_setup ADD FOREIGN KEY(school_id,draft_updated_by) REFERENCES drivy.membership(school_id,id);
GRANT UPDATE(draft_version,draft_step,draft_content,draft_updated_at,draft_updated_by,draft_applied_at) ON drivy.school_setup TO drivy_app;
-- Les politiques RLS existantes limitent ces colonnes aux ADMIN courants de la même école.
