/// Bibliothèque de composants d'interface réutilisables (préfixe `Sg`).
///
/// Tous les écrans s'appuient sur ces briques pour garantir une identité
/// visuelle homogène : cartes à ombre douce, badges de statut, boutons,
/// champs de recherche et de sélection, tableaux adaptatifs, ainsi que des
/// états unifiés de chargement, d'erreur et de liste vide.
library;

import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';

// ===========================================================================
// Tonalités de couleur
// ===========================================================================

/// Tonalité sémantique d'un composant (badge, icône, bouton…).
enum SgTone { gold, success, warning, danger, info, neutral }

/// Retourne le couple (couleur de premier plan, couleur de fond) d'une [t].
(Color, Color) sgTones(SgTone t) => switch (t) {
  // Or foncé sur fond doré pâle : lisible même en petit texte.
  SgTone.gold => (AppColors.goldDeep, AppColors.goldSoft),
  SgTone.success => (AppColors.success, AppColors.successBg),
  SgTone.warning => (AppColors.warning, AppColors.warningBg),
  SgTone.danger => (AppColors.danger, AppColors.dangerBg),
  SgTone.info => (AppColors.info, AppColors.infoBg),
  SgTone.neutral => (AppColors.grey, AppColors.neutralBg),
};

/// Déduit la tonalité d'un statut métier à partir de son libellé.
///
/// Exemple : « rejeté » → danger, « validé » → succès, « en attente » →
/// avertissement ; tout autre statut est neutre.
SgTone sgToneForStatus(String s) {
  final v = s.toLowerCase();
  if (v.contains('rejet') ||
      v.contains('refus') ||
      v.contains('indisponible') ||
      v.contains('conflit') ||
      v.contains('annul') ||
      v.contains('defavorable') ||
      v.contains('défavorable')) {
    return SgTone.danger;
  }
  if (v.contains('confirm') ||
      v.contains('valid') ||
      v.contains('favorable') ||
      v.contains('disponible') ||
      v.contains('recevable')) {
    return SgTone.success;
  }
  if (v.contains('attente') ||
      v.contains('occup') ||
      v.contains('cours') ||
      v.contains('soumis') ||
      v.contains('corriger') ||
      v.contains('report') ||
      v.contains('remplac')) {
    return SgTone.warning;
  }
  if (v.contains('planifi')) return SgTone.info;
  if (v.contains('termin') || v.contains('publi')) return SgTone.gold;
  return SgTone.neutral;
}

/// Libellés lisibles des statuts techniques renvoyés par l'API.
///
/// L'API stocke des codes sans accent (`planifie`, `recevable`…) ; cette
/// table les traduit pour l'affichage. Un statut inconnu est affiché tel
/// quel, avec une majuscule initiale.
const Map<String, String> _libellesStatuts = {
  // Soutenances (proposée → confirmée → publiée → tenue ; reportée, annulée)
  'planifie': 'Proposée',
  'confirme': 'Confirmée',
  'publie': 'Publiée',
  'reporte': 'Reportée',
  'termine': 'Tenue',
  'annule': 'Annulée',
  // Dossiers de stage, en mots de tous les jours (une personne non formée
  // doit comprendre sans lexique) : brouillon → en attente d'avis →
  // à corriger | accepté → prêt pour la soutenance, ou refusé.
  'brouillon': 'Brouillon',
  'soumis': 'En attente d’avis',
  'a_corriger': 'À corriger',
  'recevable': 'Prêt pour la soutenance',
  'valide': 'Accepté',
  'rejete': 'Refusé',
  // Convocations et procès-verbaux
  'active': 'Active',
  'remplacee': 'Remplacée',
  'annulee': 'Annulée',
  'approuve': 'Approuvé',
  'remplace': 'Remplacé',
  // Avis d'encadrement
  'favorable': 'Favorable',
  'defavorable': 'Défavorable',
};

/// Retourne le libellé français d'un statut technique (ex. `planifie`).
String libelleStatut(String statut) {
  final cle = statut.trim().toLowerCase();
  final connu = _libellesStatuts[cle];
  if (connu != null) return connu;
  if (cle.isEmpty) return '—';
  return cle[0].toUpperCase() + cle.substring(1);
}

/// Badge de statut prêt à l'emploi : libellé français + couleur adaptée.
class SgStatusBadge extends StatelessWidget {
  /// Crée le badge du statut technique [statut].
  const SgStatusBadge(this.statut, {super.key});

  /// Statut technique tel que renvoyé par l'API.
  final String statut;

  @override
  Widget build(BuildContext context) =>
      SgBadge(libelleStatut(statut), tone: sgToneForStatus(statut));
}

// ===========================================================================
// Badges, cartes et indicateurs
// ===========================================================================

/// Pastille de statut colorée (ex. « Planifiée », « Validé »).
class SgBadge extends StatelessWidget {
  /// Crée un badge affichant [label].
  ///
  /// [dot] ajoute une puce colorée ; [icon] une petite icône.
  const SgBadge(
    this.label, {
    super.key,
    this.tone = SgTone.neutral,
    this.icon,
    this.dot = true,
  });

  /// Texte du badge.
  final String label;

  /// Tonalité de couleur.
  final SgTone tone;

  /// Icône optionnelle avant le texte.
  final IconData? icon;

  /// Affiche une puce colorée avant le texte.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte de base : fond blanc, coins arrondis, bordure fine et ombre douce.
class SgCard extends StatelessWidget {
  /// Crée une carte ; [onTap] la rend cliquable (effet d'encre).
  const SgCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color = AppColors.white,
  });

  /// Contenu de la carte.
  final Widget? child;

  /// Marge intérieure.
  final EdgeInsets padding;

  /// Action au clic (facultative).
  final VoidCallback? onTap;

  /// Couleur de fond.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppTheme.softShadow,
      ),
      child: Material(
        color: color,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: AppColors.line),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Carte d'indicateur chiffré (tableau de bord).
class SgStatCard extends StatelessWidget {
  /// Crée une carte affichant [value] sous [label], avec une [icon].
  const SgStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = SgTone.gold,
    this.foot,
  });

  /// Libellé de l'indicateur.
  final String label;

  /// Valeur affichée en grand.
  final String value;

  /// Icône illustrative.
  final IconData icon;

  /// Tonalité de l'icône et du pied de carte.
  final SgTone tone;

  /// Texte complémentaire facultatif (ex. « action requise »).
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    return SgCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          // Pastille d'icône colorée.
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: fg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.1,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
                if (foot != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    foot!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Titre de section, avec sous-titre et action facultatifs à droite.
class SgSectionTitle extends StatelessWidget {
  /// Crée un titre de section.
  const SgSectionTitle(this.title, {super.key, this.subtitle, this.action});

  /// Titre principal.
  final String title;

  /// Phrase explicative facultative.
  final String? subtitle;

  /// Widget aligné à droite (ex. bouton « Tout voir »).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.grey,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Élément conditionnel (Dart ≥ 3.8) : ajouté seulement s'il existe.
        ?action,
      ],
    );
  }
}

/// Petit libellé en capitales utilisé comme en-tête de bloc dans les cartes.
class SgOverline extends StatelessWidget {
  /// Crée un sur-titre affichant [text] en majuscules.
  const SgOverline(this.text, {super.key});

  /// Texte du sur-titre.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: .9,
        fontWeight: FontWeight.w700,
        color: AppColors.greyLight,
      ),
    );
  }
}

// ===========================================================================
// Boutons et contrôles
// ===========================================================================

/// Variantes visuelles de [SgButton].
enum SgBtnVariant {
  /// Action principale : fond or, texte encre.
  primary,

  /// Action forte sur fond clair : fond encre, texte blanc.
  dark,

  /// Action secondaire : contour fin.
  outline,

  /// Action discrète : texte seul.
  ghost,

  /// Action destructrice : fond rouge pâle, texte rouge.
  danger,
}

/// Bouton maison aux variantes de la charte.
class SgButton extends StatelessWidget {
  /// Crée un bouton affichant [label].
  ///
  /// [onPressed] à `null` désactive le bouton ; [loading] affiche un
  /// indicateur de progression et bloque les clics ; [expand] occupe toute
  /// la largeur disponible ; [dense] réduit la hauteur.
  const SgButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.variant = SgBtnVariant.primary,
    this.expand = false,
    this.dense = false,
    this.loading = false,
  });

  /// Texte du bouton.
  final String label;

  /// Action au clic.
  final VoidCallback? onPressed;

  /// Icône facultative avant le texte.
  final IconData? icon;

  /// Variante visuelle.
  final SgBtnVariant variant;

  /// Occupe toute la largeur.
  final bool expand;

  /// Version compacte.
  final bool dense;

  /// Affiche un indicateur de chargement à la place de l'icône.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // Couleurs (fond, texte, bordure) de chaque variante.
    final (bg, fg, border) = switch (variant) {
      SgBtnVariant.primary => (AppColors.gold, AppColors.ink, null),
      SgBtnVariant.dark => (AppColors.ink, Colors.white, null),
      SgBtnVariant.outline => (Colors.white, AppColors.ink, AppColors.line),
      SgBtnVariant.ghost => (Colors.transparent, AppColors.grey, null),
      SgBtnVariant.danger => (AppColors.dangerBg, AppColors.danger, null),
    };
    final disabled = onPressed == null || loading;
    final color = disabled && !loading ? AppColors.greyLight : fg;

    return SizedBox(
      height: dense ? 34 : 44,
      width: expand ? double.infinity : null,
      child: Material(
        color: disabled && !loading ? AppColors.neutralBg : bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: border == null ? null : Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: dense ? 14 : 16,
                    height: dense ? 14 : 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: dense ? 15 : 17, color: color),
                if (loading || icon != null) SizedBox(width: dense ? 6 : 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: dense ? 12 : 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton carré ne contenant qu'une icône (avec infobulle facultative).
class SgIconBtn extends StatelessWidget {
  /// Crée un bouton-icône.
  const SgIconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.tone = SgTone.neutral,
  });

  /// Icône affichée.
  final IconData icon;

  /// Action au clic.
  final VoidCallback? onPressed;

  /// Texte d'infobulle (aussi utilisé par les lecteurs d'écran).
  final String? tooltip;

  /// Tonalité de couleur.
  final SgTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    final btn = Material(
      color: bg,
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 17, color: fg),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Champ de recherche compact avec icône loupe.
class SgSearch extends StatelessWidget {
  /// Crée un champ de recherche ; [onChanged] reçoit chaque saisie.
  const SgSearch({
    super.key,
    required this.onChanged,
    this.hint = 'Rechercher…',
    this.width,
  });

  /// Rappel à chaque modification du texte.
  final ValueChanged<String> onChanged;

  /// Texte indicatif.
  final String hint;

  /// Largeur fixe facultative.
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 42,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.greyLight,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 30,
          ),
        ),
      ),
    );
  }
}

/// Liste déroulante sobre, au style des champs de l'application.
class SgSelect<T> extends StatelessWidget {
  /// Crée une liste déroulante.
  const SgSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.width,
    this.height = 42,
  });

  /// Valeur sélectionnée.
  final T value;

  /// Options proposées.
  final List<DropdownMenuItem<T>> items;

  /// Rappel lors d'un changement de sélection.
  final ValueChanged<T?> onChanged;

  /// Icône facultative à gauche.
  final IconData? icon;

  /// Largeur fixe facultative.
  final double? width;

  /// Hauteur du champ.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.greyLight),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(12),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.grey,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Puce sélectionnable (filtres, choix de vue).
class SgChip extends StatelessWidget {
  /// Crée une puce.
  const SgChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  /// Texte de la puce.
  final String label;

  /// Vrai si la puce est active.
  final bool selected;

  /// Action au clic.
  final VoidCallback? onTap;

  /// Icône facultative.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.white,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? AppColors.gold : AppColors.grey,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille ronde aux initiales d'une personne.
class SgAvatar extends StatelessWidget {
  /// Crée un avatar affichant [initials].
  const SgAvatar({
    super.key,
    required this.initials,
    this.size = 36,
    this.tone = SgTone.gold,
  });

  /// Initiales (1 ou 2 lettres).
  final String initials;

  /// Diamètre en pixels logiques.
  final double size;

  /// Tonalité de couleur.
  final SgTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: fg,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Paire libellé / valeur des fiches de détail.
class SgKv extends StatelessWidget {
  /// Crée une paire « [label] : [value] ».
  const SgKv({super.key, required this.label, required this.value});

  /// Libellé (affiché en petites capitales).
  final String label;

  /// Valeur affichée en gras.
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SgOverline(label),
        const SizedBox(height: 5),
        Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Tableau adaptatif
// ===========================================================================

/// Définition d'une colonne de [SgTable].
class SgCol {
  /// Crée une colonne de titre [label], de largeur relative [flex].
  const SgCol(this.label, {this.flex = 1, this.align = Alignment.centerLeft});

  /// Titre de la colonne.
  final String label;

  /// Largeur relative (comme `Expanded.flex`).
  final int flex;

  /// Alignement du contenu.
  final Alignment align;
}

/// Tableau simple : défilement horizontal sur les petits écrans afin de
/// conserver des colonnes lisibles (largeur minimale [minWidth]).
class SgTable extends StatelessWidget {
  /// Crée un tableau.
  const SgTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onTap,
    this.minWidth = 820,
  });

  /// Colonnes du tableau.
  final List<SgCol> columns;

  /// Lignes : une liste de widgets par ligne, dans l'ordre des colonnes.
  final List<List<Widget>> rows;

  /// Action au clic sur une ligne (reçoit son index).
  final void Function(int index)? onTap;

  /// Largeur minimale avant défilement horizontal.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final table = Column(
      children: [
        // En-tête des colonnes.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              for (final c in columns)
                Expanded(
                  flex: c.flex,
                  child: Align(alignment: c.align, child: SgOverline(c.label)),
                ),
            ],
          ),
        ),
        // Lignes de données.
        for (var i = 0; i < rows.length; i++)
          Material(
            color: AppColors.white,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  border: i == rows.length - 1
                      ? null
                      : const Border(
                          bottom: BorderSide(color: AppColors.line),
                        ),
                ),
                child: Row(
                  children: [
                    for (var j = 0; j < columns.length; j++)
                      Expanded(
                        flex: columns[j].flex,
                        child: Align(
                          alignment: columns[j].align,
                          child: j < rows[i].length
                              ? rows[i][j]
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: c.maxWidth > minWidth ? c.maxWidth : minWidth,
          child: table,
        ),
      ),
    );
  }
}

// ===========================================================================
// États : chargement, erreur, vide, alerte
// ===========================================================================

/// Indicateur de chargement centré, avec message facultatif.
class SgLoading extends StatelessWidget {
  /// Crée un indicateur de chargement.
  const SgLoading({super.key, this.message});

  /// Texte affiché sous l'indicateur.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bloc d'état neutre : liste vide, aucun résultat, etc.
class SgEmpty extends StatelessWidget {
  /// Crée un état vide.
  const SgEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = SgTone.neutral,
  });

  /// Icône illustrative.
  final IconData icon;

  /// Titre court.
  final String title;

  /// Explication facultative.
  final String? message;

  /// Bouton d'action facultatif.
  final Widget? action;

  /// Tonalité de l'icône.
  final SgTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    return SgCard(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: fg),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.grey,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Bloc d'erreur explicite, avec bouton « Réessayer » facultatif.
class SgErrorState extends StatelessWidget {
  /// Crée un état d'erreur affichant [message].
  const SgErrorState({
    super.key,
    required this.message,
    this.title = 'Un problème est survenu',
    this.onRetry,
  });

  /// Titre de l'erreur.
  final String title;

  /// Détail lisible (souvent le message de l'API).
  final String message;

  /// Action de nouvelle tentative (bouton masqué si `null`).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SgEmpty(
      icon: Icons.cloud_off_rounded,
      tone: SgTone.danger,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : SgButton(
              'Réessayer',
              icon: Icons.refresh_rounded,
              variant: SgBtnVariant.outline,
              onPressed: onRetry,
            ),
    );
  }
}

/// Bandeau d'alerte en ligne (information, avertissement, erreur…).
class SgBanner extends StatelessWidget {
  /// Crée un bandeau affichant [message].
  const SgBanner({
    super.key,
    required this.message,
    this.tone = SgTone.info,
    this.icon,
    this.onClose,
  });

  /// Texte du bandeau.
  final String message;

  /// Tonalité de couleur.
  final SgTone tone;

  /// Icône ; par défaut, choisie selon la tonalité.
  final IconData? icon;

  /// Affiche une croix de fermeture si renseigné.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    final defaultIcon = switch (tone) {
      SgTone.danger => Icons.error_outline_rounded,
      SgTone.warning => Icons.warning_amber_rounded,
      SgTone.success => Icons.check_circle_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              // Texte foncé sur fond pâle : contraste suffisant (accessibilité).
              style: TextStyle(color: fg, fontSize: 13, height: 1.4),
            ),
          ),
          if (onClose != null)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 16, color: fg),
              ),
            ),
        ],
      ),
    );
  }
}

/// Notifications éphémères (« toasts ») en bas de l'écran.
abstract final class SgToast {
  /// Affiche [message] ; la [tone] choisit l'icône (succès, erreur…).
  static void show(
    BuildContext context,
    String message, {
    SgTone tone = SgTone.success,
  }) {
    // Le toast a un fond encre : on utilise des teintes claires, lisibles
    // sur fond sombre, plutôt que les couleurs sémantiques standard.
    final iconColor = switch (tone) {
      SgTone.success => const Color(0xFF4ADE80),
      SgTone.danger => const Color(0xFFF87171),
      SgTone.warning => const Color(0xFFFBBF24),
      SgTone.info => const Color(0xFF93C5FD),
      SgTone.gold => AppColors.gold,
      SgTone.neutral => Colors.white,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              tone == SgTone.danger
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Formulaire protégé contre le geste « retour »
// ===========================================================================

/// Formulaire qui protège la saisie contre un geste « retour » accidentel.
///
/// S'utilise à la place de [Form] (avec `formKey:` au lieu de `key:`).
/// * Tant que rien n'a été saisi, le geste « retour » (glissement depuis le
///   bord de l'écran sur Samsung/Android, bouton retour du navigateur,
///   toucher en dehors d'une boîte de dialogue) ferme l'écran normalement.
/// * Dès qu'un champ a été modifié, le même geste ouvre la question
///   « Quitter sans enregistrer ? » au lieu de fermer : un léger glissement
///   involontaire ne fait plus perdre ce qui a été tapé.
/// Les boutons « Annuler » et « Enregistrer », qui ferment explicitement
/// l'écran avec `Navigator.pop`, ne sont pas concernés.
class SgFormulaire extends StatefulWidget {
  /// Crée un formulaire protégé.
  const SgFormulaire({super.key, required this.formKey, required this.child});

  /// Clé du [Form] interne (validation : `formKey.currentState!.validate()`).
  final GlobalKey<FormState> formKey;

  /// Champs du formulaire.
  final Widget child;

  /// Indique que la saisie a été enregistrée alors que le formulaire reste
  /// affiché (ex. changement de mot de passe) : le geste « retour » ferme de
  /// nouveau l'écran sans poser de question.
  ///
  /// À appeler APRÈS avoir vidé les champs, car vider un champ compte
  /// comme une modification.
  static void marquerEnregistre(GlobalKey<FormState> formKey) {
    formKey.currentContext
        ?.findAncestorStateOfType<_SgFormulaireState>()
        ?._reinitialiser();
  }

  @override
  State<SgFormulaire> createState() => _SgFormulaireState();
}

/// État du formulaire protégé : mémorise si une saisie est en cours.
class _SgFormulaireState extends State<SgFormulaire> {
  /// Vrai dès qu'un champ a été modifié depuis l'ouverture.
  bool _modifie = false;

  /// Appelé par le [Form] à chaque modification d'un champ.
  void _marquerModifie() {
    if (!_modifie) setState(() => _modifie = true);
  }

  /// Revient à l'état « rien à enregistrer ».
  void _reinitialiser() {
    if (_modifie) setState(() => _modifie = false);
  }

  /// Demande confirmation, puis ferme l'écran si l'utilisateur le veut.
  Future<void> _confirmerSortie() async {
    final quitter = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter sans enregistrer ?'),
        content: const Text(
          'Les informations que vous avez saisies seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuer la saisie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    // `Navigator.pop` ferme l'écran sans repasser par la garde.
    if (quitter == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Fermeture libre tant que rien n'a été saisi.
      canPop: !_modifie,
      onPopInvokedWithResult: (didPop, _) {
        // Geste bloqué car une saisie est en cours : on demande.
        if (!didPop) _confirmerSortie();
      },
      child: Form(
        key: widget.formKey,
        onChanged: _marquerModifie,
        child: widget.child,
      ),
    );
  }
}
