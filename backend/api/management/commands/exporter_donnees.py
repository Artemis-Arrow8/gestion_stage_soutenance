"""
Commande `python manage.py exporter_donnees --sortie <dossier>` (chapitre 23 :
« préparer le retrait »).

Produit un export documenté et réutilisable des données métier :

* un fichier par table (JSON par défaut, CSV avec --format csv), avec les
  identifiants d'origine pour que les liens entre tables restent lisibles ;
* `dictionnaire.json` : pour chaque table et chaque champ, le type, le
  caractère obligatoire, la description, et l'unité ou le format des dates
  (ISO 8601 en UTC) et des notes (sur 20, décimal exact) ;
* `manifeste.json` : date de l'export, version du schéma (dernière
  migration) et nombre de lignes par table, pour vérifier la réutilisation
  dans une base distincte.

Les comptes de connexion (mots de passe hachés, jetons) ne sont JAMAIS
exportés. Le jeu de démonstration est fictif ; pour des données réelles, la
politique de conservation, d'anonymisation et de suppression doit d'abord
être définie avec le responsable métier.
"""
import csv
import json
from pathlib import Path

from django.core.management.base import BaseCommand
from django.db.migrations.recorder import MigrationRecorder
from django.utils import timezone

from api import models

# Tables exportées, dans l'ordre des dépendances (référentiels d'abord).
MODELES_EXPORTES = (
    models.Campaign, models.Student, models.InternshipFolder, models.DocumentVersion,
    models.Review, models.HistoriqueDossier, models.ConfidentialiteDossier,
    models.Room, models.Jury, models.JuryMember, models.Indisponibilite,
    models.ExceptionIndisponibilite, models.Defense, models.VersionPlanning,
    models.Convocation, models.GrilleEvaluation, models.Assessment, models.ProcesVerbal,
)

# Champs qui désignent un compte de connexion : seul l'identifiant est gardé.
SUFFIXE_COMPTE = '_id'


def _valeur(valeur):
    """Rend une valeur sérialisable (dates ISO, décimaux en texte, plages)."""
    if hasattr(valeur, 'isoformat'):
        return valeur.isoformat()
    if hasattr(valeur, 'lower') and hasattr(valeur, 'upper'):  # tstzrange
        return {'debut': _valeur(valeur.lower), 'fin': _valeur(valeur.upper)}
    if valeur is None or isinstance(valeur, (bool, int, float, str, list, dict)):
        return valeur
    return str(valeur)


def _description_champ(champ):
    """Entrée du dictionnaire de données pour un champ."""
    description = {
        'type': champ.get_internal_type(),
        'obligatoire': not champ.null,
        'description': str(champ.help_text or champ.verbose_name),
    }
    if champ.get_internal_type() in ('DateTimeField', 'DateTimeRangeField'):
        description['format'] = 'ISO 8601, UTC'
    elif champ.get_internal_type() == 'DecimalField':
        description['format'] = f'décimal exact, {champ.decimal_places} décimales'
    if champ.is_relation:
        description['reference'] = champ.related_model._meta.db_table
    return description


class Command(BaseCommand):
    """Exporte les données métier avec leur dictionnaire."""

    help = "Exporte les données métier (JSON ou CSV) avec un dictionnaire de données."

    def add_arguments(self, parser):
        """Options : dossier de sortie et format."""
        parser.add_argument('--sortie', required=True, help="Dossier de destination (créé si besoin).")
        parser.add_argument('--format', choices=('json', 'csv'), default='json')

    def handle(self, *args, **options):
        """Écrit les fichiers d'export, le dictionnaire et le manifeste."""
        sortie = Path(options['sortie'])
        sortie.mkdir(parents=True, exist_ok=True)
        dictionnaire, comptes = {}, {}
        for modele in MODELES_EXPORTES:
            table = modele._meta.db_table
            champs = [c for c in modele._meta.concrete_fields]
            colonnes = [c.attname for c in champs]
            lignes = [
                {col: _valeur(getattr(objet, col)) for col in colonnes}
                for objet in modele.objects.order_by('pk')
            ]
            comptes[table] = len(lignes)
            dictionnaire[table] = {
                'description': (modele.__doc__ or '').strip().split('\n')[0],
                'champs': {c.attname: _description_champ(c) for c in champs},
            }
            if options['format'] == 'json':
                (sortie / f'{table}.json').write_text(
                    json.dumps(lignes, ensure_ascii=False, indent=2), encoding='utf-8')
            else:
                with open(sortie / f'{table}.csv', 'w', newline='', encoding='utf-8') as fichier:
                    ecrivain = csv.DictWriter(fichier, fieldnames=colonnes)
                    ecrivain.writeheader()
                    for ligne in lignes:
                        ecrivain.writerow({k: json.dumps(v, ensure_ascii=False)
                                           if isinstance(v, (dict, list)) else v
                                           for k, v in ligne.items()})
        derniere = (MigrationRecorder.Migration.objects.filter(app='api')
                    .order_by('-applied').values_list('name', flat=True).first())
        (sortie / 'dictionnaire.json').write_text(
            json.dumps(dictionnaire, ensure_ascii=False, indent=2), encoding='utf-8')
        (sortie / 'manifeste.json').write_text(json.dumps({
            'date_export': timezone.now().isoformat(),
            'format': options['format'],
            'version_schema': derniere,
            'lignes_par_table': comptes,
            'remarque': 'Comptes de connexion et secrets exclus. Données fictives de démonstration.',
        }, ensure_ascii=False, indent=2), encoding='utf-8')
        total = sum(comptes.values())
        self.stdout.write(f'Export terminé : {len(comptes)} tables, {total} lignes, dans {sortie}.')
