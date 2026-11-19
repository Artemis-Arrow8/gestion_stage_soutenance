# INC-001 — Un juré publié sur deux soutenances simultanées (exercice du chapitre 20)

> **Exercice d'incident** demandé par le dossier ALM : « une soutenance a été publiée alors qu'un juré siégeait déjà ailleurs ». Les sections *chronologie* et *issue* sont à compléter par l'équipe avec les identifiants réels (issue, branche, PR, version livrée). Ce document ne présente pas un incident de production réel.

## 1. Fiche incident

| Champ | Valeur |
|---|---|
| Impact | Un membre de jury convoqué à deux soutenances au même moment ; convocations contradictoires |
| Version concernée (scénario) | Version où le contrôle ne portait que sur le **jury** (même `jury_id`), pas sur la **personne** présente dans deux jurys |
| Reproduction | Deux jurys A et B partagent « Dr Commun » ; deux planificateurs publient en même temps A (09 h-10 h) et B (09 h 30-10 h 30) |
| Protection immédiate | Suspendre les publications ; vérifier le planning avec la requête du § 3 |
| Issue | **À créer** (étiquette `anomalie` + `sécurité`) |
| Branche corrective / PR | **À renseigner** |

## 2. Analyse

- Le contrôle existait-il seulement dans l'interface ? **Non.** Le contrôle applicatif `verifier_conflit_membres_jury` existe côté serveur, mais deux requêtes simultanées pouvaient passer le contrôle avant l'écriture. La contrainte d'exclusion PostgreSQL porte sur `jury_id` et ne voit pas une personne commune à deux jurys.
- **Protection transactionnelle en base :** toute planification, tout report et toute publication prennent le verrou transactionnel `pg_advisory_xact_lock(0x534753, 1)` avant de revérifier les règles. Les contrôles sont donc sérialisés, et le second planificateur voit la réservation du premier.

## 3. Correction et non-régression

| Élément | Emplacement |
|---|---|
| Contrôle par personne (nom du membre, tous jurys confondus) | `backend/api/services/conflicts.py::verifier_conflit_membres_jury` |
| Verrou transactionnel commun (planifier, reporter, publier) | `conflicts.planifier_soutenance`, `publication._verrou_planning` |
| Revérification de toutes les règles au moment de publier (tout ou rien) | `backend/api/services/publication.py::publier` |
| Test de non-régression (2 connexions réelles, démarrage synchronisé) | `backend/tests/test_concurrence_exg01.py::test_sta03_meme_membre_dans_deux_jurys_une_seule_reservation_validee` |
| Report validé et notifications liées à la version corrigée | `POST /api/soutenances/{id}/reporter/` : nouvelle version, anciennes convocations « remplacées » (`test_sta07_…`) |

Requête de contrôle (lecture seule), qui liste les personnes réservées deux fois :

```sql
SELECT m1.member_name, d1.id AS soutenance_1, d2.id AS soutenance_2
FROM defense d1
JOIN jury_member m1 ON m1.jury_id = d1.jury_id
JOIN jury_member m2 ON m2.member_name = m1.member_name
JOIN defense d2 ON d2.jury_id = m2.jury_id AND d2.id > d1.id
WHERE d1.status <> 'annule' AND d2.status <> 'annule'
  AND d1.slot_range && d2.slot_range;
```

## 4. Correction manuelle éventuelle des données

Une correction en base doit être :

- revue ;
- précédée d'une sauvegarde (`scripts/backup.ps1`) ;
- tracée ;
- répétable sans double effet.

On ne supprime pas une soutenance publiée : on **reporte** l'une des deux (nouvelle version et nouvelles convocations) ou on l'**annule** (convocations annulées et conservées).

## 5. Retour d'expérience (sans recherche de coupable) — à compléter par l'équipe

- Ce qui a permis de détecter le problème : …
- Ce qui a manqué : un test de concurrence sur une personne commune à deux jurys (ajouté depuis).
- Actions : …
