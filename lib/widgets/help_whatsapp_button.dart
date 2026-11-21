import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/remote_config_service.dart';

/// WhatsApp help contact — Magic Box pattern.
///
/// The number comes from remote config (tj-pro.json
/// `support_whatsapp_number`, default '03090808180' from AppConfig)
/// so it can change without a rebuild. The wa.me link is derived:
/// Pakistan code 92 + number without the leading 0.
class SupportContact {
  /// Display number from remote config (e.g. '03090808180').
  static String get displayNumber =>
      RemoteConfigService.instance.config.supportWhatsAppNumber;

  /// wa.me link for [displayNumber] (or an explicit [number]).
  static String waMeUrl([String? number]) {
    final String digits =
        (number ?? displayNumber).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('92')) return 'https://wa.me/$digits';
    if (digits.startsWith('0')) return 'https://wa.me/92${digits.substring(1)}';
    return 'https://wa.me/92$digits';
  }

  static Future<void> openWhatsApp(BuildContext context) async {
    try {
      await launchUrl(
        Uri.parse(waMeUrl()),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }
}

/// Green WhatsApp button (labelled "WhatsApp").
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
      ),
      onPressed: () => SupportContact.openWhatsApp(context),
      icon: const Icon(Icons.chat, size: 18),
      label: const Text('WhatsApp'),
    );
  }
}

/// "For Help" row — placed at the very END of a screen, under all
/// other content: a guideline line, the contact number, WhatsApp
/// button. Used on the login screen (and home/settings by Phase 2).
class HelpWhatsAppRow extends StatelessWidget {
  const HelpWhatsAppRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: RemoteConfigService.instance.notifier,
      builder: (context, config, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'For Help — need any guideline? Message us on WhatsApp',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              config.supportWhatsAppNumber,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Center(child: WhatsAppButton()),
          ],
        );
      },
    );
  }
}
