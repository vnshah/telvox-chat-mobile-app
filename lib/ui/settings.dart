import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'theme.dart';

/// Settings tab. It lives in the main shell, which already draws the header.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: InkWell(
            onTap: () => context.push('/profile'),
            child: Row(
              children: [
                const Avatar('Renav Shah', size: 54),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Renav Shah',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'renav@studionorth.co',
                        style: TextStyle(fontSize: 12, color: T.muted),
                      ),
                      const SizedBox(height: 7),
                      const Pill(
                        'Workspace admin',
                        color: T.brass,
                        fill: T.wash,
                      ),
                    ],
                  ),
                ),
                const AppIcon(Icons.chevron_right, color: T.brass),
              ],
            ),
          ),
        ),
        const Section('Your account'),
        MenuRow('Profile', Icons.person_outline, route: '/profile'),
        MenuRow(
          'Notifications',
          Icons.notifications_none_rounded,
          route: '/settings/notifications',
        ),
        MenuRow(
          'Security & devices',
          Icons.shield_outlined,
          route: '/settings/security',
        ),
        const Section('Workspace'),
        MenuRow(
          'Business profile',
          Icons.storefront_outlined,
          route: '/settings/business',
        ),
        MenuRow(
          'Connected numbers',
          Icons.phone_android_outlined,
          route: '/workspaces',
        ),
        const Section('Support'),
        MenuRow('Help & support', Icons.help_outline, route: '/settings/help'),
        MenuRow(
          'About telvox chat',
          Icons.info_outline,
          route: '/settings/about',
        ),
        MenuRow('Privacy', Icons.lock_outline, route: '/legal/privacy'),
        const SizedBox(height: 20),
        MenuRow(
          'Sign out',
          Icons.logout_rounded,
          danger: true,
          onTap: () async {
            if (await confirm(
                  context,
                  'Leave this workspace?',
                  'Your sample changes will stay available while this preview is open.',
                  action: 'Sign out',
                ) &&
                context.mounted) {
              context.go('/login');
            }
          },
        ),
        const SizedBox(height: 20),
        Center(child: Text('telvox | chat · 1.0.0', style: mono(size: 10))),
      ],
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final form = GlobalKey<FormState>();
  String name = 'Renav Shah';
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Your profile',
    bottom: AppButton.filled(
      onPressed: () {
        if (!form.currentState!.validate()) return;
        notice(context, 'Profile saved in preview.');
      },
      child: const Text('Save changes'),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          Center(child: Avatar(name.isEmpty ? 'Your profile' : name, size: 86)),
          const SizedBox(height: 10),
          Center(
            child: AppButton.text(
              onPressed: () => sheet(
                context,
                Column(
                  children: [
                    Text(
                      'Choose profile style',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 22),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Avatar('Renav Shah', size: 60),
                        Avatar('Renav Shah', size: 60, color: T.paper),
                        Avatar(
                          'Renav Shah',
                          size: 60,
                          color: Color(0xFFE2DEE9),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    AppButton.text(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              child: const Text('Profile photo'),
            ),
          ),
          const SizedBox(height: 20),
          LabeledField(
            'Full name',
            value: name,
            required: true,
            onChanged: (v) => setState(() => name = v),
          ),
          const LabeledField(
            'Email address',
            value: 'renav@studionorth.co',
            keyboard: TextInputType.emailAddress,
            required: true,
          ),
          const LabeledField(
            'Phone number',
            value: '+91 98765 00000',
            keyboard: TextInputType.phone,
          ),
          const LabeledField('Role', value: 'Workspace admin'),
          const LabeledField(
            'About',
            value: 'Here to make every conversation count.',
            lines: 3,
          ),
        ],
      ),
    ),
  );
}

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(previewProvider).notificationsRead;
    return PageFrame(
      title: 'Notifications',
      actions: [
        AppButton.text(
          onPressed: () =>
              ref.read(previewProvider.notifier).notificationsRead(),
          child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Section('Today'),
          for (final (icon, title, body, time, route) in [
            (
              Icons.chat_bubble_outline,
              'A new conversation for you',
              'Rohan is asking about the everyday tote.',
              '10:35',
              '/chat/rohan',
            ),
            (
              Icons.confirmation_number_outlined,
              'Ticket #1042 needs a reply',
              'Ishita’s address update is due in 24 minutes.',
              '09:42',
              '/ticket/1042',
            ),
            (
              Icons.check_circle_outline,
              'Template approved',
              'shipping_update is ready to use.',
              '09:10',
              '/template/shipping',
            ),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: read ? Colors.white : T.wash,
                border: Border.all(color: T.edge),
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: () {
                  ref.read(previewProvider.notifier).notificationsRead();
                  context.push(route);
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(icon, size: 21, color: T.brass),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            body,
                            style: const TextStyle(
                              fontSize: 12,
                              color: T.secondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(time, style: mono(size: 10)),
                        ],
                      ),
                    ),
                    if (!read)
                      const AppIcon(Icons.circle, size: 6, color: T.green),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          AppButton.text(
            onPressed: () => context.push('/notifications/permission'),
            child: const Text('Notification permissions'),
          ),
        ],
      ),
    );
  }
}

class PreferencePage extends ConsumerWidget {
  const PreferencePage(this.section, {super.key});
  final String section;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewProvider);
    final control = ref.read(previewProvider.notifier);
    final definitions = section == 'calls'
        ? [
            ('Incoming calls', 'Allow customers to reach your team'),
            ('Call alerts', 'Sound and vibration for incoming calls'),
            ('Call recording', 'Show recording controls when available'),
          ]
        : [
            ('New messages', 'Alerts for conversations assigned to you'),
            ('Message previews', 'Show message text in notifications'),
            (
              'Unassigned conversations',
              'Know when a customer needs a teammate',
            ),
            ('Ticket reminders', 'Stay ahead of response targets'),
            ('Sound', 'A gentle sound for new activity'),
            ('Vibration', 'A subtle nudge when a message arrives'),
          ];
    return PageFrame(
      title: section == 'calls'
          ? 'Calling preferences'
          : 'Notification preferences',
      subtitle: 'Choose what deserves your attention.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Section('Your preferences'),
          for (final item in definitions)
            AppSwitchTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              title: Text(
                item.$1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                item.$2,
                style: const TextStyle(fontSize: 12, color: T.muted),
              ),
              value: state.preferences['$section${item.$1}'] ?? true,
              onChanged: (v) => control.preference('$section${item.$1}', v),
            ),
          const SizedBox(height: 24),
          const Panel(
            color: T.wash,
            child: Text(
              'Changes apply to this preview. Device permissions are managed separately.',
              style: TextStyle(fontSize: 12, height: 1.6, color: T.secondary),
            ),
          ),
          if (section != 'calls')
            MenuRow(
              'Quiet hours',
              Icons.bedtime_outlined,
              subtitle: '22:00 – 08:00',
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 22, minute: 0),
                );
                if (time != null && context.mounted) {
                  notice(
                    context,
                    'Quiet hours start at ${time.format(context)} in preview.',
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class BusinessProfilePage extends StatefulWidget {
  const BusinessProfilePage({super.key});
  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Business profile',
    bottom: AppButton.filled(
      onPressed: () {
        if (form.currentState!.validate()) {
          notice(context, 'Business profile saved in preview.');
        }
      },
      child: const Text('Save profile'),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: Avatar('Studio North', size: 80)),
          const SizedBox(height: 26),
          const LabeledField(
            'Business name',
            value: 'Studio North',
            required: true,
          ),
          const LabeledField(
            'About',
            value: 'Thoughtfully made essentials for your everyday.',
            lines: 3,
          ),
          const LabeledField('Category', value: 'Shopping & retail'),
          const LabeledField('Business email', value: 'hello@studionorth.co'),
          const LabeledField('Website', value: 'https://studionorth.example'),
          const LabeledField(
            'Address',
            value: 'Ahmedabad, Gujarat, India',
            lines: 2,
          ),
          const Section('Connected number'),
          const Panel(
            child: Column(
              children: [
                InfoLine('Number', '+91 98765 00001'),
                InfoLine('Quality', 'High'),
                InfoLine('Status', 'Connected · sample account'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Security & devices',
    subtitle: 'A little peace of mind for your workspace.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Panel(
          color: T.selected,
          child: Row(
            children: [
              AppIcon(Icons.verified_user_outlined, color: T.green, size: 26),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Your workspace, kept in good hands.',
                  style: TextStyle(color: T.green, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const Section('Active devices'),
        const Panel(
          child: Column(
            children: [
              InfoLine('Android device', 'This device · active now'),
              InfoLine('Location', 'Ahmedabad, India'),
              InfoLine('Last active', 'Today · 10:42'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoLine('Web browser', 'Chrome · macOS'),
              const InfoLine('Last active', 'Today · 09:15'),
              AppButton.text(
                onPressed: () async {
                  if (await confirm(
                        context,
                        'End this session?',
                        'This is a session-management preview.',
                      ) &&
                      context.mounted) {
                    notice(context, 'Session removed in preview.');
                  }
                },
                child: const Text(
                  'End session',
                  style: TextStyle(color: T.danger),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PermissionPage extends StatelessWidget {
  const PermissionPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Stay in the conversation',
    child: Column(
      children: [
        const SizedBox(height: 60),
        Container(
          width: 112,
          height: 112,
          decoration: const BoxDecoration(
            color: T.selected,
            shape: BoxShape.circle,
          ),
          child: const AppIcon(
            Icons.notifications_active_outlined,
            size: 48,
            color: T.green,
          ),
        ),
        const SizedBox(height: 30),
        Text(
          'A gentle nudge,\nwhen it matters.',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        const Text(
          'Keep up with new messages, assigned conversations, and customer follow-ups.',
          textAlign: TextAlign.center,
          style: TextStyle(color: T.muted, height: 1.7),
        ),
        const SizedBox(height: 34),
        AppButton.filled(
          onPressed: () => notice(
            context,
            'Permission request preview. No device setting has changed.',
          ),
          child: const Text('Enable notifications'),
        ),
        AppButton.text(
          onPressed: () => context.pop(),
          child: const Text('Maybe later'),
        ),
      ],
    ),
  );
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key, this.about = false, this.legal});
  final bool about;
  final String? legal;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: legal != null
        ? (legal == 'privacy' ? 'Privacy' : 'Terms of use')
        : about
        ? 'About telvox chat'
        : 'Help & support',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Center(child: Brand(large: true)),
        const SizedBox(height: 36),
        if (legal != null) ...[
          Text(
            'Your trust matters.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),
          const Text(
            'This is a design preview of the policy screen. Your business’s approved privacy policy and terms will appear here before release.',
            style: TextStyle(color: T.secondary, height: 1.8),
          ),
          const Section('Your information'),
          const Text(
            'Only sample conversations and contacts are included in this preview. No customer data or account credentials are requested.',
            style: TextStyle(height: 1.8, color: T.secondary),
          ),
        ] else if (about) ...[
          Text(
            'Closer to your customers.',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          const Text(
            'A thoughtful home for customer conversations. Built for the people behind your business.',
            style: TextStyle(color: T.secondary, height: 1.8),
            textAlign: TextAlign.center,
          ),
          const Section('About this preview'),
          const InfoLine('Version', '1.0.0 · UI preview'),
          const InfoLine('Workspace', 'Studio North'),
          MenuRow(
            'Privacy policy',
            Icons.lock_outline,
            route: '/legal/privacy',
          ),
          MenuRow(
            'Terms of use',
            Icons.article_outlined,
            route: '/legal/terms',
          ),
        ] else ...[
          const SearchBox(hint: 'What can we help with?'),
          const Section('Common questions'),
          for (final (title, body) in [
            (
              'How do I assign a conversation?',
              'Open the contact details or the chat menu, choose Assign conversation, and select a teammate.',
            ),
            (
              'How do templates work?',
              'Choose a template, personalise its values, and review the message before sharing.',
            ),
            (
              'Where can I find customer notes?',
              'Open a customer’s details and select Notes. Notes are visible to your team only.',
            ),
            (
              'How do I change my workspace?',
              'Use the workspace switcher beside the brand mark to choose another connected number.',
            ),
          ])
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(title, style: const TextStyle(fontSize: 14)),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    body,
                    style: const TextStyle(color: T.secondary, height: 1.7),
                  ),
                ),
              ],
            ),
          const Section('Need a little more help?'),
          MenuRow(
            'Contact support',
            Icons.chat_bubble_outline,
            subtitle: 'We’re here for your team',
            onTap: () => sheet(
              context,
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('Support'),
                  SizedBox(height: 14),
                  Text(
                    'Your workspace administrator can help with access and account questions.',
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Support contact details will appear here before release.',
                    style: TextStyle(color: T.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
