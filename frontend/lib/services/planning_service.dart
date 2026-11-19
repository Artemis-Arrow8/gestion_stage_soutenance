/// Accès aux routes de planification : soutenances, salles, jurys et
/// dossiers de stage.
library;

import '../core/network/api_service.dart';
import '../models/defense.dart';
import '../models/planning_refs.dart';

/// Service du planning des soutenances.
///
/// Le serveur reste seul juge des conflits (salle, jury, recevabilité) :
/// une création refusée remonte sous forme d'[ApiException] (HTTP 400)
/// dont le message est directement affichable.
class PlanningService {
  /// Crée le service à partir du client HTTP authentifié [api].
  PlanningService(this.api);

  /// Client HTTP authentifié partagé.
  final ApiService api;

  /// Charge le planning complet, trié chronologiquement par le serveur.
  ///
  /// Lève une [FormatException] si la réponse ne contient pas la liste
  /// `soutenances` attendue.
  Future<List<Defense>> loadDefenses() async {
    final data = await api.getObject('soutenances/planning/');
    final items = data['soutenances'];
    if (items is! List) {
      throw const FormatException('Le serveur a renvoyé un planning invalide.');
    }
    return items
        .whereType<Map>()
        .map((item) => Defense.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// Liste les salles du catalogue.
  Future<List<Map<String, dynamic>>> loadRooms() => api.getList('salles/');

  /// Liste les jurys avec leurs membres.
  Future<List<Map<String, dynamic>>> loadJuries() => api.getList('jurys/');

  /// Liste les dossiers de stage planifiables.
  Future<List<Map<String, dynamic>>> loadFolders() =>
      api.getList('internship-folders/');

  /// Demande la création d'une soutenance.
  ///
  /// Les instants [start] et [end] sont envoyés en UTC (exigence NFR04) ;
  /// retourne la soutenance enregistrée par le serveur.
  Future<Map<String, dynamic>> createDefense({
    required int folderId,
    required int juryId,
    required String roomName,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await api.post('soutenances/', {
      'folder': folderId,
      'jury': juryId,
      'room_name': roomName,
      'slot_start': start.toUtc().toIso8601String(),
      'slot_end': end.toUtc().toIso8601String(),
    });
    return ApiService.requireObject(data);
  }

  // -------------------------------------------------------------------
  // Cycle de vie (F04, F05) : le statut ne se modifie jamais directement.
  // -------------------------------------------------------------------

  /// Confirme une soutenance proposée (dossier recevable, jury complet).
  Future<void> confirmer(int id) => api.post('soutenances/$id/confirmer/', null);

  /// Annule une soutenance : salle et jury libérés, convocations annulées.
  Future<void> annuler(int id, {String motif = ''}) =>
      api.post('soutenances/$id/annuler/', {'motif': motif});

  /// Enregistre qu'une soutenance publiée a bien eu lieu.
  Future<void> marquerTenue(int id) => api.post('soutenances/$id/tenue/', null);

  /// Publie toutes les soutenances confirmées dans une nouvelle version du
  /// planning et produit les convocations. [cle] : clé d'idempotence de
  /// l'action (réutilisée si l'utilisateur relance après une coupure).
  Future<Map<String, dynamic>> publier({String commentaire = '', required String cle}) async {
    final data = await api.post(
      'soutenances/publier/',
      {'commentaire': commentaire},
      idempotencyKey: cle,
    );
    return ApiService.requireObject(data);
  }

  /// Reporte une soutenance publiée ([debut]/[fin] locaux) avec un motif :
  /// une nouvelle version du planning est publiée et les anciennes
  /// convocations sont marquées « remplacées ».
  Future<Map<String, dynamic>> reporter(
    int id, {
    required DateTime debut,
    required DateTime fin,
    required String motif,
    String? salle,
    required String cle,
  }) async {
    final data = await api.post(
      'soutenances/$id/reporter/',
      {
        'slot_start': debut.toUtc().toIso8601String(),
        'slot_end': fin.toUtc().toIso8601String(),
        'motif': motif,
        if (salle != null) 'room_name': salle,
      },
      idempotencyKey: cle,
    );
    return ApiService.requireObject(data);
  }

  /// Supprime une soutenance non publiée (une soutenance publiée s'annule).
  Future<void> deleteDefense(int id) => api.delete('soutenances/$id/');

  /// Versions publiées du planning (la plus récente en premier).
  Future<List<Map<String, dynamic>>> versions() => api.getList('versions-planning/');

  /// Convocations visibles (les siennes ; toutes pour le personnel).
  Future<List<Map<String, dynamic>>> convocations({int? soutenance}) => api.getList(
    'convocations/',
    query: soutenance == null ? null : {'soutenance': '$soutenance'},
  );

  // -------------------------------------------------------------------
  // Indisponibilités récurrentes (complément F04, personnel)
  // -------------------------------------------------------------------

  /// Indisponibilités d'une [ressource] (nom du membre ou de la salle).
  Future<List<Map<String, dynamic>>> indisponibilites({String? ressource}) => api.getList(
    'indisponibilites/',
    query: ressource == null ? null : {'ressource': ressource},
  );

  /// Crée une indisponibilité hebdomadaire ; la réponse contient `alertes`
  /// (soutenances déjà publiées concernées, jamais déplacées automatiquement).
  Future<Map<String, dynamic>> creerIndisponibilite(Map<String, dynamic> regle) async {
    return ApiService.requireObject(await api.post('indisponibilites/', regle));
  }

  /// Supprime une indisponibilité.
  Future<void> supprimerIndisponibilite(int id) => api.delete('indisponibilites/$id/');

  // -------------------------------------------------------------------
  // Catalogue des salles (CRUD, réservé au personnel)
  // -------------------------------------------------------------------

  /// Liste les salles sous forme de modèles typés, triées par nom.
  Future<List<Room>> loadRoomRecords() async {
    return (await loadRooms()).map(Room.fromJson).toList();
  }

  /// Crée une salle ; le nom doit être unique et la capacité positive.
  Future<Room> createRoom({
    required String name,
    required int capacity,
    required bool isActive,
  }) async {
    final data = await api.post('salles/', {
      'name': name,
      'capacity': capacity,
      'is_active': isActive,
    });
    return Room.fromJson(ApiService.requireObject(data));
  }

  /// Modifie la salle [id].
  Future<Room> updateRoom(
    int id, {
    required String name,
    required int capacity,
    required bool isActive,
  }) async {
    final data = await api.patch('salles/$id/', {
      'name': name,
      'capacity': capacity,
      'is_active': isActive,
    });
    return Room.fromJson(ApiService.requireObject(data));
  }

  /// Supprime la salle [id].
  Future<void> deleteRoom(int id) => api.delete('salles/$id/');

  // -------------------------------------------------------------------
  // Jurys et membres (écriture réservée au personnel)
  // -------------------------------------------------------------------

  /// Liste les jurys avec leurs membres, sous forme de modèles typés.
  Future<List<Jury>> loadJuryRecords() async {
    return (await loadJuries()).map(Jury.fromJson).toList();
  }

  /// Crée un jury vide nommé [name].
  Future<Jury> createJury(String name) async {
    final data = await api.post('jurys/', {'name': name, 'is_complete': false});
    return Jury.fromJson(ApiService.requireObject(data));
  }

  /// Déclare le jury [id] complet ou incomplet.
  Future<void> setJuryComplete(int id, {required bool isComplete}) async {
    await api.patch('jurys/$id/', {'is_complete': isComplete});
  }

  /// Ajoute un membre au jury [juryId].
  ///
  /// [role] vaut `president`, `rapporteur` ou `examinateur`.
  Future<JuryMember> addJuryMember({
    required int juryId,
    required String name,
    required String role,
  }) async {
    final data = await api.post('jury-members/', {
      'jury': juryId,
      'member_name': name,
      'role_in_jury': role,
    });
    return JuryMember.fromJson(ApiService.requireObject(data));
  }

  /// Retire le membre [memberId] de son jury.
  Future<void> deleteJuryMember(int memberId) =>
      api.delete('jury-members/$memberId/');
}
