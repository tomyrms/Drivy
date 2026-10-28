-- La préparation GPS garde la leçon PLANNED ; son audit doit pouvoir être écrit
-- dans la même transaction que la leçon, sans emprunter l'action d'un départ réel.
-- Les droits métier et RLS de la leçon restent inchangés.
CREATE POLICY gps_preparation_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND action='LessonPreparedForGPS');
