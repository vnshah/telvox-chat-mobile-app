import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'notification_sound.dart';
import 'screens.dart' show mobileNotice;

/// The inbox's ⋮ menu on Android, as WhatsApp's: who is signed in at the
/// top, then the account's settings.
class AccountMenu extends StatelessWidget {
  const AccountMenu({
    super.key,
    required this.session,
    required this.onSignOut,
  });
  final MobileSession session;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final name = '${user?['name'] ?? 'Account'}';
    final email = '${user?['email'] ?? ''}';
    return OverflowMenu(
      header: Padding(
        key: const ValueKey('account-header'),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                email,
                style: const TextStyle(fontSize: 11.5, color: T.muted),
              ),
            ],
          ],
        ),
      ),
      items: [
        (
          label: 'Notification sound',
          onPressed: () => chooseNotificationSound(context, session),
        ),
        (label: 'Privacy policy', onPressed: () => openPrivacyPolicy(context)),
        (
          label: 'Delete account',
          onPressed: () => requestAccountDeletion(context, session),
        ),
        (label: 'Sign out', onPressed: onSignOut),
      ],
    );
  }
}

/// Where the privacy policy is published; the stores link the same page.
const privacyPolicyUrl = 'https://telvox.dev/privacy';

/// Opens the privacy policy in the phone's browser.
Future<void> openPrivacyPolicy(BuildContext context) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(privacyPolicyUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  if (!opened && context.mounted) {
    mobileNotice(context, 'No app could open $privacyPolicyUrl.');
  }
}

/// Asks for this account to be deleted, as both stores require an app to
/// offer. The request goes to the Telvox team, who delete the account and
/// its personal data; until then the account keeps working. Asked once: a
/// second time says when it was asked.
Future<void> requestAccountDeletion(
  BuildContext context,
  MobileSession session,
) async {
  final asked = DateTime.tryParse(
    '${session.user?['deletion_requested_at'] ?? ''}',
  );
  if (asked != null) {
    await _tell(
      context,
      'Deletion requested',
      'You asked for this account to be deleted on ${_day(asked)}. '
          'It will be deleted with its personal data, and signed out on '
          'every phone. Until then you can keep working.',
    );
    return;
  }
  final confirmed = await _confirmDeletion(context);
  if (!confirmed || !context.mounted) return;
  try {
    final answer = await session.api.post('me/deletion-request');
    session.user = {
      ...?session.user,
      'deletion_requested_at':
          answer['requested_at'] ?? DateTime.now().toUtc().toIso8601String(),
    };
    if (!context.mounted) return;
    await _tell(
      context,
      'Request sent',
      'The Telvox team will delete your account and its personal data, '
          'and sign it out on every phone. Until then you can keep working.',
    );
  } catch (e) {
    if (context.mounted) mobileNotice(context, e);
  }
}

String _day(DateTime at) {
  final d = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

const _deletionQuestion = 'Delete your account?';
const _deletionBody =
    'This asks the Telvox team to delete your account and its personal '
    'data. Your business’s chats and contacts are not deleted. '
    'This cannot be undone once the account is deleted.';

Future<bool> _confirmDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => isCupertino(context)
          ? CupertinoAlertDialog(
              title: const Text(_deletionQuestion),
              content: const Text(_deletionBody),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  key: const ValueKey('delete-account-confirm'),
                  isDestructiveAction: true,
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Request deletion'),
                ),
              ],
            )
          : AlertDialog(
              title: const Text(_deletionQuestion),
              content: const Text(_deletionBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const ValueKey('delete-account-confirm'),
                  style: TextButton.styleFrom(foregroundColor: T.danger),
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Request deletion'),
                ),
              ],
            ),
    ) ??
    false;

Future<void> _tell(BuildContext context, String title, String body) =>
    showDialog<void>(
      context: context,
      builder: (dialog) => isCupertino(context)
          ? CupertinoAlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('OK'),
                ),
              ],
            )
          : AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('OK'),
                ),
              ],
            ),
    );

/// Lets the user pick the sound new messages make, the way the phone's own
/// settings do: Android's radio dialog with Cancel and OK, or an iOS list
/// with a check mark. Each sound plays as it is picked.
Future<void> chooseNotificationSound(
  BuildContext context,
  MobileSession session,
) async {
  final preview = SoundPreview();
  try {
    if (isCupertino(context)) {
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => _IosSoundPage(session: session, preview: preview),
        ),
      );
      return;
    }
    var picked = session.notificationSound.value;
    final chosen = await showDialog<NotificationSound>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: const Text('Notification sound'),
          contentPadding: const EdgeInsets.only(top: 12, bottom: 4),
          content: RadioGroup<NotificationSound>(
            groupValue: picked,
            onChanged: (sound) {
              if (sound == null) return;
              setState(() => picked = sound);
              preview.play(sound);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final sound in NotificationSound.values)
                  RadioListTile<NotificationSound>(
                    key: ValueKey('sound-${sound.name}'),
                    value: sound,
                    title: Text(sound.label),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('sound-ok'),
              onPressed: () => Navigator.pop(dialog, picked),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == session.notificationSound.value) return;
    await session.setNotificationSound(chosen);
    if (context.mounted) {
      mobileNotice(context, 'New messages will play ${chosen.label}.');
    }
  } finally {
    await preview.stop();
  }
}

/// iOS Settings' sound list: tap a sound to hear it and keep it.
class _IosSoundPage extends StatelessWidget {
  const _IosSoundPage({required this.session, required this.preview});
  final MobileSession session;
  final SoundPreview preview;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground,
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Notification Sound'),
    ),
    child: SafeArea(
      child: ValueListenableBuilder(
        valueListenable: session.notificationSound,
        builder: (context, current, _) => ListView(
          children: [
            CupertinoListSection.insetGrouped(
              footer: const Text('Played when a new message arrives.'),
              children: [
                for (final sound in NotificationSound.values)
                  CupertinoListTile(
                    key: ValueKey('sound-${sound.name}'),
                    title: Text(sound.label),
                    trailing: sound == current
                        ? const Icon(CupertinoIcons.check_mark, color: T.green)
                        : null,
                    onTap: () {
                      preview.play(sound);
                      session.setNotificationSound(sound);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
