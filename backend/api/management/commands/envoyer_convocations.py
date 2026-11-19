"""
Commande `python manage.py envoyer_convocations` (F05, chapitres 8 et 12).

Envoie les notifications des convocations ACTIVES en attente ou en échec,
par courriel (backend de messagerie configuré : console en démonstration,
donc « courriel simulé »). Chaque convocation est traitée isolément :

* succès → notification « envoyee » ;
* adresse inconnue ou erreur d'envoi → « echec », tentative comptée ; la
  commande peut être relancée plus tard (au plus --max-tentatives fois).

L'envoi ne modifie JAMAIS le planning publié : un échec de notification
n'efface ni ne remplace aucune convocation (chapitre 12 : « son échec ne
doit pas effacer le planning validé »).
"""
from django.conf import settings
from django.core.mail import send_mail
from django.core.management.base import BaseCommand

from api.journalisation import tracer_evenement
from api.models import Convocation


class Command(BaseCommand):
    """Envoie (ou relance) les notifications de convocation."""

    help = "Envoie les notifications des convocations en attente (relançable)."

    def add_arguments(self, parser):
        """Option : nombre maximal de tentatives par convocation."""
        parser.add_argument('--max-tentatives', type=int, default=5)

    def handle(self, *args, **options):
        """Parcourt les convocations à notifier et rend compte du résultat."""
        a_traiter = Convocation.objects.filter(
            statut='active', notification__in=('en_attente', 'echec'),
            tentatives_envoi__lt=options['max_tentatives'],
        ).select_related('compte', 'version')
        envoyees = echecs = 0
        for convocation in a_traiter:
            convocation.tentatives_envoi += 1
            adresse = getattr(convocation.compte, 'email', '') or ''
            try:
                if not adresse:
                    raise ValueError('aucune adresse e-mail connue')
                send_mail(
                    subject=f'Convocation à une soutenance (planning v{convocation.version.numero})',
                    message=(
                        f'Bonjour {convocation.destinataire},\n\n'
                        f'Vous êtes convoqué(e) en tant que {convocation.role_destinataire} '
                        f'le {convocation.debut:%d/%m/%Y à %H:%M} (UTC), salle {convocation.salle}.\n'
                        f'Version du planning : {convocation.version.numero}.\n'
                    ),
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[adresse],
                )
                convocation.notification = 'envoyee'
                envoyees += 1
            except Exception as erreur:  # noqa: BLE001 - tout échec est relançable
                convocation.notification = 'echec'
                echecs += 1
                tracer_evenement('convocation.echec_envoi', convocation=convocation.pk,
                                 raison=type(erreur).__name__)
            convocation.save(update_fields=['notification', 'tentatives_envoi'])
        self.stdout.write(f'Notifications envoyées : {envoyees} ; en échec (à relancer) : {echecs}.')
