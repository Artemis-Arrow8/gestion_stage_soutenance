"""
Sérialiseurs du domaine académique : campagnes, étudiants, dossiers,
versions de documents, avis et évaluations.

Ces sérialiseurs sont volontairement simples (`ModelSerializer`) : les
règles d'accès sont appliquées dans les vues, et les règles métier
complexes dans les services.
"""

from rest_framework import serializers

from api.models import (
    Assessment,
    Campaign,
    DocumentVersion,
    InternshipFolder,
    Review,
    Student,
)
from api.roles import get_user_role


class CampaignSerializer(serializers.ModelSerializer):
    """Campagne académique (année universitaire et état actif/inactif)."""

    class Meta:
        model = Campaign
        fields = '__all__'


class StudentSerializer(serializers.ModelSerializer):
    """Fiche étudiante (numéro, nom complet, e-mail)."""

    class Meta:
        model = Student
        fields = '__all__'


class InternshipFolderSerializer(serializers.ModelSerializer):
    """
    Dossier de stage.

    `status` est TOUJOURS en lecture seule : il ne change que par les
    transitions de api/services/dossiers.py (soumettre, autoriser…), jamais
    par une modification directe (STA11). `student` et `campaign` sont en
    plus rendus non modifiables par la vue lorsque l'appelant est étudiant.
    `confidentialite` indique le niveau (« standard » ou « confidentiel »).
    """

    confidentialite = serializers.SerializerMethodField()

    # --- Champs d'affichage, en lecture seule ------------------------------
    # Ils permettent à l'écran « Dossiers » de dire d'un coup d'œil À QUI
    # appartient le dossier, QUELLE version attend une décision et QUELLE a
    # été la dernière décision, sans requête supplémentaire par dossier.
    student_name = serializers.CharField(source='student.full_name', read_only=True)
    student_number = serializers.CharField(source='student.student_number', read_only=True)
    nombre_versions = serializers.SerializerMethodField()
    derniere_version = serializers.SerializerMethodField()
    dernier_avis = serializers.SerializerMethodField()
    derniere_etape = serializers.SerializerMethodField()

    class Meta:
        model = InternshipFolder
        fields = '__all__'
        read_only_fields = ('status',)

    def get_confidentialite(self, dossier):
        """Niveau de confidentialité du dossier (standard par défaut)."""
        reglage = getattr(dossier, 'confidentialite', None)
        return reglage.niveau if reglage is not None else 'standard'

    # Les méthodes ci-dessous parcourent `.all()` en Python : avec le
    # `prefetch_related` de la vue, aucune requête n'est faite par dossier.

    @staticmethod
    def _versions(dossier):
        """Versions du rapport, de la plus ancienne à la plus récente."""
        return sorted(dossier.document_versions.all(),
                      key=lambda v: (v.version_number, v.pk))

    @staticmethod
    def _date(valeur):
        """Date au format ISO 8601 de l'API (None conservé)."""
        return serializers.DateTimeField().to_representation(valeur) if valeur else None

    def get_nombre_versions(self, dossier):
        """Nombre de versions déposées du rapport."""
        return len(self._versions(dossier))

    def get_derniere_version(self, dossier):
        """Dernière version déposée : {id, version_number, uploaded_at} ou None."""
        versions = self._versions(dossier)
        if not versions:
            return None
        version = versions[-1]
        return {
            'id': version.pk,
            'version_number': version.version_number,
            'uploaded_at': self._date(version.uploaded_at),
        }

    def _avis_visible(self, avis):
        """
        Applique au dernier avis la MÊME règle de lecture que /api/reviews/
        (matrice des droits inchangée) : administrateur et étudiant
        propriétaire voient tout ; un encadreur ne voit que ses propres avis ;
        les autres rôles ne voient pas le détail des avis.
        """
        request = self.context.get('request')
        if request is None:
            return False
        # Rôle calculé UNE fois par réponse : en liste, la même instance du
        # sérialiseur sert pour tous les dossiers (pas de requête par ligne).
        if not hasattr(self, '_role_appelant'):
            self._role_appelant = get_user_role(request.user)
        role = self._role_appelant
        if role in ('admin', 'student'):
            return True
        if role == 'supervisor':
            return avis.author_id == request.user.pk
        return False

    def get_dernier_avis(self, dossier):
        """
        Avis le plus récent, toutes versions confondues (ex. la demande de
        correction reste lisible après le dépôt de la version corrigée) :
        {decision, comments, author_role, version_number, created_at} ou None.
        """
        avis = [
            (version.version_number, a)
            for version in self._versions(dossier)
            for a in version.reviews.all()
        ]
        if not avis:
            return None
        numero, dernier = max(avis, key=lambda paire: (paire[1].created_at, paire[1].pk))
        if not self._avis_visible(dernier):
            return None
        return {
            'decision': dernier.decision,
            'comments': dernier.comments or '',
            'author_role': dernier.author_role,
            'version_number': numero,
            'created_at': self._date(dernier.created_at),
        }

    def get_derniere_etape(self, dossier):
        """
        Dernière transition enregistrée (ex. motif d'un refus) :
        {evenement, statut_apres, motif, created_at} ou None.
        """
        lignes = list(dossier.historique.all())
        if not lignes:
            return None
        derniere = max(lignes, key=lambda h: (h.created_at, h.pk))
        return {
            'evenement': derniere.evenement,
            'statut_apres': derniere.statut_apres,
            'motif': derniere.motif,
            'created_at': self._date(derniere.created_at),
        }


class DocumentVersionSerializer(serializers.ModelSerializer):
    """Version déposée d'un rapport ; l'horodatage est fixé par le serveur."""

    class Meta:
        model = DocumentVersion
        fields = '__all__'
        read_only_fields = ('id', 'uploaded_at')


class ReviewSerializer(serializers.ModelSerializer):
    """
    Avis d'encadrement sur une version de document.

    L'auteur et son rôle sont déduits du jeton par la vue : ils sont donc en
    lecture seule et ne peuvent pas être usurpés par le client.
    """

    class Meta:
        model = Review
        fields = '__all__'
        read_only_fields = ('id', 'author', 'author_role', 'created_at')


class AssessmentSerializer(serializers.ModelSerializer):
    """
    Notes (rapport, oral, moyenne) et validation finale d'une soutenance.

    La moyenne (`final_average`) et l'approbation (`is_approved`) sont en
    lecture seule : la moyenne est TOUJOURS calculée par le serveur selon la
    grille de la campagne (api/services/notes.py) et l'approbation passe par
    l'action /approuver/. `grille` décrit la règle de calcul appliquée.

    Règles ajoutées :
        * une seule évaluation par soutenance ;
        * si la moyenne finale n'est pas fournie, elle est calculée
          automatiquement à partir des notes de rapport et d'oral.
    Champs ajoutés en lecture seule pour l'affichage : nom de l'étudiant,
    sujet, jury et créneau de la soutenance évaluée.
    """

    student_name = serializers.CharField(
        source='defense.folder.student.full_name', read_only=True,
    )
    subject = serializers.CharField(source='defense.folder.subject', read_only=True)
    jury_name = serializers.CharField(source='defense.jury.name', read_only=True, default='')
    defense_start = serializers.SerializerMethodField()
    grille = serializers.SerializerMethodField()
    nombre_proces_verbaux = serializers.IntegerField(
        source='proces_verbaux.count', read_only=True,
    )

    class Meta:
        model = Assessment
        fields = [
            'id',
            'defense',
            'student_name',
            'subject',
            'jury_name',
            'defense_start',
            'report_grade',
            'oral_grade',
            'final_average',
            'is_approved',
            'grille',
            'nombre_proces_verbaux',
        ]
        read_only_fields = ('final_average', 'is_approved')

    def get_defense_start(self, assessment):
        """Retourne le début du créneau de la soutenance (ISO 8601) ou None."""
        slot = assessment.defense.slot_range if assessment.defense_id else None
        return slot.lower.isoformat() if slot is not None and slot.lower else None

    def get_grille(self, evaluation):
        """Règle de calcul en vigueur (coefficients), sans rien créer."""
        from api.services.notes import grille_affichee
        return grille_affichee(evaluation.defense.folder.campaign)

    def validate(self, attrs):
        """
        Vérifie l'unicité par soutenance (la moyenne est calculée par la vue).

        Lève :
            ValidationError : une évaluation existe déjà pour cette soutenance.
        """
        attrs = super().validate(attrs)
        defense = attrs.get('defense') or (self.instance.defense if self.instance else None)
        if defense is not None:
            doublons = Assessment.objects.filter(defense=defense)
            if self.instance is not None:
                doublons = doublons.exclude(pk=self.instance.pk)
            if doublons.exists():
                raise serializers.ValidationError(
                    {'defense': 'Cette soutenance a déjà une évaluation : modifiez-la.'}
                )
        return attrs
