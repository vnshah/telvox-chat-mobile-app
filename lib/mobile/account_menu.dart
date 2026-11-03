import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
        (label: 'Sign out', onPressed: onSignOut),
      ],
    );
  }
}

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
