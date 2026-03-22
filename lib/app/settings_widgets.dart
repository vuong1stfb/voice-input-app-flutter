import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'app_state.dart';

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.title,
    required this.detail,
    required this.tone,
  });

  final String title;
  final String detail;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, border, titleColor, detailColor) = switch (tone) {
      AppStatusTone.calm => (
        AppColors.readySoft,
        const Color(0xFFBCD4CA),
        AppColors.ready,
        const Color(0xFF4B665E),
      ),
      AppStatusTone.active => (
        AppColors.activeSoft,
        const Color(0xFFC2D4E4),
        AppColors.active,
        const Color(0xFF587287),
      ),
      AppStatusTone.warning => (
        AppColors.warningSoft,
        const Color(0xFFE4CAA9),
        const Color(0xFF845018),
        const Color(0xFF856544),
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Text(
              'Status',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: detailColor),
          ),
        ],
      ),
    );
  }
}

class AdvancedSection extends StatelessWidget {
  const AdvancedSection({
    super.key,
    required this.expanded,
    required this.onChanged,
    required this.child,
  });

  final bool expanded;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.advancedBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.advancedBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          initiallyExpanded: expanded,
          onExpansionChanged: onChanged,
          title: Text(
            'Advanced',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.advancedText,
            ),
          ),
          subtitle: Text(
            'Diagnostics, reconnect, and technical settings.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.advancedMuted),
          ),
          iconColor: AppColors.advancedText,
          collapsedIconColor: AppColors.advancedText,
          children: [child],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.brass,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class HotkeyDropdown extends StatelessWidget {
  const HotkeyDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> choices;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.keyboard_command_key_rounded, size: 18),
          ),
          items: choices
              .map(
                (choice) => DropdownMenuItem<String>(
                  value: choice,
                  child: Text(
                    choice,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: GoogleFonts.ibmPlexMono().fontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class SettingField extends StatelessWidget {
  const SettingField({
    super.key,
    required this.label,
    required this.controller,
    required this.onSubmitted,
    this.example,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final String? example;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (example != null) ...[
          const SizedBox(height: 4),
          Text(
            example!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5C7672)),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          onChanged: onSubmitted,
          decoration: InputDecoration(
            hintText: example == null ? null : 'vi,en',
          ),
        ),
      ],
    );
  }
}

class ReadOnlyField extends StatelessWidget {
  const ReadOnlyField({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.panelMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.ibmPlexMono().fontFamily,
            ),
          ),
        ),
      ],
    );
  }
}

class TranscriptBox extends StatelessWidget {
  const TranscriptBox({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.panelMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            value.isEmpty ? 'No transcript yet.' : value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.ibmPlexMono().fontFamily,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.tone = AppStatusTone.calm,
  });

  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, border, titleColor, bodyColor) = switch (tone) {
      AppStatusTone.calm => (
        AppColors.readySoft,
        const Color(0xFFCCDCD4),
        AppColors.ready,
        const Color(0xFF536763),
      ),
      AppStatusTone.active => (
        AppColors.activeSoft,
        const Color(0xFFCFDCE9),
        AppColors.active,
        const Color(0xFF617386),
      ),
      AppStatusTone.warning => (
        AppColors.warningSoft,
        const Color(0xFFE6CEB2),
        const Color(0xFF89521A),
        const Color(0xFF86644A),
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: bodyColor),
          ),
          if (primaryLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (primaryLabel != null)
                  FilledButton(
                    onPressed: onPrimaryPressed,
                    child: Text(primaryLabel!),
                  ),
                if (secondaryLabel != null)
                  TextButton(
                    onPressed: onSecondaryPressed,
                    child: Text(secondaryLabel!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class KeycapBadge extends StatelessWidget {
  const KeycapBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            offset: Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.ink,
          fontFamily: GoogleFonts.ibmPlexMono().fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
