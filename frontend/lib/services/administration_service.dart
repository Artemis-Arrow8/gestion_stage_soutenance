/// Accès aux routes d'administration : campagnes, comptes, étudiants et
/// membres de jury.
library;

import '../core/network/api_service.dart';
import '../models/administration.dart';

/// Service des écrans « Campagnes » et « Comptes ».
///
/// Toutes les requêtes passent par le client authentifié [ApiService]
/// fourni par `AuthProvider` (jeton et renouvellement automatiques).
class AdministrationService {
  /// Crée le service à partir du client HTTP authentifié [api].
  AdministrationService(this.api);

  /// Client HTTP authentifié partagé.
  final ApiService api;

  /// Liste les campagnes académiques.
  Future<List<CampaignRecord>> loadCampaigns() async {
    return (await api.getList('campaigns/'))
        .map(CampaignRecord.fromJson)
        .toList();
  }

  /// Liste les comptes utilisateurs (réservé aux administrateurs).
  Future<List<AccountRecord>> loadAccounts() async {
    return (await api.getList('accounts/'))
        .map(AccountRecord.fromJson)
        .toList();
  }

  /// Liste les fiches étudiantes, pour lier un compte étudiant.
  Future<List<StudentOption>> loadStudents() async {
    return (await api.getList('students/'))
        .map(StudentOption.fromJson)
        .toList();
  }

  /// Liste les membres de jury, pour lier un compte jury.
  Future<List<JuryMemberOption>> loadJuryMembers() async {
    return (await api.getList('jury-members/'))
        .map(JuryMemberOption.fromJson)
        .toList();
  }

  /// Crée une campagne et retourne la version enregistrée par le serveur.
  Future<CampaignRecord> createCampaign({
    required String academicYear,
    required bool isActive,
  }) async {
    final data = await api.post('campaigns/', {
      'academic_year': academicYear,
      'is_active': isActive,
    });
    return CampaignRecord.fromJson(ApiService.requireObject(data));
  }

  /// Modifie la campagne [id] et retourne sa nouvelle version.
  Future<CampaignRecord> updateCampaign(
    int id, {
    required String academicYear,
    required bool isActive,
  }) async {
    final data = await api.patch('campaigns/$id/', {
      'academic_year': academicYear,
      'is_active': isActive,
    });
    return CampaignRecord.fromJson(ApiService.requireObject(data));
  }

  /// Crée un compte à partir des champs saisis ([account]).
  ///
  /// Le serveur valide le rôle, la liaison étudiant/jury et le mot de passe.
  Future<AccountRecord> createAccount(Map<String, dynamic> account) async {
    final data = await api.post('accounts/', account);
    return AccountRecord.fromJson(ApiService.requireObject(data));
  }

  /// Applique les modifications [changes] au compte [id].
  Future<AccountRecord> updateAccount(
    int id,
    Map<String, dynamic> changes,
  ) async {
    final data = await api.patch('accounts/$id/', changes);
    return AccountRecord.fromJson(ApiService.requireObject(data));
  }

  /// Crée une fiche étudiante.
  Future<StudentOption> createStudent({
    required String studentNumber,
    required String fullName,
    required String email,
  }) async {
    final data = await api.post('students/', {
      'student_number': studentNumber,
      'full_name': fullName,
      'email': email,
    });
    return StudentOption.fromJson(ApiService.requireObject(data));
  }
}
