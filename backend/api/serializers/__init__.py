"""
Paquet des sérialiseurs de l'API SGSUS, découpé par domaine fonctionnel.

Organisation :
    * `fields`   : champs personnalisés réutilisables ;
    * `accounts` : comptes utilisateurs, rôles et liaisons métier ;
    * `academic` : campagnes, étudiants, dossiers, documents, avis, notes ;
    * `planning` : salles, jurys, membres et soutenances.

Les classes sont réexportées ici pour conserver l'import historique
`from api.serializers import X` utilisé par les vues et les tests.
"""

from .academic import (
    AssessmentSerializer,
    CampaignSerializer,
    DocumentVersionSerializer,
    InternshipFolderSerializer,
    ReviewSerializer,
    StudentSerializer,
)
from .accounts import UserAccountSerializer
from .fields import AccountRoleField, DateTimeRangeSerializerField
from .planning import (
    DefenseSerializer,
    JuryMemberSerializer,
    JurySerializer,
    SalleSerializer,
)

# Liste explicite des noms publics du paquet.
__all__ = [
    'AccountRoleField',
    'AssessmentSerializer',
    'CampaignSerializer',
    'DateTimeRangeSerializerField',
    'DefenseSerializer',
    'DocumentVersionSerializer',
    'InternshipFolderSerializer',
    'JuryMemberSerializer',
    'JurySerializer',
    'ReviewSerializer',
    'SalleSerializer',
    'StudentSerializer',
    'UserAccountSerializer',
]
