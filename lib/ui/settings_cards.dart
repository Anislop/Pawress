import 'package:flutter/material.dart';

import 'theme.dart';

/// Rounded panels for settings screens, as in BooruPlus. Every change
/// applies as soon as it is made, so there is nothing to save.
const _radius = BorderRadius.all(Radius.circular(16));
const _tilePadding = EdgeInsets.symmetric(horizontal: 16);

/// The kicker and headline at the top of a settings screen.
class SettingsHeadline extends StatelessWidget {
  const SettingsHeadline({
    super.key,
    required this.kicker,
    required this.title,
  });

  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsSection(kicker),
      Text(
        title,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: -.7,
        ),
      ),
    ],
  );
}

/// A section heading, flush with the cards under it.
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: pawPink,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    ),
  );
}

/// One panel holding [children] (tiles), separated by hairlines.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: panel,
      borderRadius: _radius,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Divider(height: 1, indent: 56, color: hairline),
            child,
          ],
        ],
      ),
    ),
  );
}

/// A switch in its own panel.
class SettingsSwitchCard extends StatelessWidget {
  const SettingsSwitchCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingsGroup(
    children: [
      SettingsSwitch(
        icon: icon,
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: onChanged,
      ),
    ],
  );
}

/// A switch tile for use inside a [SettingsGroup].
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    value: value,
    onChanged: onChanged,
    secondary: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    contentPadding: _tilePadding,
  );
}

/// A tappable row for use inside a [SettingsGroup], or alone in a
/// [SettingsTileCard].
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: iconColor),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing:
        trailing ??
        (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
    onTap: onTap,
    contentPadding: _tilePadding,
  );
}

class SettingsTileCard extends StatelessWidget {
  const SettingsTileCard({super.key, required this.tile});

  final SettingsTile tile;

  @override
  Widget build(BuildContext context) => SettingsGroup(children: [tile]);
}

/// A setting with a few choices, as a button group with an explanation of
/// the current one underneath.
class SettingsChoiceCard<T> extends StatelessWidget {
  const SettingsChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.values,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.icons,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<T> values;
  final String Function(T) label;
  final T selected;

  /// Null disables the buttons.
  final ValueChanged<T>? onChanged;

  /// An icon per choice, if any.
  final IconData Function(T)? icons;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: panel, borderRadius: _radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ink(.8)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [
                for (final value in values)
                  ButtonSegment<T>(
                    value: value,
                    label: Text(label(value)),
                    icon: icons == null ? null : Icon(icons!(value), size: 16),
                  ),
              ],
              selected: {selected},
              onSelectionChanged: onChanged == null
                  ? null
                  : (choice) => onChanged!(choice.single),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: ink(.54), fontSize: 12, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

/// Explanatory text and buttons in a panel, like BooruPlus's backup card.
class SettingsActionsCard extends StatelessWidget {
  const SettingsActionsCard({
    super.key,
    required this.text,
    required this.actions,
  });

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: panel, borderRadius: _radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(color: ink(.54), fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    ),
  );
}

/// A highlighted notice card, e.g. when Android blocks notifications.
class SettingsWarningCard extends StatelessWidget {
  const SettingsWarningCard({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });

  final String title;
  final String body;
  final Widget? action;

  static const _amber = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _amber.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _amber.withValues(alpha: .45), width: 1.2),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: .18),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.notifications_off_outlined,
            color: _amber,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFFFFE0B2),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFD4B89B),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    ),
  );
}

/// The scrolling body every settings screen shares: centered, at most
/// 720 wide, with BooruPlus's margins.
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: children,
        ),
      ),
    ),
  );
}
