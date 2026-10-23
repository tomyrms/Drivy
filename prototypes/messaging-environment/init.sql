-- Marqueur de laboratoire, pas une preuve d'absence de données réelles.
CREATE SCHEMA synthetic_environment;
CREATE TABLE synthetic_environment.marker (
    label text PRIMARY KEY CHECK (label = 'drivy-messaging-fixtures-only-v1')
);
INSERT INTO synthetic_environment.marker VALUES ('drivy-messaging-fixtures-only-v1');
