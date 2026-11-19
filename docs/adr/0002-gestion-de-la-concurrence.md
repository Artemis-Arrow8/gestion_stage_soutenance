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
## Mise à jour du 19 novembre 2026

La décision initiale (contraintes d'exclusion PostgreSQL) est conservée. Elle est complétée sur plusieurs points.

- **Personne commune à deux jurys.** La contrainte porte sur `jury_id` et ne voit pas un même membre présent dans deux jurys. Les écritures de planning (proposer, modifier, reporter, publier) prennent donc d'abord le verrou transactionnel `pg_advisory_xact_lock(0x534753, 1)`. Elles **refont ensuite tous les contrôles dans la transaction** : contrôle par nom de membre, marge de déplacement, indisponibilités. C'est l'option « verrouiller les ressources dans un ordre stable et refaire les contrôles » décrite au chapitre 12. Elle est prouvée par `test_sta03_meme_membre_dans_deux_jurys_une_seule_reservation_validee` (deux connexions réelles).
- **Réservations actives seulement.** Les contraintes ont désormais la condition `WHERE (status <> 'annule')` (migration 0013) : une soutenance annulée libère la salle et le jury.
- **Marge de déplacement (STA02).** `SGSUS_MARGE_MINUTES` (0 par défaut) élargit le créneau lors des contrôles applicatifs. Comme ces contrôles s'exécutent sous le verrou, la marge est respectée même en cas d'écritures simultanées.
- **Publication.** Elle revérifie toutes les règles et fige une version dans une seule transaction. Si le serveur s'arrête avant la validation finale, PostgreSQL annule tout : aucune publication partielle. L'en-tête `Idempotency-Key` évite une double publication lorsqu'une réponse s'est perdue.
- **Réponse au client.** Un conflit renvoie HTTP **409** `{code: BUSINESS_CONFLICT, regle: EXG01, message, request_id}`. Le message identifie la ressource et la soutenance en conflit, sans divulguer le dossier d'un autre étudiant.

**Condition de révision :** si plusieurs établissements partagent la même base, remplacer le verrou global par des verrous par ressource (salle, personne), pris dans un ordre stable.
