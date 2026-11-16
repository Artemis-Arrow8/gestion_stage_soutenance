"""
Commande `python manage.py wait_for_db` : attend que PostgreSQL soit joignable.

Au démarrage d'un conteneur, la base peut ne pas encore accepter de
connexions (base Render en cours de réveil, service `db` de Compose encore
en initialisation). Lancer `migrate` trop tôt ferait échouer le démarrage.
Cette commande réessaie la connexion à intervalle régulier et ne rend la
main qu'une fois la base disponible, ou échoue proprement après un délai.
"""

import time

from django.core.management.base import BaseCommand, CommandError
from django.db import connections
from django.db.utils import OperationalError


class Command(BaseCommand):
    """Attend la disponibilité de la base de données `default`."""

    help = "Attend que la base de données accepte les connexions."

    def add_arguments(self, parser):
        """
        Déclare les options de la ligne de commande.

        Paramètres :
            parser (argparse.ArgumentParser) : analyseur fourni par Django.
        """
        parser.add_argument(
            '--timeout',
            type=int,
            default=60,
            help="Durée maximale d'attente, en secondes (60 par défaut).",
        )
        parser.add_argument(
            '--interval',
            type=float,
            default=2.0,
            help='Délai entre deux tentatives, en secondes (2 par défaut).',
        )

    def handle(self, *args, **options):
        """
        Boucle de tentatives de connexion.

        Lève :
            CommandError : la base est restée injoignable au-delà du délai
            (le script de démarrage s'arrête alors avec un code d'erreur).
        """
        timeout = options['timeout']
        interval = options['interval']
        # `monotonic` n'est pas affecté par les changements d'heure système.
        echeance = time.monotonic() + timeout
        connexion = connections['default']
        tentative = 0

        while True:
            tentative += 1
            try:
                # `ensure_connection` ouvre réellement une connexion réseau.
                connexion.ensure_connection()
            except OperationalError as error:
                if time.monotonic() >= echeance:
                    raise CommandError(
                        f'Base de données injoignable après {timeout} s : {error}'
                    ) from error
                self.stdout.write(
                    f'Base de données indisponible (tentative {tentative}), '
                    f'nouvel essai dans {interval:g} s…'
                )
                time.sleep(interval)
                continue

            # On referme pour que les commandes suivantes repartent d'une
            # connexion fraîche (et non d'une connexion héritée d'ici).
            connexion.close()
            self.stdout.write(self.style.SUCCESS('Base de données disponible.'))
            return
