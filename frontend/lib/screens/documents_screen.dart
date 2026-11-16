/// Gestion documentaire : dossiers de stage, versions des rapports PDF et
/// avis des encadreurs.
///
/// Le contenu visible dépend du rôle (filtré par le serveur) :
/// * étudiant : ses dossiers, dépôt de nouvelles versions ;
/// * encadreur : dossiers affectés, consultation et avis ;
/// * personnel : tous les dossiers, dépôt et avis (administrateur).
library;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/document_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Taille maximale d'un PDF déposé (identique à la limite du serveur).
const _tailleMaxPdf = 10 * 1024 * 1024;

/// Formate une date ISO (`2026-07-10T…`) en `10/07/2026`.
String _fmtDate(String? raw) {
  if (raw == null || raw.length < 10) return raw ?? '';
  final p = raw.substring(0, 10).split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : raw.substring(0, 10);
}

/// Regroupe les statuts techniques d'un dossier en trois libellés lisibles.
String _labelStatut(String? s) {
  final v = (s ?? '').toLowerCase();
  if (v.contains('valid') || v.contains('recevable')) return 'Validé';
  if (v.contains('rejet') || v.contains('refus')) return 'Rejeté';
  return 'En attente';
}

/// Tonalité associée au libellé de statut.
SgTone _toneStatut(String? s) => switch (_labelStatut(s)) {
  'Validé' => SgTone.success,
  'Rejeté' => SgTone.danger,
  _ => SgTone.warning,
};

/// Message lisible d'une erreur quelconque.
String _message(Object e) => switch (e) {
  ApiException(:final message) => message,
  FormatException(:final message) => message,
  _ => 'Une erreur inattendue est survenue.',
};

/// Écran de gestion documentaire.
class DocumentsScreen extends StatefulWidget {
  /// Crée l'écran.
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

/// État de l'écran : dossiers, versions chargées à la demande, filtres.
class _DocumentsScreenState extends State<DocumentsScreen> {
  late final DocumentService _service;
  late final bool _peutTeleverser;
  late final bool _peutDonnerAvis;

  /// Dossiers visibles par le compte.
  List<Map<String, dynamic>> _folders = [];

  /// Versions de documents, chargées à l'ouverture de chaque dossier.
  final Map<int, List<Map<String, dynamic>>> _documents = {};

  /// Dossier en cours de dépôt (affiche un indicateur sur son bouton).
  int? _uploadingFolder;

  bool _loading = true;
  String? _error;

  /// Texte de recherche (entreprise ou sujet).
  String _q = '';

  /// Filtre de statut actif.
  String _filtre = 'Tous';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = DocumentService(auth.api);
    _peutTeleverser = const {
      'admin',
      'responsible',
      'student',
    }.contains(auth.role);
    _peutDonnerAvis = const {'admin', 'supervisor'}.contains(auth.role);
    _loadFolders();
  }

  /// Charge (ou recharge) la liste des dossiers.
  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.getFolders();
      if (!mounted) return;
      setState(() {
        _folders = result;
        // Les versions seront rechargées à la prochaine ouverture.
        _documents.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  /// Charge les versions du dossier [folderId].
  Future<void> _loadDocuments(int folderId) async {
    try {
      final result = await _service.getDocuments(folderId);
      if (!mounted) return;
      setState(() => _documents[folderId] = result);
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, _message(e), tone: SgTone.danger);
    }
  }

  /// Sélectionne un PDF, vérifie sa taille puis le dépose dans [folderId].
  Future<void> _upload(int folderId) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (file == null) return;

      // Contrôle précoce (le serveur vérifie aussi taille et signature).
      final taille = (await file.length()) ?? 0;
      if (taille > _tailleMaxPdf) {
        if (mounted) {
          SgToast.show(
            context,
            'Le fichier ne doit pas dépasser 10 Mo.',
            tone: SgTone.danger,
          );
        }
        return;
      }

      setState(() => _uploadingFolder = folderId);
      await _service.uploadDocument(folderId, file);
      await _loadDocuments(folderId);
      if (!mounted) return;
      SgToast.show(context, 'Document envoyé avec succès.');
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, _message(e), tone: SgTone.danger);
    } finally {
      if (mounted) setState(() => _uploadingFolder = null);
    }
  }

  /// Télécharge le document [documentId].
  Future<void> _download(int documentId) async {
    try {
      final success = await _service.downloadDocument(documentId);
      if (!mounted) return;
      if (success) SgToast.show(context, 'Téléchargement terminé.');
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, _message(e), tone: SgTone.danger);
    }
  }

  /// Ouvre le panneau des avis du document [documentId].
  void _ouvrirAvis(int documentId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AvisSheet(
        service: _service,
        documentId: documentId,
        peutDonnerAvis: _peutDonnerAvis,
      ),
    );
  }

  /// Dossiers correspondant à la recherche et au filtre de statut.
  List<Map<String, dynamic>> get _filtrees {
    final q = _q.toLowerCase();
    return _folders.where((f) {
      final nom = (f['company_name'] ?? '').toString().toLowerCase();
      final sujet = (f['subject'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty && !nom.contains(q) && !sujet.contains(q)) {
        return false;
      }
      return _filtre == 'Tous' ||
          _labelStatut(f['status']?.toString()) == _filtre;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.documents,
      title: 'Gestion documentaire',
      subtitle:
          'Dossiers de stage, versions des documents et avis des encadreurs.',
      onRefresh: _loadFolders,
      actions: [
        SgButton(
          'Actualiser',
          icon: Icons.refresh_rounded,
          variant: SgBtnVariant.outline,
          onPressed: _loadFolders,
        ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des dossiers…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les dossiers',
              message: _error!,
              onRetry: _loadFolders,
            )
          : _contenu(),
    );
  }

  /// Indicateurs, filtres puis liste des dossiers.
  Widget _contenu() {
    final visibles = _filtrees;
    int compte(String label) => _folders
        .where((f) => _labelStatut(f['status']?.toString()) == label)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final perRow = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 440 ? 2 : 1);
            final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
            final cards = [
              SgStatCard(
                label: 'Dossiers de stage',
                value: '${_folders.length}',
                icon: Icons.folder_open_rounded,
              ),
              SgStatCard(
                label: 'En attente',
                value: '${compte('En attente')}',
                icon: Icons.hourglass_top_rounded,
                tone: SgTone.warning,
              ),
              SgStatCard(
                label: 'Validés',
                value: '${compte('Validé')}',
                icon: Icons.verified_outlined,
                tone: SgTone.success,
              ),
              SgStatCard(
                label: 'Rejetés',
                value: '${compte('Rejeté')}',
                icon: Icons.cancel_outlined,
                tone: SgTone.danger,
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final card in cards) SizedBox(width: w, child: card)],
            );
          },
        ),
        const SizedBox(height: 20),
        SgCard(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SgSearch(
                width: 260,
                hint: 'Entreprise ou sujet…',
                onChanged: (v) => setState(() => _q = v),
              ),
              for (final s in ['Tous', 'En attente', 'Validé', 'Rejeté'])
                SgChip(
                  label: s,
                  selected: _filtre == s,
                  onTap: () => setState(() => _filtre = s),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (visibles.isEmpty)
          SgEmpty(
            icon: Icons.folder_open_outlined,
            title: _folders.isEmpty ? 'Aucun dossier' : 'Aucun résultat',
            message: _folders.isEmpty
                ? 'Aucun dossier de stage ne vous est encore accessible.'
                : 'Aucun dossier ne correspond à votre recherche.',
          )
        else
          for (final folder in visibles) _folderCard(folder),
      ],
    );
  }

  /// Carte dépliable d'un dossier : sujet, versions et dépôt.
  Widget _folderCard(Map<String, dynamic> folder) {
    final folderId = int.tryParse(folder['id']?.toString() ?? '') ?? 0;
    final statut = folder['status']?.toString();
    final docs = _documents[folderId];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SgCard(
        padding: EdgeInsets.zero,
        child: Theme(
          // Supprime les séparateurs par défaut de l'ExpansionTile.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 21,
                color: AppColors.gold,
              ),
            ),
            title: Text(
              folder['company_name']?.toString() ?? 'Entreprise inconnue',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Dossier #$folderId'
                '${folder['subject'] != null ? ' · ${folder['subject']}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.grey),
              ),
            ),
            trailing: SgBadge(_labelStatut(statut), tone: _toneStatut(statut)),
            // Chargement paresseux : versions récupérées à la 1re ouverture.
            onExpansionChanged: (open) {
              if (open && !_documents.containsKey(folderId)) {
                _loadDocuments(folderId);
              }
            },
            children: [
              const Divider(),
              const SizedBox(height: 12),
              SgKv(
                label: 'Sujet',
                value: folder['subject']?.toString() ?? 'Non défini',
              ),
              const SizedBox(height: 16),
              const SgOverline('Historique des versions'),
              const SizedBox(height: 10),
              if (docs == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                )
              else if (docs.isEmpty)
                const Text(
                  'Aucun document déposé.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                )
              else
                // Version la plus récente en premier.
                for (final document in docs.reversed) _docRow(document),
              if (_peutTeleverser) ...[
                const SizedBox(height: 14),
                SgButton(
                  'Déposer une nouvelle version (PDF, 10 Mo max.)',
                  icon: Icons.upload_file_rounded,
                  variant: SgBtnVariant.dark,
                  expand: true,
                  loading: _uploadingFolder == folderId,
                  onPressed: () => _upload(folderId),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Ligne d'une version de document : numéro, date et actions.
  Widget _docRow(Map<String, dynamic> document) {
    final documentId = int.tryParse(document['id']?.toString() ?? '') ?? 0;
    final version = document['version_number']?.toString() ?? '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          // Étiquette de version « V1, V2… ».
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'V$version',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rapport de stage (PDF)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Déposé le ${_fmtDate(document['uploaded_at']?.toString())}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          SgIconBtn(
            icon: Icons.rate_review_outlined,
            tooltip: 'Voir les avis',
            tone: SgTone.info,
            onPressed: () => _ouvrirAvis(documentId),
          ),
          const SizedBox(width: 6),
          SgIconBtn(
            icon: Icons.download_rounded,
            tooltip: 'Télécharger',
            tone: SgTone.gold,
            onPressed: () => _download(documentId),
          ),
        ],
      ),
    );
  }
}

/// Panneau inférieur : consultation des avis et dépôt d'un nouvel avis
/// (dépôt réservé aux encadreurs et administrateurs).
class _AvisSheet extends StatefulWidget {
  const _AvisSheet({
    required this.service,
    required this.documentId,
    required this.peutDonnerAvis,
  });

  /// Service documentaire.
  final DocumentService service;

  /// Version de document concernée.
  final int documentId;

  /// Vrai si le formulaire d'avis doit être proposé.
  final bool peutDonnerAvis;

  @override
  State<_AvisSheet> createState() => _AvisSheetState();
}

/// État du panneau des avis.
class _AvisSheetState extends State<_AvisSheet> {
  /// Chargement des avis existants.
  late Future<List<Map<String, dynamic>>> _avisFuture;

  /// Décision choisie : `favorable` ou `defavorable`.
  String? _decision;

  /// Commentaires facultatifs.
  final TextEditingController _commentaires = TextEditingController();

  /// Vrai pendant l'envoi.
  bool _envoiEnCours = false;

  @override
  void initState() {
    super.initState();
    _avisFuture = widget.service.getReviews(widget.documentId);
  }

  @override
  void dispose() {
    _commentaires.dispose();
    super.dispose();
  }

  /// Envoie l'avis saisi puis ferme le panneau.
  Future<void> _envoyerAvis() async {
    final decision = _decision;
    if (decision == null) {
      SgToast.show(
        context,
        'Choisissez une décision : favorable ou défavorable.',
        tone: SgTone.danger,
      );
      return;
    }

    setState(() => _envoiEnCours = true);
    // Messager capturé avant la fermeture du panneau : après `pop`, le
    // contexte du panneau n'est plus utilisable pour afficher un toast.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.service.addReview(
        widget.documentId,
        decision,
        _commentaires.text,
      );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Avis enregistré avec succès.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      SgToast.show(context, _message(e), tone: SgTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Le clavier virtuel repousse le contenu vers le haut.
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.goldSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.rate_review_rounded,
                    size: 18,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Avis sur ce document',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                SgIconBtn(
                  icon: Icons.close_rounded,
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _avisFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SgLoading();
                  }
                  if (snapshot.hasError) {
                    return SgBanner(
                      message: _message(snapshot.error!),
                      tone: SgTone.danger,
                    );
                  }

                  final avis = snapshot.data ?? const [];
                  if (avis.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Aucun avis pour le moment.',
                        style: TextStyle(fontSize: 13, color: AppColors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: avis.length,
                    itemBuilder: (context, index) => _avisTile(avis[index]),
                  );
                },
              ),
            ),
            if (widget.peutDonnerAvis) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Donner un avis',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              // Le groupe de boutons radio est géré par un RadioGroup ancêtre.
              RadioGroup<String>(
                groupValue: _decision,
                onChanged: (valeur) => setState(() => _decision = valeur),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      value: 'favorable',
                      title: Text(
                        'Favorable (valider le document)',
                        style: TextStyle(fontSize: 13),
                      ),
                      activeColor: AppColors.success,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<String>(
                      value: 'defavorable',
                      title: Text(
                        'Défavorable (demander des corrections)',
                        style: TextStyle(fontSize: 13),
                      ),
                      activeColor: AppColors.danger,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              TextField(
                controller: _commentaires,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Commentaires (facultatif)',
                ),
              ),
              const SizedBox(height: 14),
              SgButton(
                'Envoyer l’avis',
                icon: Icons.send_rounded,
                variant: SgBtnVariant.dark,
                expand: true,
                loading: _envoiEnCours,
                onPressed: _envoyerAvis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ligne d'un avis : décision, auteur, commentaire et date.
  Widget _avisTile(Map<String, dynamic> item) {
    final favorable = item['decision'] == 'favorable';
    final commentaire = (item['comments'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: favorable ? AppColors.successBg : AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            favorable
                ? Icons.thumb_up_alt_outlined
                : Icons.thumb_down_alt_outlined,
            size: 17,
            color: favorable ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['author_role'] ?? 'Auteur'} — '
                  '${favorable ? 'favorable' : 'défavorable'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (commentaire.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    commentaire,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            _fmtDate(item['created_at']?.toString()),
            style: const TextStyle(fontSize: 11, color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}
