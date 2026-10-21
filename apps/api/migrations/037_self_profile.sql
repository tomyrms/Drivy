-- Profil personnel (21 octobre 2026, issue #64) : chaque personne modifie son propre nom affiché depuis l'app, quel que soit
-- son rôle (moniteur, administrateur, élève). Seule la ligne de la personne connectée est concernée, et seulement quand la
-- route du profil personnel pose app.self_profile dans sa transaction. Rôles, adhésions et dossiers d'élève ne changent pas.
-- Les droits de colonne existent déjà (display_name, version : migrations 002 et 031).
CREATE POLICY person_self_profile_update ON drivy.person FOR UPDATE TO drivy_app
  USING(id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE'
    AND current_setting('app.self_profile',true)='true')
  WITH CHECK(id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE'
    AND current_setting('app.self_profile',true)='true');
