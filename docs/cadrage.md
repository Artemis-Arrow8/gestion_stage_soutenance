# Dossier de cadrage — SGSUS

**Projet :** Système de gestion des stages et soutenances universitaires (SGSUS)
**Établissement (cas d'étude) :** Institut privé africain de technologies et de management (ITMA)
**Auteure principale (lot 1) :** Kadiatou Hélène GUINDO
**Équipe (Groupe 4) :** Kadiatou Hélène GUINDO, Mariam DIARRA, Kadidia DIARRA, Nahawa SANOGO
**Version initiale :** 23 octobre 2026 — **mise à jour :** 19 novembre 2026

---

## 1. Contexte et justification

À l'ITMA, la gestion des stages et des soutenances repose sur :

- des documents papier ;
- des échanges de courriels non centralisés ;
- des emplois du temps tenus à la main.

Cette organisation crée un risque élevé de conflits : une salle réservée deux fois, ou un membre de jury sollicité pour deux soutenances simultanées.

SGSUS dématérialise le processus, du dépôt du dossier de stage jusqu'à l'archivage des procès-verbaux de soutenance. Deux processus liés mais distincts sont couverts : le **suivi du stage** et la **préparation de la soutenance**. Un dossier peut être incomplet ou non recevable même si un créneau est libre : la recevabilité est donc vérifiée avant toute publication.

## 2. Objectifs

- **Dématérialisation :** centraliser les dossiers, les rapports et leurs versions successives (V1, V2…).
- **Traçabilité :** chaque étape d'un dossier est historisée (acteur, date, motif, version examinée).
- **Zéro conflit de planning (EXG01) :** impossibilité, garantie par la base de données, de réserver deux fois une salle ou un membre de jury.
- **Rigueur des résultats :** calcul exact (décimal) côté serveur, procès-verbaux figés, rectifications motivées et versionnées.

## 3. Parties prenantes et rôles

| Rôle (dossier ALM) | Rôle dans l'application | Responsabilité |
|---|---|---|
| Étudiant | `student` | Constitue et soumet son dossier, consulte ses décisions et ses convocations |
| Encadreur | `supervisor` | Suit uniquement les dossiers affectés et donne l'avis pédagogique |
| Responsable des stages | `responsible` | Autorise la soutenance, refuse ou rouvre un dossier, rectifie un résultat |
| Planificateur | `responsible` (cumul, voir A8) | Prépare jurys et créneaux, publie le planning ; ne modifie pas les notes approuvées |
| Jury | `jury` | Consulte ses soutenances et ses dossiers, saisit les notes ; le président approuve |
| Scolarité / administration | `admin` | Comptes, campagnes, archivage ; pas d'accès automatique aux rapports confidentiels |

La direction porte généralement la décision d'acquisition ; le service de scolarité et le responsable des stages en sont les utilisateurs clés.

## 4. Entretien utilisateur — À RÉALISER ET COMPLÉTER PAR L'ÉQUIPE

> Le dossier exige un entretien avec un utilisateur représentatif (sinon un entretien simulé avec l'enseignant, en signalant cette limite). **Aucun entretien n'est encore consigné ici : ne rien présenter comme validé tant que cette section est vide.**

| Rubrique | À renseigner |
|---|---|
| Date | … |
| Rôle interrogé (sans données personnelles) | … (ex. responsable des stages, scolarité) |
| Type | Réel / simulé avec l'enseignant (limite à signaler) |
| Opération observée | … |
| Constats | … |
| Hypothèses (non validées) | Voir le registre A1 à A9 de `cahier-des-charges.md` |
| Décisions prises | … |

Questions à poser (chapitre 1) :

- Quelles pièces rendent un stage recevable, et qui les valide ?
- Qui peut consulter un rapport confidentiel déposé par une entreprise ?
- Quelles sont les règles de composition du jury et d'éligibilité à la soutenance ?
- Comment sont connues les indisponibilités des enseignants et des salles ?
- Qui publie le planning, et qui autorise une modification après publication ?
- Comment sont approuvés les résultats et corrigées les erreurs de saisie ?

## 5. Comparaison des solutions

| Critère | Pratique actuelle (papier, courriel, tableur) | Solution générique existante (ex. ENT ou LMS avec module de devoirs) — **à préciser par l'équipe** | SGSUS |
|---|---|---|---|
| Parcours réel du dossier | Dispersé, relances manuelles | Dépôt de fichiers, peu de circuit de validation | Circuit complet, étapes tracées |
| Conflits de planning | Détectés à la main | Rarement gérés | Interdits par la base (EXG01) |
| Mobile | Non | Variable | Web et Android, à une main, 360 px, mode hors ligne |
| Exports | Tableur | Variable | Export JSON/CSV documenté |
| Reprise des données | Ressaisie | Variable | Import CSV avec aperçu et sans doublon |
| Support | Informel | Éditeur | À définir (projet pédagogique) |

## 6. Budget d'exploitation — montants À COMPLÉTER AVEC DES OFFRES DATÉES

| Poste | Choix actuel | Coût | Source / date de l'offre |
|---|---|---|---|
| Serveur (API) | Render Web Service (instance payante pendant la démonstration, puis gratuite) | … | Page de tarifs Render, à dater |
| Base de données | Render PostgreSQL (offre gratuite, durée limitée) | … | À dater ; expiration à surveiller |
| Site Web | Render Static Site | … | À dater |
| Sauvegardes | Dumps manuels (`scripts/backup.ps1`) | Temps humain | — |
| Messages | Courriel simulé (aucun coût) ; SMTP réel à chiffrer | … | — |
| Assistance | Équipe projet | Temps humain | — |
| Formation | Démonstration et guide d'exploitation | Temps humain | — |

Aucun engagement de dépense ne doit être pris sans offre datée.

## 7. Périmètre de la solution

- **Backend** : API REST Django et Django REST Framework, PostgreSQL 17 (contraintes d'exclusion `tstzrange` et `btree_gist`).
- **Frontend** : application Flutter multiplateforme (Web, Android, version PC hors ligne), utilisable à partir de 360 px de large.
- **Sécurité et gouvernance** :
  - droits contrôlés côté serveur, pour chaque objet et chaque fichier ;
  - jetons JWT ;
  - journaux structurés et journal d'accès aux rapports.

## 8. Organisation (ALM)

Le projet est réparti en lots. La conduite technique et documentaire du lot 1 (cadrage, architecture, base de données, socle backend et frontend) revient à Kadiatou Hélène GUINDO, en collaboration avec l'équipe du Groupe 4. Le volet DevOps (Docker, CI, sauvegardes) est documenté par Mariam DIARRA dans `rapport_avancement_devops.md`.

Les responsabilités de référent (métier, conception, qualité, intégration) et leur rotation sont à consigner par l'équipe, conformément au chapitre 9 du dossier.
