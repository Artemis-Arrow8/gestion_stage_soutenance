import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/document_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

String _fmtDate(String? raw) {
  if (raw == null || raw.length < 10) return raw ?? '';
  final p = raw.substring(0, 10).split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : raw.substring(0, 10);
}

String _labelStatut(String? s) {
  final v = (s ?? '').toLowerCase();
  if (v.contains('valid')) return 'Validé';
  if (v.contains('rejet') || v.contains('refus')) return 'Rejeté';
  return 'En attente';
}

SgTone _toneStatut(String? s) => switch (_labelStatut(s)) {
      'Validé' => SgTone.success,
      'Rejeté' => SgTone.danger,
      _ => SgTone.warning,
    };

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late DocumentService service;

  List<dynamic> folders = [];
  final Map<int, List<dynamic>> documents = {};

  bool loading = true;
  String? error;
  bool _initialise = false;
  bool _peutDonnerAvis = false;
  String _q = '';
  String _filtre = 'Tous';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    _initialise = true;

    final auth = context.read<AuthProvider>();
    service = DocumentService(accessToken: auth.accessToken);
    _peutDonnerAvis =
        const {'admin', 'responsible', 'supervisor'}.contains(auth.role);

    loadFolders();
  }

  Future<void> loadFolders() async {
    try {
      final result = await service.getFolders();
      if (!mounted) return;
      setState(() {
        folders = result;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> loadDocuments(int folderId) async {
    try {
      final result = await service.getDocuments(folderId);
      if (!mounted) return;
      setState(() => documents[folderId] = result);
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, e.toString(), tone: SgTone.danger);
    }
  }

  Future<void> upload(int folderId) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (file == null) return;

      final taille = (await file.length()) ?? 0;
      if (taille > 10 * 1024 * 1024) {
        throw Exception('Le fichier ne doit pas dépasser 10 Mo.');
      }

      await service.uploadDocument(folderId, file);
      documents.remove(folderId);
      await loadDocuments(folderId);
      if (!mounted) return;
      SgToast.show(context, 'Document envoyé avec succès.');
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, e.toString(), tone: SgTone.danger);
    }
  }

  Future<void> download(int documentId) async {
    try {
      final success = await service.downloadDocument(documentId);
      if (!mounted) return;
      if (success) SgToast.show(context, 'Téléchargement terminé.');
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, e.toString(), tone: SgTone.danger);
    }
  }

  void ouvrirAvis(int documentId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _AvisSheet(
        service: service,
        documentId: documentId,
        peutDonnerAvis: _peutDonnerAvis,
      ),
    );
  }

  List<dynamic> get _filtrees => folders.where((f) {
        final nom = (f['company_name'] ?? '').toString().toLowerCase();
        final sujet = (f['subject'] ?? '').toString().toLowerCase();
        if (_q.isNotEmpty && !nom.contains(_q) && !sujet.contains(_q)) {
          return false;
        }
        if (_filtre != 'Tous' &&
            _labelStatut(f['status']?.toString()) != _filtre) {
          return false;
        }
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.documents,
      title: 'Gestion documentaire',
      subtitle:
          'Dossiers de stage, versions des documents et avis des encadreurs.',
      actions: [
        SgButton('Actualiser',
            icon: Icons.refresh_rounded,
            variant: SgBtnVariant.outline,
            onPressed: () {
              setState(() => loading = true);
              loadFolders();
            }),
      ],
      child: _contenu(),
    );
  }

  Widget _contenu() {
    if (loading) {
      return const SgCard(
        child: SizedBox(
          height: 160,
          child:
              Center(child: CircularProgressIndicator(color: AppColors.gold)),
        ),
      );
    }

    if (error != null) {
      return SgEmpty(
        icon: Icons.cloud_off_outlined,
        title: 'Impossible de charger les dossiers',
        message: 'Vérifiez votre connexion puis réessayez.',
        action: SgButton('Réessayer', onPressed: () {
          setState(() {
            loading = true;
            error = null;
          });
          loadFolders();
        }),
      );
    }

    final visibles = _filtrees;
    final valides = folders
        .where((f) => _labelStatut(f['status']?.toString()) == 'Validé')
        .length;
    final attente = folders
        .where((f) => _labelStatut(f['status']?.toString()) == 'En attente')
        .length;
    final rejetes = folders
        .where((f) => _labelStatut(f['status']?.toString()) == 'Rejeté')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final n = c.maxWidth >= 1040 ? 4 : 2;
            final w = (c.maxWidth - (n - 1) * 12) / n;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                    width: w,
                    child: SgStatCard(
                        label: 'Dossiers de stage',
                        value: '${folders.length}',
                        icon: Icons.folder_open_rounded,
                        tone: SgTone.gold)),
                SizedBox(
                    width: w,
                    child: SgStatCard(
                        label: 'En attente',
                        value: '$attente',
                        icon: Icons.hourglass_top_rounded,
                        tone: SgTone.warning)),
                SizedBox(
                    width: w,
                    child: SgStatCard(
                        label: 'Validés',
                        value: '$valides',
                        icon: Icons.verified_outlined,
                        tone: SgTone.success)),
                SizedBox(
                    width: w,
                    child: SgStatCard(
                        label: 'Rejetés',
                        value: '$rejetes',
                        icon: Icons.cancel_outlined,
                        tone: SgTone.danger)),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SgCard(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SgSearch(
                  width: 240,
                  hint: 'Rechercher un dossier…',
                  onChanged: (v) => setState(() => _q = v)),
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
          const SgEmpty(
            icon: Icons.folder_open_outlined,
            title: 'Aucun dossier',
            message: 'Aucun dossier ne correspond à votre recherche.',
          )
        else
          for (final folder in visibles) _folderCard(folder),
      ],
    );
  }

  Widget _folderCard(dynamic folder) {
    final folderId = folder['id'] as int;
    final statut = folder['status']?.toString();
    final docs = documents[folderId];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.folder_open_rounded,
                size: 19, color: AppColors.gold),
          ),
          title: Text(
            folder['company_name']?.toString() ?? 'Entreprise inconnue',
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              'Dossier #$folderId'
              '${folder['subject'] != null ? ' · ${folder['subject']}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.grey),
            ),
          ),
          trailing: SgBadge(_labelStatut(statut), tone: _toneStatut(statut)),
          onExpansionChanged: (open) {
            if (open && !documents.containsKey(folderId)) {
              loadDocuments(folderId);
            }
          },
          children: [
            const Divider(),
            const SizedBox(height: 10),
            SgKv(
                label: 'Sujet',
                value: folder['subject']?.toString() ?? 'Non défini'),
            const SizedBox(height: 12),
            const Text('HISTORIQUE DES VERSIONS',
                style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.greyLight)),
            const SizedBox(height: 8),
            if (docs == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.gold),
                  ),
                ),
              )
            else if (docs.isEmpty)
              const Text('Aucun document déposé.',
                  style: TextStyle(fontSize: 12, color: AppColors.grey))
            else
              for (final document in docs) _docRow(document),
            const SizedBox(height: 14),
            SgButton('Ajouter un document PDF',
                icon: Icons.upload_file_rounded,
                expand: true,
                onPressed: () => upload(folderId)),
          ],
        ),
      ),
    );
  }

  Widget _docRow(dynamic document) {
    final documentId = document['id'] as int;
    final version = document['version_number']?.toString() ?? '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(7)),
            child: Text('V$version',
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rapport de stage (PDF)',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    'Déposé le '
                    '${_fmtDate(document['uploaded_at']?.toString())}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.grey)),
              ],
            ),
          ),
          SgIconBtn(
              icon: Icons.rate_review_outlined,
              tooltip: 'Voir les avis',
              tone: SgTone.info,
              onPressed: () => ouvrirAvis(documentId)),
          const SizedBox(width: 6),
          SgIconBtn(
              icon: Icons.download_rounded,
              tooltip: 'Télécharger',
              tone: SgTone.gold,
              onPressed: () => download(documentId)),
        ],
      ),
    );
  }
}

/// Panneau inférieur : consultation des avis + dépôt d'un avis
/// (dépôt réservé aux encadreurs, responsables et administrateurs).
class _AvisSheet extends StatefulWidget {
  const _AvisSheet({
    required this.service,
    required this.documentId,
    required this.peutDonnerAvis,
  });

  final DocumentService service;
  final int documentId;
  final bool peutDonnerAvis;

  @override
  State<_AvisSheet> createState() => _AvisSheetState();
}

class _AvisSheetState extends State<_AvisSheet> {
  late Future<List<dynamic>> _avisFuture;
  String? _decision;
  final TextEditingController _commentaires = TextEditingController();
  bool _envoiEnCours = false;

  @override
  void initState() {
    super.initState();
    _avisFuture = widget.service.getReviews(widget.documentId);
  }

  Future<void> _envoyerAvis() async {
    final decision = _decision;
    if (decision == null) {
      SgToast.show(context,
          'Choisissez une décision : favorable ou défavorable.',
          tone: SgTone.danger);
      return;
    }

    setState(() => _envoiEnCours = true);
    try {
      await widget.service.addReview(
          widget.documentId, decision, _commentaires.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      SgToast.show(context, 'Avis enregistré avec succès.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      SgToast.show(context, e.toString(), tone: SgTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                      borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.rate_review_rounded,
                      size: 17, color: AppColors.gold),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Avis sur ce document',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.ink)),
                ),
                SgIconBtn(
                    icon: Icons.close_rounded,
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: FutureBuilder<List<dynamic>>(
                future: _avisFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.gold)),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text('Erreur : ${snapshot.error}',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.danger));
                  }

                  final avis = snapshot.data ?? const [];
                  if (avis.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Aucun avis pour le moment.',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.grey)),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: avis.length,
                    itemBuilder: (context, index) {
                      final item = avis[index];
                      final favorable = item['decision'] == 'favorable';
                      final dateBrute =
                          _fmtDate(item['created_at']?.toString());

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              favorable
                                  ? Icons.thumb_up_alt_outlined
                                  : Icons.thumb_down_alt_outlined,
                              size: 16,
                              color: favorable
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['author_role'] ?? 'Auteur'} — '
                                    '${favorable ? 'favorable' : 'défavorable'}',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if ((item['comments'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(item['comments'].toString(),
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.grey,
                                            height: 1.4)),
                                  ],
                                ],
                              ),
                            ),
                            Text(dateBrute,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.greyLight)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (widget.peutDonnerAvis) ...[
              const Divider(),
              const SizedBox(height: 10),
              const Text('Donner un avis',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppColors.ink)),
              // Flutter >= 3.32 : le groupe est géré par un ancêtre RadioGroup.
              RadioGroup<String>(
                groupValue: _decision,
                onChanged: (valeur) => setState(() => _decision = valeur),
                child: Column(
                  children: const [
                    RadioListTile<String>(
                      value: 'favorable',
                      title: Text('Favorable (valider le document)',
                          style: TextStyle(fontSize: 13)),
                      activeColor: AppColors.success,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<String>(
                      value: 'defavorable',
                      title: Text('Défavorable (demander des corrections)',
                          style: TextStyle(fontSize: 13)),
                      activeColor: AppColors.danger,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              TextField(
                controller: _commentaires,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Commentaires (optionnel)',
                ),
              ),
              const SizedBox(height: 12),
              SgButton('Envoyer l’avis',
                  icon: Icons.send_rounded,
                  variant: SgBtnVariant.dark,
                  expand: true,
                  onPressed: _envoiEnCours ? null : _envoyerAvis),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentaires.dispose();
    super.dispose();
  }
}