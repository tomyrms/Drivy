-- Essai terrain du 29 septembre 2026 : tous les textes du bilan sont facultatifs, y compris pour une publication explicite.
-- L'auto-partage conserve sa règle : un brouillon entièrement vide reste sauvegardé sans créer une révision inutile.
ALTER TABLE drivy.report_revision DROP CONSTRAINT report_revision_content;
ALTER TABLE drivy.report_revision ADD CONSTRAINT report_revision_content CHECK(
 char_length(worked_on)<=4000 AND char_length(observation_text)<=4000 AND char_length(next_step)<=4000);
