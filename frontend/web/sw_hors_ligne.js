/*
 * Service worker de SGSUS : permet d'ouvrir le site sans connexion.
 *
 * Un service worker est un petit programme que le navigateur installe pour
 * le site et qui s'intercale entre la page et le réseau. Il garde ici une
 * copie des fichiers de l'APPLICATION (page, code, moteur de rendu, polices,
 * icônes) pour que SGSUS s'ouvre même hors ligne. Les DONNÉES (planning,
 * dossiers, notes…) ne passent pas par lui : l'application les mémorise
 * elle-même (lib/core/network/hors_ligne.dart).
 *
 * Stratégie « réseau d'abord » : en ligne, on prend toujours la version du
 * serveur (une nouvelle mise en ligne est donc visible tout de suite) et on
 * met la copie à jour ; hors ligne seulement, on sert la copie.
 */
'use strict';

/** Nom du cache ; à changer seulement si la logique de ce fichier change. */
const CACHE = 'sgsus-site-v1';

/** Fichiers indispensables, copiés dès l'installation. */
const ESSENTIELS = [
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'assets/FontManifest.json',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/fonts/Roboto-Regular.ttf',
  'assets/assets/fonts/Roboto-Medium.ttf',
  'assets/assets/fonts/Roboto-Bold.ttf',
];

/**
 * Chemins jamais mis en cache ici : l'API et l'administration Django
 * (version PC, servies à la même adresse que le site). Leurs données
 * changent sans cesse et sont gérées par l'application.
 */
const EXCLUS = ['/api/', '/admin/', '/media/', '/static/', '/health/'];

/** Polices de secours de Google (caractères rares), versionnées par URL. */
const HOTES_POLICES = ['fonts.gstatic.com', 'www.gstatic.com'];

/** Adresse de la page d'accueil, servie pour toute navigation hors ligne. */
const ACCUEIL = new URL('index.html', self.registration.scope).href;

/** Vrai si la requête vise un fichier du site que l'on peut conserver. */
function estFichierDuSite(url) {
  return (
    url.origin === self.location.origin &&
    !EXCLUS.some((chemin) => url.pathname.startsWith(chemin))
  );
}

// Installation : copie des fichiers essentiels. Un fichier absent ne bloque
// pas l'installation (allSettled), il sera copié à sa première utilisation.
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.allSettled(ESSENTIELS.map((chemin) => cache.add(chemin))),
    ),
  );
  // La nouvelle version prend la main sans attendre la fermeture des onglets.
  self.skipWaiting();
});

// Activation : suppression des caches d'anciennes versions de ce fichier.
self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const noms = await caches.keys();
      await Promise.all(
        noms
          .filter((nom) => nom.startsWith('sgsus-site-') && nom !== CACHE)
          .map((nom) => caches.delete(nom)),
      );
      // Contrôle immédiat des pages déjà ouvertes.
      await self.clients.claim();
    })(),
  );
});

// Interception des requêtes.
self.addEventListener('fetch', (event) => {
  const requete = event.request;
  if (requete.method !== 'GET') return; // envois : jamais interceptés
  const url = new URL(requete.url);

  if (requete.mode === 'navigate') {
    // Ouverture d'une adresse du site : la page d'accueil, qui contient
    // toute l'application (navigation interne gérée par Flutter).
    event.respondWith(reseauDAbord(requete, ACCUEIL));
  } else if (estFichierDuSite(url)) {
    event.respondWith(reseauDAbord(requete, requete));
  } else if (HOTES_POLICES.includes(url.hostname)) {
    event.respondWith(cacheDAbord(requete));
  }
  // Tout le reste (API Render, autres sites) passe sans intervention.
});

/**
 * Réseau d'abord : réponse du serveur (copiée sous la clé `cle`), ou la
 * copie enregistrée si le réseau est indisponible.
 */
async function reseauDAbord(requete, cle) {
  const cache = await caches.open(CACHE);
  try {
    const reponse = await fetch(requete);
    if (reponse.ok) await cache.put(cle, reponse.clone());
    return reponse;
  } catch (erreur) {
    const copie = await cache.match(cle, { ignoreSearch: true });
    if (copie) return copie;
    throw erreur; // jamais téléchargé : erreur réseau normale
  }
}

/** Cache d'abord : pour les fichiers dont l'adresse change à chaque version. */
async function cacheDAbord(requete) {
  const cache = await caches.open(CACHE);
  const copie = await cache.match(requete);
  if (copie) return copie;
  const reponse = await fetch(requete);
  // Réponse « opaque » (status 0) acceptée : polices chargées sans CORS.
  if (reponse.ok || reponse.type === 'opaque') {
    await cache.put(requete, reponse.clone());
  }
  return reponse;
}

// Message de la page (index.html) : liste des fichiers qu'elle a chargés
// AVANT que ce service worker ne soit actif (première visite). On les copie
// pour que la toute première visite suffise à rendre le site disponible
// hors ligne, avec exactement les fichiers utilisés par ce navigateur.
self.addEventListener('message', (event) => {
  const donnees = event.data;
  if (!donnees || donnees.type !== 'mettre-en-cache') return;
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      const urls = Array.isArray(donnees.urls) ? donnees.urls : [];
      await Promise.allSettled(
        urls.map(async (adresse) => {
          const url = new URL(adresse, self.registration.scope);
          if (!estFichierDuSite(url) && !HOTES_POLICES.includes(url.hostname)) {
            return;
          }
          if (await cache.match(url.href)) return; // déjà copié
          const reponse = await fetch(url.href);
          if (reponse.ok) await cache.put(url.href, reponse);
        }),
      );
      // La page elle-même est conservée comme page d'accueil hors ligne.
      const accueil = await fetch(ACCUEIL).catch(() => null);
      if (accueil && accueil.ok) await cache.put(ACCUEIL, accueil);
    })(),
  );
});
