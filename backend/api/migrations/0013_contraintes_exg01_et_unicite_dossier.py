"""
Contraintes de base de données du socle (tables historiques).

1. EXG01 : les contraintes d'exclusion de la table `defense` ne portent plus
   que sur les soutenances ACTIVES (statut différent de « annule ») : une
   soutenance annulée libère sa salle et son jury (chapitre 5 : « une
   réservation contient … un état actif ou annulé »). La nouvelle contrainte
   est moins restrictive que l'ancienne : elle ne peut pas échouer sur des
   données existantes.
2. F01 : un étudiant n'a qu'un dossier par campagne (index unique). L'index
   n'est créé que si la base ne contient AUCUN doublon : sur une base réelle,
   la migration ne doit jamais échouer ni supprimer de données ; un doublon
   éventuel est alors à traiter manuellement (voir docs/guide-exploitation.md)
   et le service d'import continue de refuser les doublons.

Les instructions sont gardées (« si la table existe ») : en test, les tables
historiques sont recréées ensuite par database/schema.sql, qui contient les
mêmes contraintes.
"""
from django.db import migrations

CONTRAINTES_EXG01 = """
DO $$
BEGIN
    IF to_regclass('public.defense') IS NOT NULL THEN
        ALTER TABLE defense DROP CONSTRAINT IF EXISTS prevent_room_double_booking;
        ALTER TABLE defense ADD CONSTRAINT prevent_room_double_booking
            EXCLUDE USING gist (room_name WITH =, slot_range WITH &&)
            WHERE (status <> 'annule');
        ALTER TABLE defense DROP CONSTRAINT IF EXISTS prevent_jury_double_booking;
        ALTER TABLE defense ADD CONSTRAINT prevent_jury_double_booking
            EXCLUDE USING gist (jury_id WITH =, slot_range WITH &&)
            WHERE (status <> 'annule');
    END IF;
END $$;
"""

# Retour arrière : contraintes d'origine, sans condition.
CONTRAINTES_EXG01_INITIALES = """
DO $$
BEGIN
    IF to_regclass('public.defense') IS NOT NULL THEN
        ALTER TABLE defense DROP CONSTRAINT IF EXISTS prevent_room_double_booking;
        ALTER TABLE defense ADD CONSTRAINT prevent_room_double_booking
            EXCLUDE USING gist (room_name WITH =, slot_range WITH &&);
        ALTER TABLE defense DROP CONSTRAINT IF EXISTS prevent_jury_double_booking;
        ALTER TABLE defense ADD CONSTRAINT prevent_jury_double_booking
            EXCLUDE USING gist (jury_id WITH =, slot_range WITH &&);
    END IF;
END $$;
"""

UNICITE_DOSSIER = """
DO $$
BEGIN
    IF to_regclass('public.internship_folder') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM internship_folder
           GROUP BY student_id, campaign_id HAVING COUNT(*) > 1
       ) THEN
        CREATE UNIQUE INDEX IF NOT EXISTS dossier_unique_par_campagne
            ON internship_folder (student_id, campaign_id);
    END IF;
END $$;
"""


class Migration(migrations.Migration):
    """Contraintes EXG01 conditionnelles et unicité dossier/campagne."""

    dependencies = [
        ('api', '0012_socle_alm'),
    ]

    operations = [
        migrations.RunSQL(CONTRAINTES_EXG01, reverse_sql=CONTRAINTES_EXG01_INITIALES),
        migrations.RunSQL(
            UNICITE_DOSSIER,
            reverse_sql='DROP INDEX IF EXISTS dossier_unique_par_campagne;',
        ),
    ]
