# CAHIER DES CHARGES DU PROJET (SGSUS)

**Projet :** Systeme de Gestion des Stages et Soutenances Universitaires (SGSUS)  
**Etablissement :** Institut prive Africain de Technologies et de Management (ITMA)  
**Auteur Principal (Lot 1) :** Kadiatou Helene GUINDO  
**Date :** 23 Octobre 2026  

---

## 1. Objectif du Projet
Le projet SGSUS consiste a developper une application web et mobile pour automatiser et securiser la gestion complete des stages et des soutenances a l'ITMA.

## 2. Exigences Fonctionnelles
- **F01 :** Gestion des campagnes, des filieres et import des etudiants sans doublons.
- **F02 :** Depot des dossiers de stage et gestion des versions de documents (V1, V2) avec niveau de confidentialite.
- **F03 :** Suivi des stages et validation obligatoire de l'avis de recevabilite par l'encadreur.
- **F04 :** Constitution des jurys et gestion des indisponibilites des salles et des membres.
- **F05 :** Planification des soutenances avec attribution des salles et des creneaux horaires.
- **F06 :** Grille de notation avec type Decimal exact, validation des Proces-Verbaux (PV) et rectifications.

## 3. Exigences Non Fonctionnelles et Regles Critiques
- **EXG01 :** Interdiction absolue de chevauchement d'horaires pour une meme salle ou un meme membre du jury (gestion par contraintes PostgreSQL).
- **NFR01 :** Interface mobile et web responsive (adaptee a partir de 360 px de largeur).
- **NFR02 :** Controle strict des droits d'acces cote serveur selon le role utilisateur.
- **NFR03 :** Gestion robuste des coupures reseau et preservation de l'integrite des donnees.
- **NFR04 :** Horodatage en UTC et calculs de moyennes chiffres en Decimal.
- **NFR05 :** Performance cible p95 inferieure a 2 secondes sous 20 utilisateurs simultanes.