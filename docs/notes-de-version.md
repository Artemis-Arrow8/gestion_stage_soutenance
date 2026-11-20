# Notes de version — SGSUS

Chapitre 19 du dossier ALM : chaque version livrée est identifiée par un **tag annoté**, le **SHA du commit**, l'**empreinte SHA-256 de l'image** construite par la CI et la **recette** correspondante.

## Version 1.0.0 — proposée le 20/11/2026

> À faire par l'équipe après le dernier commit accepté :
>
> ```bash
> git tag -a v1.0.0 -m "SGSUS 1.0.0 — socle du dossier ALM"
> git push origin v1.0.0
> ```
>
> Recopier ensuite ici le SHA du commit tagué et l'empreinte `image.tar.gz.sha256` de l'artefact `image-<sha>` produit par le job « Image identifiée par le commit » de GitHub Actions.

| Élément | Valeur |
|---|---|
| Tag | `v1.0.0` (à créer) |
| Commit | **à recopier** (SHA complet du commit tagué) |
| Empreinte de l'image | **à recopier** depuis l'artefact CI |
| Recette | `docs/recette.md`, exécution du 19/11/2026, complétée le 20/11/2026 |
| Tests | backend : suite PostgreSQL complète réussie le 20/11/2026 ; frontend : 74 tests Flutter réussis le 20/11/2026 |

### Contenu : socle du dossier

- **F01** : campagnes ; import CSV des étudiants avec aperçu, rapport d'erreurs et sans doublon.
- **F02** : dossier (entreprise, sujet) ; rapports PDF versionnés ; avis liés à la version examinée ; confidentialité, habilitations et embargo.
- **F03** : affectation des encadreurs ; avis pédagogique ; autorisation de soutenance. Un dossier non recevable ne peut pas être planifié.
- **F04** : jurys (membres, fonctions, règle de composition) ; indisponibilités récurrentes avec exceptions et fuseau.
- **F05** : planification avec détection des conflits ; publication figée et versionnée ; convocations ; report et annulation.
- **F06** : grille 40/60 fictive ; calcul décimal côté serveur ; approbation ; procès-verbal versionné ; rectification motivée.
- **EXG01** : contraintes d'exclusion PostgreSQL (`tstzrange` + `btree_gist`) et verrou transactionnel ; testé avec deux connexions réelles.

### Réalisé en plus du socle

- Application Flutter Web, Android (APK) et version PC hors ligne ; utilisable à une main sur un écran de 360 px.
- Mode hors ligne en consultation.
- Pages « Documents » propres à chaque profil (20/11/2026) :
  - étudiant : tout sur une page, dépôt toujours visible ;
  - encadreur : rapports à examiner ;
  - responsable : décisions ;
  - jury : rapports à lire avant la soutenance, en lecture seule côté serveur.

### Modifications du 20/11/2026

- Ergonomie de la partie Documents, différenciée par rôle. La page complète d'un dossier remplace le panneau flottant.
- Jury : lecture seule des dossiers et rapports des soutenances actives de son jury (`test_le_jury_liste_en_lecture_seule_les_dossiers_de_ses_soutenances`).
- Commande `seed_demo` : jeu de démonstration du chapitre 5 (`tests/test_seed_demo.py`).
- Script `scripts/exercice-restauration.sh` : restauration réellement exercée sur données fictives, durées mesurées (`guide-exploitation.md`).
- Budget : conditions des offres gratuites Render relevées le 20/11/2026 (`cadrage.md`).

### Migrations

Aucune nouvelle migration le 20/11/2026. Les migrations 0012 et 0013 sont additives (voir `guide-exploitation.md`, retour arrière).

### Limites connues

- NFR05 (p95 inférieur à 2 s avec 20 utilisateurs) non mesurée.
- Stockage des fichiers éphémère sur l'offre gratuite Render ; base gratuite limitée à 30 jours.
- STA13 (import ICS, propositions concurrentes) : extension non réalisée.
- Soutenances à distance (chapitre 21) : évolution analysée, non réalisée.
