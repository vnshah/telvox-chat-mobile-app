import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'management.dart';
import 'theme.dart';

const reviewScreens = <(String, String, String)>[
  ('Access', 'Sign in', '/login'),
  ('Access', 'Forgot password', '/forgot-password'),
  ('Access', 'Verification', '/verify'),
  ('Access', 'Reset password', '/reset-password'),
  ('Access', 'Choose workspace', '/workspaces'),
  ('Conversations', 'Inbox', '/inbox'),
  ('Conversations', 'Chat', '/chat/ananya'),
  ('Conversations', 'Contacts', '/contacts'),
  ('Conversations', 'Contact details', '/customer/ananya'),
  ('Conversations', 'New contact', '/contact/new'),
  ('Conversations', 'Edit contact', '/contact/ananya/edit'),
  ('Conversations', 'Assignment', '/customer/ananya/assign'),
  ('Conversations', 'Notes', '/customer/ananya/notes'),
  ('Conversations', 'Labels', '/customer/ananya/tags'),
  ('Conversations', 'Custom fields', '/customer/ananya/fields'),
  ('Conversations', 'Media & documents', '/customer/ananya/media'),
  ('Messaging tools', 'Templates', '/templates'),
  ('Messaging tools', 'Template preview', '/template/order'),
  ('Messaging tools', 'Create template', '/template/new'),
  ('Messaging tools', 'Quick replies', '/quick-replies'),
  ('Messaging tools', 'AI assist', '/ai'),
  ('Commerce', 'Catalogue', '/catalogue'),
  ('Commerce', 'Product', '/product/tote'),
  ('Commerce', 'Orders', '/orders'),
  ('Commerce', 'Order details', '/order/2048'),
  ('Support', 'Tickets', '/tickets'),
  ('Support', 'Ticket details', '/ticket/1042'),
  ('Support', 'Create ticket', '/ticket/new'),
  ('Support', 'Calls', '/calls'),
  ('Support', 'Outgoing call', '/call/ananya'),
  ('Support', 'Incoming call', '/call/incoming'),
  ('Business', 'Workspace', '/more'),
  ('Business', 'Campaigns', '/campaigns'),
  ('Business', 'New campaign', '/campaign/new'),
  ('Business', 'Campaign details', '/campaign/autumn'),
  ('Business', 'Automation journey', '/workflow/automations-0'),
  ('Business', 'Reports', '/reports'),
  ('Business', 'Billing & plans', '/billing'),
  ('Account', 'Settings', '/settings'),
  ('Account', 'Profile', '/profile'),
  ('Account', 'Notifications', '/notifications'),
  ('Account', 'Notification preferences', '/settings/notifications'),
  ('Account', 'Notification permission', '/notifications/permission'),
  ('Account', 'Business profile', '/settings/business'),
  ('Account', 'Calling preferences', '/settings/calls'),
  ('Account', 'Security & devices', '/settings/security'),
  ('Account', 'Help & support', '/settings/help'),
  ('Account', 'About', '/settings/about'),
  ('Account', 'Privacy', '/legal/privacy'),
  ('Account', 'Terms', '/legal/terms'),
  ('States', 'Empty state', '/preview/states?state=empty'),
  ('States', 'Loading state', '/preview/states?state=loading'),
  ('States', 'Connection error', '/preview/states?state=error'),
  ('States', 'Offline state', '/preview/states?state=offline'),
];

class PreviewPage extends ConsumerStatefulWidget {
  const PreviewPage({super.key});
  @override
  ConsumerState<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends ConsumerState<PreviewPage> {
  String search = '';
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Screen library',
    subtitle: 'Explore the mobile design. All data and interactions are local to this preview.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Preview appearance'),
        const SizedBox(height: 12),
        PlatformFilters(
          options: const ['Device', 'Android', 'iOS'],
          selected: switch (ref.watch(platformPreviewProvider)) {
            TargetPlatform.android => 'Android',
            TargetPlatform.iOS => 'iOS',
            _ => 'Device',
          },
          onSelected: (value) =>
              ref.read(platformPreviewProvider.notifier).select(switch (value) {
                'Android' => TargetPlatform.android,
                'iOS' => TargetPlatform.iOS,
                _ => null,
              }),
        ),
        const SizedBox(height: 10),
        const Text(
          'Device follows your phone. Choose a style to review the screens below.',
          style: TextStyle(fontSize: 12, color: T.muted),
        ),
        const SizedBox(height: 22),
        SearchBox(
          value: search,
          hint: 'Find a screen',
          onChanged: (v) => setState(() => search = v),
        ),
        for (final group in reviewScreens.map((s) => s.$1).toSet()) ...[
          Section(group),
          for (final screen in reviewScreens.where(
            (s) =>
                s.$1 == group &&
                s.$2.toLowerCase().contains(search.toLowerCase()),
          ))
            MenuRow(screen.$2, Icons.arrow_outward_rounded, route: screen.$3),
        ],
        const Section('Business modules'),
        for (final entry in hubs.entries)
          if (entry.value.$1.toLowerCase().contains(search.toLowerCase()))
            MenuRow(
              entry.value.$1,
              Icons.grid_view_outlined,
              route: '/hub/${entry.key}',
            ),
        const Section('Module screens · list, details & edit'),
        for (final entry in modules.entries)
          if (entry.value.title.toLowerCase().contains(search.toLowerCase()))
            MenuRow(
              entry.value.title,
              entry.value.icon,
              route: '/manage/${entry.key}',
            ),
      ],
    ),
  );
}

class StatePreviewPage extends StatefulWidget {
  const StatePreviewPage({super.key, this.initial = 'empty'});
  final String initial;
  @override
  State<StatePreviewPage> createState() => _StatePreviewPageState();
}

class _StatePreviewPageState extends State<StatePreviewPage> {
  late String state = widget.initial;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Screen states',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final s in ['empty', 'loading', 'error', 'offline'])
              AppChoiceChip(
                label: Text('${s[0].toUpperCase()}${s.substring(1)}'),
                selected: state == s,
                onSelected: (_) => setState(() => state = s),
              ),
          ],
        ),
        if (state == 'empty')
          EmptyView(
            title: 'Your next hello is on its way.',
            description: 'New customer conversations will appear here. Start with someone you know.',
            action: 'New conversation',
            onAction: () => context.push('/contacts?pick=true'),
          )
        else if (state == 'error')
          EmptyView(
            title: 'A small interruption.',
            description: 'We couldn’t load your conversations. Give it another try in a moment.',
            icon: Icons.cloud_off_outlined,
            action: 'Try again',
            onAction: () => context.go('/inbox'),
          )
        else if (state == 'offline') ...[
          const SizedBox(height: 24),
          const Panel(
            color: T.wash,
            child: Row(
              children: [
                AppIcon(Icons.wifi_off_rounded, color: T.brass),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You’re offline. Your saved conversations are still here.',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
          const EmptyView(
            title: 'A moment to reconnect.',
            description:
                'New replies will be available when you’re back online.',
            icon: Icons.wifi_off_outlined,
          ),
        ] else ...[
          const SizedBox(height: 32),
          const LinearProgressIndicator(
            value: .55,
            backgroundColor: T.paper,
            color: T.green,
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: T.paper,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 12, width: 130, color: T.paper),
                        const SizedBox(height: 10),
                        Container(height: 9, color: T.wash),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Center(
            child: Text(
              'Getting your conversations ready…',
              style: TextStyle(color: T.muted, fontSize: 12),
            ),
          ),
        ],
      ],
    ),
  );
}
