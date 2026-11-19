// Démarrage de l'application Flutter SGSUS (modèle remplacé par Flutter
// à la compilation : les deux lignes {{…}} deviennent le chargeur Flutter
// et la configuration de la compilation).
{{flutter_js}}
{{flutter_build_config}}

// Le service worker fourni par Flutter est obsolète (il se désinstalle
// tout seul) : on ne l'enregistre pas. Le fonctionnement hors ligne du
// site est assuré par « sw_hors_ligne.js », enregistré dans index.html.
_flutter.loader.load();
