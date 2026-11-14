import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SgTone { gold, success, warning, danger, info, neutral }

(Color, Color) sgTones(SgTone t) => switch (t) {
      SgTone.gold => (AppColors.gold, AppColors.goldSoft),
      SgTone.success => (AppColors.success, AppColors.successBg),
      SgTone.warning => (AppColors.warning, AppColors.warningBg),
      SgTone.danger => (AppColors.danger, AppColors.dangerBg),
      SgTone.info => (AppColors.info, AppColors.infoBg),
      SgTone.neutral => (AppColors.grey, AppColors.neutralBg),
    };

SgTone sgToneForStatus(String s) {
  final v = s.toLowerCase();
  if (v.contains('rejet') ||
      v.contains('refus') ||
      v.contains('indisponible')) {
    return SgTone.danger;
  }
  if (v.contains('conflit') || v.contains('annul')) return SgTone.danger;
  if (v.contains('confirm') ||
      v.contains('valid') ||
      v.contains('disponible')) {
    return SgTone.success;
  }
  if (v.contains('attente') || v.contains('occup') || v.contains('cours')) {
    return SgTone.warning;
  }
  return SgTone.neutral;
}

/// Badge de statut
class SgBadge extends StatelessWidget {
  const SgBadge(
    this.label, {
    super.key,
    this.tone = SgTone.neutral,
    this.icon,
    this.dot = true,
  });

  final String label;
  final SgTone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          if (dot) const SizedBox(width: 6),
          if (icon != null) Icon(icon, size: 12, color: fg),
          if (icon != null) const SizedBox(width: 4),
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

/// Carte de base
class SgCard extends StatelessWidget {
  const SgCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color = AppColors.white,
  });

  final Widget? child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppColors.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Carte statistique
class SgStatCard extends StatelessWidget {
  const SgStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = SgTone.gold,
    this.foot,
  });

  final String label;
  final String value;
  final IconData icon;
  final SgTone tone;
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = sgTones(tone);
    return SgCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: fg),
              ),
              const Spacer(),
              const Icon(Icons.more_horiz_rounded,
                  size: 18, color: AppColors.greyLight),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
          ),
          if (foot != null) ...[
            const SizedBox(height: 6),
            Text(
              foot!,
              style: TextStyle(
                  fontSize: 11, color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

/// Titre de section avec action
class SgSectionTitle extends StatelessWidget {
  const SgSectionTitle(this.title, {super.key, this.subtitle, this.action});

  final String title;
  final String? subtitle;
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
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.grey, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        // Null-aware element (Dart >= 3.8) : n'ajoute l'élément que si non null.
        ?action,
      ],
    );
  }
}

enum SgBtnVariant { primary, dark, outline, ghost, danger }

class SgButton extends StatelessWidget {
  const SgButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.variant = SgBtnVariant.primary,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SgBtnVariant variant;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      SgBtnVariant.primary => (AppColors.gold, AppColors.ink, null),
      SgBtnVariant.dark => (AppColors.ink, Colors.white, null),
      SgBtnVariant.outline => (Colors.white, AppColors.ink, AppColors.line),
      SgBtnVariant.ghost => (Colors.transparent, AppColors.grey, null),
      SgBtnVariant.danger => (AppColors.dangerBg, AppColors.danger, null),
    };
    final disabled = onPressed == null;

    return SizedBox(
      height: dense ? 34 : 42,
      width: expand ? double.infinity : null,
      child: Material(
        color: disabled ? AppColors.neutralBg : bg,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: border == null ? null : Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null)
                  Icon(icon,
                      size: dense ? 15 : 17,
                      color: disabled ? AppColors.greyLight : fg),
                if (icon != null) SizedBox(width: dense ? 6 : 8),
                Text(
                  label,
                  style: TextStyle(
                    color: disabled ? AppColors.greyLight : fg,
                    fontSize: dense ? 12 : 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
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

class SgIconBtn extends StatelessWidget {
  const SgIconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.tone = SgTone.neutral,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
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
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: fg),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class SgSearch extends StatelessWidget {
  const SgSearch({
    super.key,
    required this.onChanged,
    this.hint = 'Rechercher…',
    this.width,
  });

  final ValueChanged<String> onChanged;
  final String hint;
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
          prefixIcon: const Icon(Icons.search_rounded,
              size: 18, color: AppColors.greyLight),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 30),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.line),
          ),
        ),
      ),
    );
  }
}

/// Liste déroulante sobre (sans dépendre des APIs DropdownButtonFormField)
class SgSelect<T> extends StatelessWidget {
  const SgSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.width,
    this.height = 42,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final double? width;
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
          borderRadius: BorderRadius.circular(10),
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
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: AppColors.grey),
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

class SgChip extends StatelessWidget {
  const SgChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: selected ? AppColors.ink : AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected ? AppColors.gold : AppColors.grey),
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

class SgEmpty extends StatelessWidget {
  const SgEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
                color: AppColors.neutralBg, shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: AppColors.grey),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.grey, height: 1.5),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class SgAvatar extends StatelessWidget {
  const SgAvatar({
    super.key,
    required this.initials,
    this.size = 36,
    this.tone = SgTone.gold,
  });

  final String initials;
  final double size;
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

/// Paire libellé / valeur (fiches détail)
class SgKv extends StatelessWidget {
  const SgKv({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: .7,
            fontWeight: FontWeight.w700,
            color: AppColors.greyLight,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
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

class SgCol {
  const SgCol(this.label,
      {this.flex = 1, this.align = Alignment.centerLeft});
  final String label;
  final int flex;
  final Alignment align;
}

class SgTable extends StatelessWidget {
  const SgTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onTap,
    this.minWidth = 820,
  });

  final List<SgCol> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onTap;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final table = Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAFA),
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              for (final c in columns)
                Expanded(
                  flex: c.flex,
                  child: Align(
                    alignment: c.align,
                    child: Text(
                      c.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.grey,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++)
          Material(
            color: AppColors.white,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
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

class SgToast {
  static void show(BuildContext context, String message,
      {SgTone tone = SgTone.success}) {
    final (fg, _) = sgTones(tone);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              tone == SgTone.danger
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}