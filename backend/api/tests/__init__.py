"""
Tests du module planification (Tâche 4).

Trois familles :

* ``test_validation_sans_db``  — validations pures (créneaux, champs,
  traduction des IntegrityError) qui ne nécessitent pas de base de données.
* ``test_conflits_db``         — règles métier EXG01/F03/F04/F05 contre une
  vraie base PostgreSQL chargée avec database/schema.sql (contraintes
  d'exclusion actives).
* ``test_api_db``              — API REST (endpoints salles, jurys,
  soutenances, planning, disponibilités) avec DRF.

Exécution : ``python manage.py test api`` (nécessite PostgreSQL accessible,
voir docs/guide-exploitation.md).
"""
