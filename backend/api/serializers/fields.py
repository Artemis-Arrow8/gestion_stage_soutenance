"""
Champs de sérialisation personnalisés réutilisés par plusieurs sérialiseurs.
"""

from datetime import datetime

from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import serializers

from api.roles import get_user_role


class DateTimeRangeSerializerField(serializers.Field):
    """
    Sérialise un intervalle PostgreSQL `tstzrange` sous la forme {start, end}.

    Entrée attendue : {"start": "<ISO 8601 avec fuseau>", "end": "<idem>"}.
    Sortie produite : le même format, avec des dates ISO 8601.
    """

    default_error_messages = {
        'invalid': 'Fournissez une date de début et de fin avec fuseau horaire.',
        'order': 'La date de fin doit être postérieure à la date de début.',
    }

    def to_internal_value(self, data):
        """
        Convertit le JSON reçu en couple (début, fin).

        Paramètres :
            data : valeur brute reçue du client.

        Retour :
            tuple (datetime, datetime) conscients du fuseau horaire.

        Lève :
            ValidationError : structure invalide, date naïve (sans fuseau)
            ou fin antérieure/égale au début.
        """
        # On exige exactement les deux clés pour éviter les ambiguïtés.
        if not isinstance(data, dict) or set(data) != {'start', 'end'}:
            self.fail('invalid')

        datetimes = []
        for key in ('start', 'end'):
            value = data[key]
            try:
                parsed = parse_datetime(value) if isinstance(value, str) else value
            except ValueError:
                parsed = None
            # Une date sans fuseau serait interprétée différemment selon le
            # serveur : elle est refusée (exigence NFR04, tout est en UTC).
            if not isinstance(parsed, datetime) or timezone.is_naive(parsed):
                raise serializers.ValidationError({key: self.error_messages['invalid']})
            datetimes.append(parsed)

        start, end = datetimes
        if end <= start:
            self.fail('order')
        return start, end

    def to_representation(self, value):
        """
        Convertit un intervalle (objet Range ou tuple) en dictionnaire JSON.

        Retour :
            {"start": str, "end": str} ou None si l'intervalle est absent.
        """
        if value is None:
            return None
        if isinstance(value, (tuple, list)):
            start, end = value
        else:
            # Objet `DateTimeTZRange` renvoyé par psycopg.
            start, end = value.lower, value.upper
        return {
            'start': start.isoformat(),
            'end': end.isoformat(),
        }


class AccountRoleField(serializers.ChoiceField):
    """
    Champ « rôle » d'un compte : calculé en lecture, choisi en écriture.

    En lecture, le rôle n'est pas une colonne mais une déduction (groupes
    Django, fiche étudiante, fiche jury) : on surcharge donc `get_attribute`.
    """

    def get_attribute(self, instance):
        """Retourne le rôle SGSUS calculé pour l'utilisateur sérialisé."""
        return get_user_role(instance)
