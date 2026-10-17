-- Motifs de retrait et de contre-écriture : réservés au personnel (audit agent 07, essaim du 17 octobre 2026).
-- La politique 011 laissait l'élève lire toute la table : le motif saisi par le moniteur au retrait (AP57) et le motif
-- administratif d'une correction d'issue (AP50) lui étaient donc lisibles directement en base. Le bureau et le moniteur
-- affecté restent les seuls lecteurs. Aucune route de l'API ne lit cette table ; la politique seule change.
-- Lecteurs après migration : auteur actuel du bilan, moniteur actif affecté à la formation, administrateur actif de l'école.
-- DROP POLICY IF EXISTS et CREATE POLICY rendent la migration rejouable ; le contrôle de droit reste dans la base.

DROP POLICY IF EXISTS withdrawal_read ON drivy.report_publication_withdrawal;
CREATE POLICY withdrawal_read ON drivy.report_publication_withdrawal FOR SELECT TO drivy_app USING(
 drivy.report_lesson_author(lesson_id)
 OR EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.school_id=report_publication_withdrawal.school_id AND l.id=report_publication_withdrawal.lesson_id
  AND drivy.report_training_instructor(l.training_id))
 OR drivy.is_current_school_admin(school_id));
