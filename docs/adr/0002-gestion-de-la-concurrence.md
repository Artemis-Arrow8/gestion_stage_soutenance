# ADR 0002 : Strategie de Gestion de la Concurrence (Regle EXG01)

**Projet :** SGSUS  
**Auteur :** Kadiatou Helene GUINDO (Lot 1)  
**Date :** 23 Octobre 2026  
**Statut :** Accepte  

---

## 1. Contexte
L'exigence EXG01 impose d'empecher formellement les doubles reservations de salles ou de jurys en cas d'actions simultanees.

## 2. Decision Prise
Utilisation des contraintes d'exclusion natives de PostgreSQL (`tstzrange` et `btree_gist`) associees a des transactions atomiques cote Django. La base de donnees rejette immediatement toute insertion conflictuelle et renvoie une erreur.