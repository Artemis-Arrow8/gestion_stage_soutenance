# Recette de SGSUS (chapitre 5 du dossier ALM)

La recette vérifie le produit par rapport aux besoins acceptés. Pour chaque cas, on trouve ci-dessous les données de départ, l'acteur, les étapes, le résultat attendu, le **résultat observé** et la version. Chaque cas est aussi automatisé : le test cité s'exécute sur PostgreSQL (contraintes, transactions et connexions réelles).

## Exécution consignée

| Champ | Valeur |
|---|---|
| Date | 19/11/2026 |
| Version | commit `4f1dadc` + modifications du 19/11/2026 **(remplacer par le SHA du commit livré)** |
| Commande | `bash scripts/ci.sh` (ou `cd backend && python -m pytest -k "sta or f01_ or f02_ or f03_ or f04_ or f05_"`) |
| Résultat global observé | 37 tests de recette réussis (sélection) ; suite complète : 242 réussis, couverture 95 % |
| Exécutant | **À compléter : une personne AUTRE que l'auteur doit rejouer la recette** (chapitre 13) et signer ce tableau |

Un refus doit laisser les données dans un état cohérent : chaque test de refus vérifie aussi l'**absence d'écriture partielle** (nombre de lignes, statut inchangé).

## Cas de recette

### Cas STA01 à STA07

| Cas | Données de départ | Acteur | Étapes | Résultat attendu | Résultat observé (19/11/2026) | Test automatisé |
|---|---|---|---|---|---|---|
| **STA01** | Une soutenance 09 h-10 h avec un jury J | Responsable | Planifier 09 h 30-10 h 30 avec un juré de J (même jury, ou membre commun à un autre jury) | Refus avec le conflit identifié | Refus 409 `EXG01` citant la soutenance en conflit ; une seule soutenance en base | `test_conflits_exg01.py::test_sta01_meme_jury_chevauchement_refuse_sans_ecriture`, `test_sta01_meme_salle_…`, `test_membre_commun_a_deux_jurys_refuse` |
| **STA02** | Une soutenance 09 h-10 h | Responsable | Planifier 10 h-11 h (jointif), avec une marge de 0 puis de 15 min | Accepté avec une marge nulle ; refusé si une marge est configurée | Marge 0 : accepté. Marge 15 min : refus 409 `EXG01`, puis 10 h 15 accepté | `test_sta02_creneaux_jointifs_acceptes_avec_marge_zero`, `test_sta02_creneaux_jointifs_refuses_si_marge_configuree` |
| **STA03** | Deux dossiers recevables, même salle (ou même jury, ou même membre) | Deux planificateurs simultanés | Deux threads, deux connexions, démarrage synchronisé | Une seule réservation validée | 1 « ok », 1 « conflit » ; 1 seule ligne en base ; le filet SQL tranche même sans contrôle applicatif | `test_concurrence_exg01.py::test_sta03_meme_salle_…`, `…_meme_jury_…`, `…_meme_membre_dans_deux_jurys_…`, `test_filet_de_securite_base_…` |
| **STA04** | Rapport déposé par l'étudiant A | Étudiant B | `GET /api/documents/download/<id>/` avec l'URL exacte | Refus | 403 ; la tentative est inscrite au journal d'accès (refusée) | `test_socle_alm.py::test_sta04_un_etudiant_n_ouvre_pas_le_rapport_d_un_autre` |
| **STA05** | Avis favorable sur V1, dossier recevable | Étudiant, puis encadreur | Déposer V2 | L'avis reste attaché à V1 ; la recevabilité est réexaminée | Dossier repassé à « soumis » ; avis toujours lié à V1 ; planification refusée ; avis sur V1 refusé (409 `STA05`) ; nouvel avis sur V2 et autorisation, puis planification acceptée | `test_conflits_exg01.py::test_sta05_avis_sur_v1_ne_couvre_pas_une_v2` |
| **STA06** | Évaluation 12/13 approuvée | Responsable | `PATCH` puis `DELETE` direct sur l'évaluation | Refus hors procédure de rectification | 409 `STA06` dans les deux cas ; note inchangée (12,00) | `test_socle_alm.py::test_sta06_note_approuvee_non_modifiable_par_appel_direct` |
| **STA07** | Planning publié (version 1) | Responsable | Reporter une soutenance (nouveau créneau et motif) ; tenter un `PATCH` direct | Nouvelle version ; anciennes convocations identifiables comme remplacées | Version 2 publiée ; convocations v1 « remplacées », avec un lien vers v2 ; l'étudiant voit v1 (remplacée) et v2 (active) ; `PATCH` direct refusé (409 `STA07`) ; suppression refusée (409) | `test_sta07_report_cree_une_version_et_remplace_les_convocations`, `test_sta07_modification_directe_…` |

### Cas STA08 à STA13

| Cas | Données de départ | Acteur | Étapes | Résultat attendu | Résultat observé (19/11/2026) | Test automatisé |
|---|---|---|---|---|---|---|
| **STA08** | Rapport déclaré confidentiel, embargo terminé (01/01/2026) | Responsable sans habilitation | Télécharger ; puis accorder une habilitation, télécharger, révoquer, retélécharger | Refus, aucune publication automatique | Standard : 200. Confidentiel : 403. Avec habilitation : 200. Après révocation : 403 par la même URL. L'étudiant garde l'accès. Journal : autorisé, refusé, autorisé, refusé | `test_sta08_rapport_confidentiel_refuse_meme_apres_embargo` |
| **STA09** | Membre indisponible chaque vendredi de 9 h à 12 h (fuseau Africa/Lagos, UTC+1) en juillet | Responsable | Planifier 10 h-11 h UTC, puis 11 h-12 h UTC, puis ajouter l'exception du 10/07 | Les créneaux tiennent compte de l'exception et du fuseau | 10 h-11 h UTC refusé (409 `F04`) ; 11 h-12 h UTC accepté (12 h à Lagos) ; vendredi 17/07 refusé ; après l'exception, le 10/07 est accepté | `test_sta09_indisponibilite_recurrente_avec_exception_et_fuseau` |
| **STA10** | Grille fictive 40/60 | Responsable | Saisir 14 et 16, puis retirer la note d'oral, puis approuver | 15,2 ; approbation bloquée si une note manque | Moyenne 15.20 ; sans oral : moyenne absente (pas de zéro) ; approbation refusée (409 `STA10`) ; aucun procès-verbal créé | `test_sta10_ponderation_40_60_et_note_absente` |
| **STA11** | Dossier brouillon ; dossier validé avec seulement un avis « tuteur » | Responsable | `PATCH status=recevable` ; `POST /autoriser/` | Refus côté serveur, état inchangé | `PATCH` sans effet (statut en lecture seule) ; 409 `STA11` ; 409 `F03` sans avis de l'encadreur ; aucun historique créé | `test_sta11_statut_non_modifiable_et_etape_sautee_refusee`, `test_sta11_avis_du_tuteur_seul_…` |
| **STA12** | Évaluation approuvée (12/13, procès-verbal v1) | Responsable | Rectifier sans motif, puis avec motif (14/13) | Nouvelle version motivée et approuvée ; historique conservé | Sans motif : 400. Avec motif : procès-verbal v2 « approuvé » (13,40, motif conservé) ; v1 « remplacé » (12,60) toujours lisible ; le jury ne peut pas rectifier (403) | `test_sta12_rectification_versionnee_et_historique_conserve`, `test_president_du_jury_approuve_…` |
| **STA13** | *Extension* : import ICS et propositions concurrentes | — | — | Pas de doublon ; aucun conflit accepté | **Non réalisé** : l'import ICS est une extension non retenue à ce stade ; aucun résultat n'est présenté | — |

## Cas complémentaires (socle)

| Cas | Résultat observé (19/11/2026) | Test |
|---|---|---|
| Parcours complet d'un dossier par l'API (dépôt, soumission, avis, autorisation) | Statuts successifs corrects ; historique de 4 étapes horodatées | `test_f03_parcours_complet_du_dossier_par_l_api` |
| F01 : seconde importation | Aperçu sans écriture ; 1re importation : 2 étudiants et 2 dossiers créés, 1 ligne en erreur signalée ; 2e importation : 0 création | `test_f01_seconde_importation_ne_cree_pas_deux_dossiers` |
| F04 : composition du jury | Refus avec 2 membres ; acceptation avec 3 ; doublon de personne refusé ; un retrait rend le jury incomplet | `test_f04_regle_de_composition_des_jurys` |
| F05 : publication tout ou rien | Un dossier redevenu non recevable fait refuser la publication entière : aucune version, aucune convocation | `test_f03_publication_refusee_si_un_dossier_n_est_plus_recevable` |
| Idempotence de la publication | Même clé : même réponse et une seule version ; contenu différent : 409 | `test_idempotence_de_la_publication` |
| Échec d'envoi des convocations | 7 échecs relançables ; le planning reste publié | `test_echec_de_notification_n_efface_pas_le_planning` |

## Données de démonstration

Les tests créent leurs propres données fictives (`backend/tests/factories.py`). Pour une démonstration manuelle :

- `python manage.py seed_sgsus` (base locale) ;
- ou les scripts SQL fictifs exécutés sur Render.

Le jeu demandé par le chapitre 5 comprend : deux campagnes, douze étudiants, quatre encadreurs, six jurés, trois salles, deux dossiers incomplets, une pièce remplacée et des tentatives de conflit. Il est **à compléter** : le jeu actuel n'en couvre qu'une partie, voir les réserves dans `cahier-des-charges.md`.

## Anomalies

Toute anomalie décrit : préconditions, étapes, résultat attendu, résultat obtenu, gravité, version.

Démarche :

1. ajouter d'abord un test qui reproduit le défaut ;
2. corriger ;
3. montrer le test réussi.

| Date | Anomalie | Gravité | Version | Test de non-régression | Statut |
|---|---|---|---|---|---|
| 19/11/2026 | Confirmation d'une soutenance : erreur 500 (« FOR UPDATE » sur une jointure facultative vers le jury) | Bloquante | modifications du 19/11 | `test_changement_de_statut_d_une_soutenance` | Corrigée (verrou limité à la ligne principale) |
| 19/11/2026 | Création d'un second dossier pour la même campagne : erreur 500 (index unique) | Majeure | modifications du 19/11 | `test_un_seul_dossier_par_etudiant_et_par_campagne` | Corrigée (refus 409 `F01` explicite) |
