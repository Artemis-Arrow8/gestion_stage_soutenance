"""
Import des étudiants d'une campagne (F01 : « importer les étudiants avec
contrôle des doublons » ; critère : une seconde importation ne crée pas deux
dossiers).

Fonctionnement :
* format CSV (séparateur « ; » ou « , », encodage UTF-8) avec les colonnes
  matricule, nom, email (les noms anglais student_number, full_name, email
  sont aussi acceptés) ;
* mode SIMULATION (prévisualisation) : le rapport est calculé mais rien
  n'est enregistré ;
* chaque ligne est contrôlée ; une ligne en erreur est signalée dans le
  rapport sans bloquer les autres (reprise possible après correction) ;
* un étudiant est identifié par son matricule : s'il existe déjà, il n'est
  ni recréé ni modifié ; une incohérence (même matricule, autre e-mail) est
  signalée au lieu d'écraser la fiche ;
* un dossier « brouillon » est créé pour la campagne seulement si
  l'étudiant n'en a pas encore : réimporter le même fichier ne crée rien.
Les imports sont sérialisés par un verrou transactionnel, et un index
unique (étudiant, campagne) protège la base (migration 0013).
"""
import csv
import io

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import validate_email
from django.db import connection, transaction

from api.journalisation import tracer_evenement
from api.models import InternshipFolder, Student

# Correspondance des en-têtes acceptés (français ou anglais) vers les champs.
EN_TETES = {
    'matricule': 'student_number', 'student_number': 'student_number',
    'nom': 'full_name', 'nom complet': 'full_name', 'full_name': 'full_name',
    'email': 'email', 'e-mail': 'email', 'courriel': 'email',
}
CHAMPS_OBLIGATOIRES = ('student_number', 'full_name', 'email')
# Valeur provisoire des champs que l'étudiant complétera lui-même.
A_RENSEIGNER = 'À renseigner par l’étudiant'
# Garde-fou : nombre maximal de lignes par import.
LIGNES_MAX = 2000


def lire_csv(texte):
    """
    Transforme un texte CSV en liste de dictionnaires normalisés.

    Lève ValueError si les colonnes obligatoires manquent.
    """
    texte = texte.lstrip('﻿')  # BOM éventuel d'Excel
    echantillon = texte[:2048]
    separateur = ';' if echantillon.count(';') >= echantillon.count(',') else ','
    lecteur = csv.DictReader(io.StringIO(texte), delimiter=separateur)
    colonnes = {
        nom: EN_TETES.get((nom or '').strip().lower())
        for nom in (lecteur.fieldnames or [])
    }
    manquantes = set(CHAMPS_OBLIGATOIRES) - set(colonnes.values())
    if manquantes:
        raise ValueError(
            'Colonnes obligatoires absentes : matricule, nom, email '
            '(séparateur « ; » ou « , »).'
        )
    lignes = []
    for brute in lecteur:
        lignes.append({
            champ: (brute.get(nom) or '').strip()
            for nom, champ in colonnes.items() if champ
        })
        if len(lignes) > LIGNES_MAX:
            raise ValueError(f'Fichier trop volumineux (plus de {LIGNES_MAX} lignes).')
    return lignes


@transaction.atomic
def importer(lignes, campagne, acteur, simulation=False):
    """
    Importe `lignes` dans `campagne` et retourne le rapport d'import.

    Paramètres :
        lignes (list[dict]) : student_number, full_name, email ;
        campagne (Campaign) : campagne de rattachement des dossiers ;
        acteur (User) : auteur de l'import (journal métier) ;
        simulation (bool) : prévisualisation sans écriture.
    """
    # Un seul import à la fois : deux imports simultanés ne peuvent pas
    # créer deux fois le même étudiant ou le même dossier.
    with connection.cursor() as curseur:
        curseur.execute("SELECT pg_advisory_xact_lock(%s, %s)", [0x534753, 2])

    rapport = {
        'simulation': simulation,
        'etudiants_crees': 0, 'etudiants_existants': 0,
        'dossiers_crees': 0, 'dossiers_existants': 0,
        'erreurs': [],
    }
    for numero, ligne in enumerate(lignes, start=2):  # ligne 1 = en-têtes
        matricule = ligne.get('student_number', '')
        nom = ligne.get('full_name', '')
        email = ligne.get('email', '').lower()
        if not (matricule and nom and email):
            rapport['erreurs'].append({'ligne': numero, 'erreur': 'Matricule, nom et e-mail sont obligatoires.'})
            continue
        try:
            validate_email(email)
        except DjangoValidationError:
            rapport['erreurs'].append({'ligne': numero, 'erreur': f'E-mail invalide : {email}'})
            continue

        etudiant = Student.objects.filter(student_number=matricule).first()
        if etudiant is not None:
            if etudiant.email.lower() != email:
                rapport['erreurs'].append({
                    'ligne': numero,
                    'erreur': f'Le matricule {matricule} existe déjà avec un autre e-mail : fiche non modifiée.',
                })
                continue
            rapport['etudiants_existants'] += 1
        else:
            if Student.objects.filter(email__iexact=email).exists():
                rapport['erreurs'].append({
                    'ligne': numero,
                    'erreur': f"L'e-mail {email} appartient déjà à un autre matricule.",
                })
                continue
            etudiant = Student.objects.create(student_number=matricule, full_name=nom, email=email)
            rapport['etudiants_crees'] += 1

        if InternshipFolder.objects.filter(student=etudiant, campaign=campagne).exists():
            rapport['dossiers_existants'] += 1
        else:
            InternshipFolder.objects.create(
                student=etudiant, campaign=campagne, company_name=A_RENSEIGNER,
                subject=A_RENSEIGNER, status='brouillon',
            )
            rapport['dossiers_crees'] += 1

    if simulation:
        # Prévisualisation : on annule toutes les écritures de la transaction.
        transaction.set_rollback(True)
    else:
        tracer_evenement('etudiants.importes', campagne=campagne.pk,
                         etudiants_crees=rapport['etudiants_crees'],
                         dossiers_crees=rapport['dossiers_crees'],
                         erreurs=len(rapport['erreurs']),
                         acteur=getattr(acteur, 'pk', None))
    return rapport
