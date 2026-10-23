# DOSSIER DE CADRAGE DU PROJET (SGSUS)

**Projet :** Systeme de Gestion des Stages et Soutenances Universitaires (SGSUS)  
**Etablissement :** Institut prive Africain de Technologies et de Management (ITMA)  
**Auteur Principal (Lot 1) :** Kadiatou Helene GUINDO  
**Equipe Projet (Groupe 4) :** Kadiatou Helene GUINDO, Mariam DIARRA, Kadidia DIARRA, Nahawa SANOGO  
**Date :** 23 Octobre 2026   

---

## 1. Contexte et Justification du Projet

Dans le cadre de la scolarite et de la fin de cycle e l'Institut Africain de Technologies et de Management (ITMA), la gestion des stages et des soutenances implique traditionnellement un volume important de documents papier, d'echanges d'e-mails non centralises et de risques eleves de conflits d'emplois du temps (salles reservees en double ou membres de jury sollicites sur deux soutenances simultanees). 

Le projet **SGSUS** a pour ambition de concevoir et deployer une plateforme logicielle integree, moderne et securisee, permettant de dematerialiser l'ensemble du processus, depuis le depot initial des dossiers de stage jusqu'a l'archivage des Proces-Verbaux (PV) de soutenance.

## 2. Objectifs Strategiques et Operationnels

- **Dematerialisation totale :** Centraliser la soumission des dossiers, des rapports de stage et le suivi des versions (V1, V2).
- **Transparence et Traaabilite :** Assurer un suivi en temps reel par les encadreurs, les tuteurs en entreprise, les responsables de stages et les jurys.
- **Zero Conflit de Planning (EXG01) :** Garantir par des contraintes de base de donnees l'impossibilite absolue de chevauchement d'horaires pour une salle ou un membre du jury.
- **Rigueur des Resultats :** Securiser le calcul des notes finales en type `NUMERIC`/`DECIMAL` exact et figer les PV officiels.

## 3. Parties Prenantes et Roles Cles

- **Etudiant :** Soumission des pieces, suivi de l'avancement et consultation de son dossier.
- **Encadreur Pedagogique :** Evaluation et emission de l'avis de recevabilite sur les rapports de ses Etudiants.
- **Tuteur en Entreprise :** Suivi et validation du stage en milieu professionnel.
- **Responsable des Stages :** Validation de l'eligibilite administrative et pedagogique des dossiers.
- **Planificateur :** Gestion des salles, des jurys et publication des plannings de soutenance.
- **Membres / President du Jury :** Saisie des notes de soutenance, validation du PV final et gestion des rectifications exceptionnelles.

## 4. Perimrtre de la Solution (MVP et Evolutions)

- **Backend :** API REST developpee avec Django REST Framework, connectee a une base de donnees PostgreSQL 17.
- **Frontend :** Application multiplateforme (Mobile & Web) developpee en Flutter, assurant une ergonomie fluide a partir de 360 px de largeur.
- **Securite et Gouvernance :** Controle d'acces strict par roles cote serveur, gestion des tokens d'authentification et journalisation des actions sensibles (Audit Logs).

## 5. Organisation et Planification (ALM)

Le projet est reparti en lots de developpement, sous la conduite technique et documentaire d'Helene Guindo (Lot 1 : Cadrage, Architecture, Base de donnees et Socle Backend/Frontend), en etroite collaboration avec l'equipe du Groupe 4.