import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'theme.dart';

class ModuleSpec {
  const ModuleSpec(
    this.title,
    this.icon,
    this.description,
    this.items, {
    this.field = 'Description',
  });
  final String title, description, field;
  final IconData icon;
  final List<(String, String)> items;
}

const modules = <String, ModuleSpec>{
  'automations': ModuleSpec(
    'Automations',
    Icons.account_tree_outlined,
    'Small touches, handled automatically.',
    [
      ('Welcome new customers', 'New message → welcome reply'),
      ('Order follow-up', 'Delivered order → follow-up message'),
    ],
  ),
  'chatbots': ModuleSpec(
    'Chatbots',
    Icons.smart_toy_outlined,
    'A helpful first hello, around the clock.',
    [
      ('Studio assistant', 'Customer support · Published'),
      ('Product guide', 'Shopping assistance · Draft'),
    ],
  ),
  'flows': ModuleSpec(
    'WhatsApp flows',
    Icons.alt_route_rounded,
    'Simple journeys, right inside a conversation.',
    [
      ('Delivery address', 'Collect customer delivery details'),
      ('Customer feedback', 'A little feedback after every order'),
    ],
  ),
  'accounts': ModuleSpec(
    'Accounts',
    Icons.phone_android_outlined,
    'Your connected business numbers.',
    [
      ('Studio North', '+91 98765 00001 · Connected'),
      ('Wholesale', '+91 98765 00002 · Connected'),
    ],
    field: 'Phone number',
  ),
  'users': ModuleSpec(
    'Team members',
    Icons.people_outline,
    'The people behind every good conversation.',
    [
      ('Renav Shah', 'Workspace admin · Online'),
      ('Meera Joshi', 'Support agent · Online'),
      ('Aditya Shah', 'Sales agent · Away'),
    ],
    field: 'Email address',
  ),
  'departments': ModuleSpec(
    'Departments',
    Icons.groups_outlined,
    'Give every question the right home.',
    [('Support', '3 team members'), ('Sales', '2 team members')],
  ),
  'branches': ModuleSpec(
    'Branches',
    Icons.location_city_outlined,
    'Stay connected, wherever your team works.',
    [('Ahmedabad', 'Head office'), ('Mumbai', 'Sales office')],
    field: 'Address',
  ),
  'businesses': ModuleSpec(
    'Businesses',
    Icons.storefront_outlined,
    'The businesses in your organization.',
    [
      ('Studio North', 'Retail & lifestyle'),
      ('North Wholesale', 'Business customers'),
    ],
  ),
  'permissions': ModuleSpec(
    'Roles & permissions',
    Icons.admin_panel_settings_outlined,
    'The right access for the right people.',
    [
      ('Workspace admin', 'All workspace tools'),
      ('Support agent', 'Inbox, contacts & tickets'),
      ('Sales agent', 'Inbox, contacts & catalogue'),
    ],
  ),
  'currencies': ModuleSpec(
    'Currencies',
    Icons.currency_exchange_outlined,
    'Currency settings for your workspace.',
    [('Indian Rupee', 'INR · ₹'), ('US Dollar', 'USD · \$')],
    field: 'Currency code',
  ),
  'countries': ModuleSpec(
    'Countries',
    Icons.public_outlined,
    'Countries available to your business.',
    [('India', '+91 · IN'), ('United Kingdom', '+44 · GB')],
    field: 'Country code',
  ),
  'pricing': ModuleSpec(
    'Default pricing',
    Icons.price_change_outlined,
    'Review your messaging price configuration.',
    [
      ('India · Utility', 'Sample rate configuration'),
      ('India · Marketing', 'Sample rate configuration'),
    ],
    field: 'Rate',
  ),
  'apps': ModuleSpec(
    'Apps',
    Icons.extension_outlined,
    'Bring your business tools a little closer.',
    [
      ('Zoho CRM', 'Customer records · Available'),
      ('Shopify', 'Orders & products · Available'),
      ('WooCommerce', 'Store connection · Available'),
    ],
  ),
  'webhooks': ModuleSpec(
    'Webhooks',
    Icons.webhook_outlined,
    'Send events to your business systems.',
    [
      ('Order events', 'https://api.example.com/webhooks/orders'),
      ('Message updates', 'https://api.example.com/webhooks/messages'),
    ],
    field: 'Endpoint URL',
  ),
  'links': ModuleSpec(
    'Link tracking',
    Icons.link_rounded,
    'Understand what catches your customers’ eye.',
    [
      ('Autumn collection', '128 clicks · Sample campaign'),
      ('Order tracking', '84 clicks · Sample utility link'),
    ],
    field: 'Destination URL',
  ),
  'demo-qr': ModuleSpec(
    'Demo QR sessions',
    Icons.qr_code_rounded,
    'Start a sample customer journey.',
    [
      ('Studio introduction', 'Welcome flow preview'),
      ('Shopping assistant', 'Catalogue journey preview'),
    ],
  ),
  'simcards': ModuleSpec(
    'SIM cards',
    Icons.sim_card_outlined,
    'Your registered business phone lines.',
    [
      ('Primary business line', '+91 98765 00001'),
      ('Wholesale line', '+91 98765 00002'),
    ],
    field: 'Phone number',
  ),
  'stores': ModuleSpec(
    'Store integrations',
    Icons.shopping_bag_outlined,
    'Bring orders into your conversations.',
    [
      ('Shopify', 'Studio North store · Sample connection'),
      ('WooCommerce', 'Available to connect'),
    ],
    field: 'Store URL',
  ),
  'statuses': ModuleSpec(
    'Ticket statuses',
    Icons.task_alt_rounded,
    'Keep the next step clear for your team.',
    [
      ('Open', 'Waiting for your team'),
      ('Pending', 'Waiting for a customer'),
      ('Resolved', 'All taken care of'),
    ],
  ),
  'business-hours': ModuleSpec(
    'Business hours',
    Icons.schedule_outlined,
    'Let customers know when you’re here.',
    [
      ('Monday – Friday', '09:00 – 18:00 · Asia/Kolkata'),
      ('Saturday', '10:00 – 14:00 · Asia/Kolkata'),
      ('Sunday', 'Closed'),
    ],
    field: 'Hours',
  ),
  'holidays': ModuleSpec(
    'Holidays',
    Icons.event_outlined,
    'Make room for the days you’re away.',
    [('Diwali break', '8 November 2026'), ('New Year', '1 January 2027')],
    field: 'Date',
  ),
  'sla': ModuleSpec(
    'Response targets',
    Icons.timer_outlined,
    'A promise your team can keep.',
    [
      ('Priority support', 'First reply in 30 minutes'),
      ('Standard support', 'First reply in 2 hours'),
    ],
    field: 'Response time',
  ),
  'notification-config': ModuleSpec(
    'Ticket notifications',
    Icons.notifications_none_outlined,
    'Keep your team in the loop.',
    [
      ('Assignment alert', 'When a ticket is assigned'),
      ('Response reminder', 'Before a response target is missed'),
    ],
  ),
  'notification-templates': ModuleSpec(
    'Notification templates',
    Icons.article_outlined,
    'Clear updates for your team.',
    [
      ('New ticket assigned', 'A ticket needs your attention'),
      ('Response target approaching', 'A gentle reminder to follow up'),
    ],
    field: 'Message',
  ),
  'dispositions': ModuleSpec(
    'Dispositions',
    Icons.fact_check_outlined,
    'Leave a useful outcome after every ticket.',
    [
      ('Information provided', 'Customer question answered'),
      ('Order updated', 'Order details changed'),
      ('Follow-up required', 'Keep the conversation moving'),
    ],
  ),
  'plans': ModuleSpec(
    'Plans',
    Icons.layers_outlined,
    'Workspace plans and included features.',
    [
      ('Business', 'Sample plan · Current workspace'),
      ('Enterprise', 'Sample plan · Larger teams'),
    ],
  ),
  'receivables': ModuleSpec(
    'Receivables',
    Icons.receipt_long_outlined,
    'A clear view of outstanding balances.',
    [
      ('Studio North', 'INV-2048 · ₹1,999'),
      ('North Wholesale', 'INV-2047 · Paid'),
    ],
    field: 'Amount',
  ),
  'priorities': ModuleSpec(
    'Ticket priorities',
    Icons.flag_outlined,
    'Focus attention where it matters.',
    [
      ('High', 'Urgent customer requests'),
      ('Medium', 'Standard support'),
      ('Low', 'General enquiries'),
    ],
  ),
  'keywords': ModuleSpec(
    'Automation keywords',
    Icons.text_fields_outlined,
    'The words that start a helpful journey.',
    [
      ('hello, hi', 'Welcome new customers'),
      ('order, tracking', 'Order status assistance'),
    ],
    field: 'Keywords',
  ),
  'sessions': ModuleSpec(
    'Active sessions',
    Icons.devices_outlined,
    'Where your team is signed in.',
    [
      ('Renav · Android', 'This device · Active now'),
      ('Meera · Chrome', 'Ahmedabad · Active 5 minutes ago'),
    ],
  ),
  'api-logs': ModuleSpec(
    'API logs',
    Icons.code_outlined,
    'A record of your connected services.',
    [
      ('POST /messages', '200 · Today, 10:42'),
      ('GET /templates', '200 · Today, 10:35'),
    ],
  ),
  'audit-log': ModuleSpec(
    'Audit log',
    Icons.history_rounded,
    'A little context behind every change.',
    [
      ('Conversation assigned', 'Renav Shah · Today, 10:42'),
      ('Template updated', 'Meera Joshi · Today, 09:14'),
    ],
  ),
  'platform-notifications': ModuleSpec(
    'Platform notifications',
    Icons.notifications_active_outlined,
    'Updates for the people on your platform.',
    [
      ('Account updates', 'Business account changes'),
      ('Billing reminders', 'Balance and plan reminders'),
    ],
  ),
  'announcements': ModuleSpec(
    'Announcements',
    Icons.campaign_outlined,
    'Keep everyone up to date.',
    [
      ('Welcome to your workspace', 'Published · All team members'),
      ('Holiday support hours', 'Draft · Business accounts'),
    ],
    field: 'Announcement',
  ),
  'mail': ModuleSpec(
    'Mail configuration',
    Icons.mail_outline,
    'Your business email delivery settings.',
    [('Workspace mail', 'hello@studionorth.example')],
    field: 'Sender address',
  ),
  'branding': ModuleSpec(
    'Branding',
    Icons.palette_outlined,
    'Make this workspace feel like your business.',
    [('Studio North', 'Telvox family · Warm paper & green')],
    field: 'Brand name',
  ),
};

const hubs = <String, (String, List<(String, IconData, String)>)>{
  'automation': (
    'Automation',
    [
      ('Automations', Icons.account_tree_outlined, '/manage/automations'),
      ('Chatbots', Icons.smart_toy_outlined, '/manage/chatbots'),
      ('WhatsApp flows', Icons.alt_route_rounded, '/manage/flows'),
      ('Keywords', Icons.text_fields_outlined, '/manage/keywords'),
    ],
  ),
  'commerce': (
    'Commerce',
    [
      ('Catalogue', Icons.shopping_bag_outlined, '/catalogue'),
      ('Orders', Icons.receipt_long_outlined, '/orders'),
      ('Store integrations', Icons.extension_outlined, '/manage/stores'),
    ],
  ),
  'organization': (
    'Organization',
    [
      ('Accounts', Icons.phone_android_outlined, '/manage/accounts'),
      ('Team members', Icons.people_outline, '/manage/users'),
      ('Departments', Icons.groups_outlined, '/manage/departments'),
      ('Branches', Icons.location_city_outlined, '/manage/branches'),
      ('Businesses', Icons.storefront_outlined, '/manage/businesses'),
      ('Roles & permissions', Icons.shield_outlined, '/manage/permissions'),
      ('Currencies', Icons.currency_exchange_outlined, '/manage/currencies'),
      ('Countries', Icons.public_outlined, '/manage/countries'),
      ('Default pricing', Icons.price_change_outlined, '/manage/pricing'),
    ],
  ),
  'integrations': (
    'Integrations',
    [
      ('Apps', Icons.extension_outlined, '/manage/apps'),
      ('Webhooks', Icons.webhook_outlined, '/manage/webhooks'),
      ('Link tracking', Icons.link_rounded, '/manage/links'),
      ('Demo QR sessions', Icons.qr_code_outlined, '/manage/demo-qr'),
      ('SIM cards', Icons.sim_card_outlined, '/manage/simcards'),
    ],
  ),
  'ticket-config': (
    'Ticket configuration',
    [
      ('Dashboard', Icons.bar_chart_outlined, '/reports?type=Ticket volume'),
      ('Statuses', Icons.task_alt_outlined, '/manage/statuses'),
      ('Business hours', Icons.schedule_outlined, '/manage/business-hours'),
      ('Holidays', Icons.event_outlined, '/manage/holidays'),
      ('Response targets', Icons.timer_outlined, '/manage/sla'),
      (
        'Notifications',
        Icons.notifications_outlined,
        '/manage/notification-config',
      ),
      (
        'Notification templates',
        Icons.article_outlined,
        '/manage/notification-templates',
      ),
      ('Dispositions', Icons.fact_check_outlined, '/manage/dispositions'),
      ('Priorities', Icons.flag_outlined, '/manage/priorities'),
      ('Canned responses', Icons.bolt_outlined, '/quick-replies'),
    ],
  ),
  'system': (
    'System',
    [
      ('Credit & plans', Icons.account_balance_wallet_outlined, '/billing'),
      ('Branding', Icons.palette_outlined, '/manage/branding'),
      ('Mail configuration', Icons.mail_outlined, '/manage/mail'),
      ('Plans', Icons.layers_outlined, '/manage/plans'),
      ('Receivables', Icons.receipt_long_outlined, '/manage/receivables'),
      ('Ticket priorities', Icons.flag_outlined, '/manage/priorities'),
      ('Automation keywords', Icons.text_fields_outlined, '/manage/keywords'),
      ('Active sessions', Icons.devices_outlined, '/manage/sessions'),
      ('API logs', Icons.code_outlined, '/manage/api-logs'),
      ('Audit log', Icons.history_outlined, '/manage/audit-log'),
      (
        'Notifications',
        Icons.notifications_outlined,
        '/manage/platform-notifications',
      ),
      ('Announcements', Icons.campaign_outlined, '/manage/announcements'),
      ('Settings', Icons.settings_outlined, '/settings'),
    ],
  ),
};

final recordsProvider =
    NotifierProvider<RecordsController, Map<String, List<(String, String)>>>(
      RecordsController.new,
    );

class RecordsController extends Notifier<Map<String, List<(String, String)>>> {
  @override
  Map<String, List<(String, String)>> build() => {};
  void save(String section, String name, String detail, {int? index}) {
    final items = [...state[section] ?? modules[section]!.items];
    if (index != null && index < items.length) {
      items[index] = (name, detail);
    } else {
      items.add((name, detail));
    }
    state = {...state, section: items};
  }
}

class HubPage extends StatelessWidget {
  const HubPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) {
    final hub = hubs[id] ?? hubs.values.first;
    return PageFrame(
      title: hub.$1,
      subtitle: 'Everything your team needs, in one place.',
      child: Column(
        children: [
          for (final item in hub.$2) ...[
            MenuRow(item.$1, item.$2, route: item.$3),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class ModulePage extends ConsumerStatefulWidget {
  const ModulePage(this.id, {super.key});
  final String id;
  @override
  ConsumerState<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends ConsumerState<ModulePage> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final spec = modules[widget.id]!;
    final items = ref.watch(recordsProvider)[widget.id] ?? spec.items;
    final readOnly = ['api-logs', 'audit-log', 'sessions'].contains(widget.id);
    return PageFrame(
      title: spec.title,
      subtitle: spec.description,
      actions: [
        if (!readOnly)
          AppIconButton(
            tooltip: 'Create ${spec.title.toLowerCase()} entry',
            onPressed: () => context.push('/manage/${widget.id}/new'),
            icon: const AppIcon(Icons.add),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBox(
            value: search,
            hint: 'Search ${spec.title.toLowerCase()}',
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < items.length; i++)
            if ('${items[i].$1} ${items[i].$2}'.toLowerCase().contains(
              search.toLowerCase(),
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  child: InkWell(
                    onTap: () => context.push('/manage/${widget.id}/$i'),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: T.wash,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: AppIcon(spec.icon, color: T.brass, size: 21),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                items[i].$1,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                items[i].$2,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: T.muted,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const AppIcon(
                          Icons.chevron_right_rounded,
                          color: T.brass,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          if (items
              .where(
                (i) => '${i.$1} ${i.$2}'.toLowerCase().contains(
                  search.toLowerCase(),
                ),
              )
              .isEmpty)
            EmptyView(
              title: 'No matching entries',
              description: 'Try another search to find what you need.',
              icon: spec.icon,
            ),
          const SizedBox(height: 12),
          const Text(
            'Sample workspace data',
            style: TextStyle(fontSize: 10, color: T.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class ModuleDetailPage extends ConsumerWidget {
  const ModuleDetailPage(this.section, this.index, {super.key});
  final String section;
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = modules[section]!;
    final items = ref.watch(recordsProvider)[section] ?? spec.items;
    final item = items[index.clamp(0, items.length - 1)];
    final workflow = ['automations', 'chatbots', 'flows'].contains(section);
    final permissions = section == 'permissions';
    return PageFrame(
      title: item.$1,
      subtitle: spec.title,
      actions: [
        AppIconButton(
          tooltip: 'Edit entry',
          onPressed: () => context.push('/manage/$section/$index/edit'),
          icon: const AppIcon(Icons.edit_outlined, size: 20),
        ),
      ],
      bottom: workflow
          ? AppButton.filledIcon(
              onPressed: () => context.push('/workflow/$section-$index'),
              icon: const AppIcon(Icons.account_tree_outlined, size: 18),
              label: const Text('View flow'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            color: T.wash,
            child: Row(
              children: [
                AppIcon(spec.icon, color: T.brass, size: 34),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Pill('Preview'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Section('Information'),
          Panel(
            child: Column(
              children: [
                InfoLine('Name', item.$1),
                InfoLine(spec.field, item.$2),
                const InfoLine('Workspace', 'Studio North'),
                const InfoLine('Updated', 'Today · 09:15'),
              ],
            ),
          ),
          if (permissions) ...[
            const Section('Permissions'),
            for (final label in [
              'Shared inbox',
              'Manage contacts',
              'Send templates',
              'Assign conversations',
              'Manage tickets',
              'View reports',
            ])
              AppCheckboxTile(
                value: true,
                onChanged: (_) =>
                    notice(context, 'Use Edit entry to preview role changes.'),
                title: Text(label, style: const TextStyle(fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
          if (section == 'users') ...[
            const Section('Team activity'),
            const InfoLine('Assigned chats', '12'),
            const InfoLine('Open tickets', '3'),
            const InfoLine('Average reply', '3m 12s'),
          ],
          if (workflow) ...[
            const Section('Journey overview'),
            const InfoLine('Trigger', 'New customer message'),
            const InfoLine('Action', 'Send a helpful response'),
            const InfoLine('Last run', 'Today · 10:35'),
          ],
          if (section == 'webhooks') ...[
            const Section('Subscribed events'),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill('message.received', color: T.brass, fill: T.wash),
                Pill('message.status', color: T.brass, fill: T.wash),
                Pill('order.updated', color: T.brass, fill: T.wash),
              ],
            ),
            const SizedBox(height: 24),
            AppButton.outlined(
              onPressed: () => notice(
                context,
                'Connection testing is a preview; no request is sent.',
              ),
              child: const Text('Test connection'),
            ),
          ],
          if (section == 'demo-qr') ...[
            const Section('Session preview'),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: T.wash,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const AppIcon(
                Icons.qr_code_2_rounded,
                size: 140,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Illustrative QR · not a live session link',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: T.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class ModuleFormPage extends ConsumerStatefulWidget {
  const ModuleFormPage(this.section, {super.key, this.index});
  final String section;
  final int? index;
  @override
  ConsumerState<ModuleFormPage> createState() => _ModuleFormPageState();
}

class _ModuleFormPageState extends ConsumerState<ModuleFormPage> {
  final form = GlobalKey<FormState>();
  late final initial = widget.index == null
      ? ('', '')
      : (ref.read(recordsProvider)[widget.section] ??
            modules[widget.section]!.items)[widget.index!];
  late final name = TextEditingController(text: initial.$1);
  late final detail = TextEditingController(text: initial.$2);
  bool active = true;
  final chosenPermissions = <String>{'Shared inbox', 'Manage contacts'};
  @override
  void dispose() {
    name.dispose();
    detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = modules[widget.section]!;
    return PageFrame(
      title: widget.index == null ? 'New entry' : 'Edit entry',
      subtitle: spec.title,
      bottom: AppButton.filled(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          ref
              .read(recordsProvider.notifier)
              .save(
                widget.section,
                name.text,
                detail.text,
                index: widget.index,
              );
          context.pop();
          notice(context, 'Saved in this preview.');
        },
        child: const Text('Save changes'),
      ),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              'Name',
              controller: name,
              hint: 'Give this entry a name',
              required: true,
            ),
            LabeledField(
              spec.field,
              controller: detail,
              hint: 'Add ${spec.field.toLowerCase()}',
              required: true,
              lines:
                  [
                    'Description',
                    'Message',
                    'Announcement',
                  ].contains(spec.field)
                  ? 3
                  : 1,
            ),
            if (widget.section == 'users')
              const LabeledField('Role', value: 'Support agent'),
            if (widget.section == 'webhooks')
              const LabeledField(
                'Signing secret',
                hint: 'Configured securely during integration',
                obscure: true,
              ),
            if (widget.section == 'business-hours') ...[
              const LabeledField('Timezone', value: 'Asia/Kolkata'),
              const LabeledField('Start time', value: '09:00'),
              const LabeledField('End time', value: '18:00'),
            ],
            if (widget.section == 'permissions') ...[
              const Section('Permissions'),
              for (final permission in [
                'Shared inbox',
                'Manage contacts',
                'Send templates',
                'Manage tickets',
                'View reports',
                'Manage team',
              ])
                AppCheckboxTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(permission, style: const TextStyle(fontSize: 13)),
                  value: chosenPermissions.contains(permission),
                  onChanged: (v) => setState(() {
                    if (v!) {
                      chosenPermissions.add(permission);
                    } else {
                      chosenPermissions.remove(permission);
                    }
                  }),
                ),
            ],
            AppSwitchTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Available to this workspace',
                style: TextStyle(fontSize: 12, color: T.muted),
              ),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
            const SizedBox(height: 24),
            const Panel(
              color: T.wash,
              child: Text(
                'Changes stay in this sample workspace. No external service is contacted.',
                style: TextStyle(fontSize: 12, height: 1.6, color: T.secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FlowPage extends StatefulWidget {
  const FlowPage(this.id, {super.key});
  final String id;
  @override
  State<FlowPage> createState() => _FlowPageState();
}

class _FlowPageState extends State<FlowPage> {
  final nodes = [
    (
      'Customer sends a message',
      'Trigger · New inbound conversation',
      Icons.chat_bubble_outline,
    ),
    (
      'Check business hours',
      'Condition · Mon–Fri, 09:00–18:00',
      Icons.schedule_outlined,
    ),
    (
      'Send a warm welcome',
      'Message · Hello! How can we help?',
      Icons.article_outlined,
    ),
    (
      'Assign to support',
      'Action · Customer experience team',
      Icons.people_outline,
    ),
  ];
  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.id.startsWith('chatbots')
        ? 'Studio assistant'
        : widget.id.startsWith('flows')
        ? 'Delivery address flow'
        : 'Welcome automation',
    subtitle: 'A simple journey, one thoughtful step at a time.',
    actions: [
      AppButton.text(
        onPressed: () => notice(context, 'Flow saved as a preview draft.'),
        child: const Text('Save draft'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Pill('Draft', color: T.brass, fill: T.wash),
            Spacer(),
            Eyebrow('Journey preview'),
          ],
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < nodes.length; i++) ...[
          Panel(
            child: InkWell(
              onTap: () => _edit(i),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: i == 0 ? T.selected : T.wash,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AppIcon(
                      nodes[i].$3,
                      color: i == 0 ? T.green : T.brass,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nodes[i].$1,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          nodes[i].$2,
                          style: const TextStyle(fontSize: 11, color: T.muted),
                        ),
                      ],
                    ),
                  ),
                  const AppIcon(Icons.edit_outlined, size: 17, color: T.brass),
                ],
              ),
            ),
          ),
          if (i < nodes.length - 1)
            const SizedBox(
              height: 42,
              child: AppIcon(Icons.south_rounded, color: T.control, size: 20),
            ),
        ],
        const SizedBox(height: 24),
        AppButton.outlinedIcon(
          onPressed: () => setState(
            () => nodes.add((
              'New step',
              'Action · Choose what happens next',
              Icons.add,
            )),
          ),
          icon: const AppIcon(Icons.add, size: 18),
          label: const Text('Add step'),
        ),
        const SizedBox(height: 20),
        const Text(
          'Tap a step to edit its preview. This flow does not run against live conversations.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: T.muted, height: 1.6),
        ),
      ],
    ),
  );
  void _edit(int index) => sheet(
    context,
    EditorSheet(
      title: 'Edit step',
      fields: [
        ('Step name', nodes[index].$1),
        ('Configuration', nodes[index].$2),
      ],
      onSave: (values) => setState(
        () => nodes[index] = (values[0], values[1], nodes[index].$3),
      ),
    ),
  );
}

class CampaignsPage extends StatelessWidget {
  const CampaignsPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Campaigns',
    subtitle: 'Reach out with something worth opening.',
    actions: [
      AppIconButton(
        tooltip: 'Create campaign',
        onPressed: () => context.push('/campaign/new'),
        icon: const AppIcon(Icons.add),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Panel(
          color: T.selected,
          child: Row(
            children: [
              AppIcon(Icons.campaign_outlined, color: T.green, size: 28),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'A personal touch, even at a little scale.',
                  style: TextStyle(
                    color: T.green,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Section('Recent broadcasts'),
        for (final (id, name, status, audience, time) in [
          (
            'autumn',
            'The autumn edit',
            'Completed',
            '248 customers',
            'Yesterday · 10:00',
          ),
          (
            'followup',
            'A little check-in',
            'Scheduled',
            '86 customers',
            'Tomorrow · 11:00',
          ),
          (
            'welcome',
            'Welcome to the studio',
            'Draft',
            'New customers',
            'Last edited today',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Panel(
              child: InkWell(
                onTap: () => context.push('/campaign/$id'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Pill(
                          status,
                          color: status == 'Completed' ? T.green : T.brass,
                          fill: status == 'Completed' ? T.selected : T.wash,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      audience,
                      style: const TextStyle(fontSize: 12, color: T.secondary),
                    ),
                    const SizedBox(height: 8),
                    Text(time, style: mono(size: 10)),
                  ],
                ),
              ),
            ),
          ),
        MenuRow(
          'Message templates',
          Icons.article_outlined,
          route: '/templates',
        ),
        MenuRow(
          'Template library',
          Icons.library_books_outlined,
          route: '/templates',
        ),
      ],
    ),
  );
}

class CampaignFormPage extends StatefulWidget {
  const CampaignFormPage({super.key});
  @override
  State<CampaignFormPage> createState() => _CampaignFormPageState();
}

class _CampaignFormPageState extends State<CampaignFormPage> {
  int step = 0;
  String name = '',
      audience = 'Customers',
      template = 'welcome',
      schedule = 'Send later';
  DateTime date = DateTime(2026, 10, 29);
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'New campaign',
    bottom: Row(
      children: [
        if (step > 0) ...[
          AppButton.outlined(
            onPressed: () => setState(() => step--),
            child: const Text('Back'),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: AppButton.filled(
            onPressed: () {
              if (step == 0 && !form.currentState!.validate()) return;
              if (step < 2) {
                setState(() => step++);
              } else {
                notice(
                  context,
                  'Campaign preview saved. No messages are scheduled or sent.',
                );
                context.pop();
              }
            },
            child: Text(step == 2 ? 'Save preview' : 'Continue'),
          ),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 3, color: i <= step ? T.green : T.edge),
                      const SizedBox(height: 10),
                      Text(
                        ['Audience', 'Message', 'Review'][i],
                        style: mono(
                          size: 10,
                          color: i == step ? T.green : T.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 30),
        if (step == 0)
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  'Campaign name',
                  value: name,
                  hint: 'e.g. The autumn edit',
                  required: true,
                  onChanged: (v) => name = v,
                ),
                const Section('Choose your audience'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in [
                      'Customers',
                      'VIP',
                      'New leads',
                      'Wholesale',
                    ])
                      AppChoiceChip(
                        label: Text(a),
                        selected: audience == a,
                        onSelected: (_) => setState(() => audience = a),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Panel(
                  child: InfoLine('Sample audience', '248 opted-in customers'),
                ),
              ],
            ),
          )
        else if (step == 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Choose a template'),
              const SizedBox(height: 16),
              for (final t in templates.where((t) => t.status == 'Approved'))
                AppListTile(
                  selected: template == t.id,
                  leading: AppIcon(
                    template == t.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: template == t.id ? T.green : T.control,
                  ),
                  title: Text(t.title, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    t.category,
                    style: const TextStyle(fontSize: 11, color: T.muted),
                  ),
                  onTap: () => setState(() => template = t.id),
                ),
              const Section('Delivery'),
              AppChoiceChip(
                label: const Text('Save as draft'),
                selected: schedule == 'Draft',
                onSelected: (_) => setState(() => schedule = 'Draft'),
              ),
              AppChoiceChip(
                label: const Text('Schedule later'),
                selected: schedule == 'Send later',
                onSelected: (_) => setState(() => schedule = 'Send later'),
              ),
              if (schedule == 'Send later')
                AppButton.textIcon(
                  onPressed: () async {
                    final value = await showAppDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2026, 10, 28),
                      lastDate: DateTime(2028),
                    );
                    if (value != null) setState(() => date = value);
                  },
                  icon: const AppIcon(Icons.event_outlined, size: 18),
                  label: Text('${date.day}/${date.month}/${date.year} · 11:00'),
                ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'One last look.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              Panel(
                child: Column(
                  children: [
                    InfoLine('Campaign', name),
                    InfoLine('Audience', audience),
                    InfoLine('Template', template),
                    InfoLine('Delivery', schedule),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Panel(
                color: T.outgoing,
                child: Text(templates.firstWhere((t) => t.id == template).body),
              ),
              const SizedBox(height: 20),
              const Text(
                'This is a campaign design preview. No live campaign is created.',
                style: TextStyle(color: T.muted, fontSize: 12),
              ),
            ],
          ),
      ],
    ),
  );
}

class CampaignDetailPage extends StatelessWidget {
  const CampaignDetailPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: id == 'autumn'
        ? 'The autumn edit'
        : id == 'followup'
        ? 'A little check-in'
        : 'Welcome to the studio',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Pill('Sample campaign', color: T.brass, fill: T.wash),
            Spacer(),
            Eyebrow('248 recipients'),
          ],
        ),
        const Section('Delivery overview'),
        const StatsGrid(
          values: [
            ('Submitted', '248'),
            ('Delivered', '242'),
            ('Read', '186'),
            ('Replies', '34'),
          ],
        ),
        const Section('Message'),
        const Panel(
          color: T.outgoing,
          child: Text(
            'Hi Ananya, our autumn collection has arrived. Thoughtfully made pieces for slower, better days. Explore the new edit. 🌿',
            style: TextStyle(height: 1.7),
          ),
        ),
        const Section('Audience'),
        const InfoLine('Segment', 'Customers · Opted in'),
        const InfoLine('Sent', '27 October · 10:00'),
        const InfoLine('Template', 'new_collection'),
        const SizedBox(height: 20),
        AppButton.outlined(
          onPressed: () => context.push('/reports?type=Broadcast'),
          child: const Text('View campaign report'),
        ),
      ],
    ),
  );
}

class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.values});
  final List<(String, String)> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final value in values)
          SizedBox(
            width: (size.maxWidth - 12) / 2,
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.$1,
                    style: const TextStyle(fontSize: 11, color: T.muted),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value.$2,
                    style: mono(
                      size: 27,
                      color: T.ink,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

const reportNames = [
  'Delivery',
  'Broadcast',
  'Broadcast messages',
  'AI usage',
  'Wallet spend',
  'Profit & loss',
  'Notification log',
  'WhatsApp flow',
  'Chatbot conversation',
  'Call details',
  'Automation log',
  'Agent performance',
  'Ticket register',
  'Ticket aging',
  'Ticket SLA',
  'Ticket disposition',
  'Ticket volume',
  'Ticket notifications',
  'Link tracking',
];

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.initial = 'Delivery'});
  final String initial;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late String report = reportNames.contains(widget.initial)
      ? widget.initial
      : 'Delivery';
  DateTimeRange range = DateTimeRange(
    start: DateTime(2026, 10, 22),
    end: DateTime(2026, 10, 28),
  );
  List<(String, String)> get metrics {
    if (report.startsWith('Ticket') || report == 'Agent performance') {
      return const [
        ('Created', '42'),
        ('Resolved', '38'),
        ('Avg. response', '3m'),
        ('SLA met', '94%'),
      ];
    }
    return switch (report) {
      'AI usage' => const [
        ('Suggestions', '186'),
        ('Used by team', '142'),
        ('Time saved', '4.2h'),
        ('Acceptance', '76%'),
      ],
      'Wallet spend' => const [
        ('Spent', '₹180'),
        ('Credits', '₹5,000'),
        ('Balance', '₹4,820'),
        ('Transactions', '12'),
      ],
      'Profit & loss' => const [
        ('Revenue', '₹8,400'),
        ('Costs', '₹3,180'),
        ('Gross profit', '₹5,220'),
        ('Margin', '62.1%'),
      ],
      'Call details' => const [
        ('Calls', '42'),
        ('Answered', '36'),
        ('Missed', '6'),
        ('Avg. duration', '3m'),
      ],
      'Automation log' || 'Chatbot conversation' => const [
        ('Runs', '248'),
        ('Completed', '236'),
        ('Hand-offs', '12'),
        ('Success', '95.2%'),
      ],
      'WhatsApp flow' => const [
        ('Started', '86'),
        ('Completed', '72'),
        ('Completion', '83.7%'),
        ('Drop-offs', '14'),
      ],
      'Link tracking' => const [
        ('Clicks', '212'),
        ('Unique clicks', '186'),
        ('Active links', '8'),
        ('Click rate', '24%'),
      ],
      'Notification log' => const [
        ('Sent', '148'),
        ('Delivered', '146'),
        ('Read', '122'),
        ('Failed', '2'),
      ],
      _ => const [
        ('Messages', '1,248'),
        ('Delivered', '98.4%'),
        ('Read', '76.2%'),
        ('Replies', '186'),
      ],
    };
  }

  List<(String, String, String)> get breakdown {
    if (report.startsWith('Ticket') || report == 'Agent performance') {
      return const [
        ('Renav Shah', '24 conversations', '3m 12s'),
        ('Meera Joshi', '18 conversations', '2m 48s'),
        ('Aditya Shah', '16 conversations', '4m 02s'),
      ];
    }
    return switch (report) {
      'Wallet spend' || 'Profit & loss' => const [
        ('Message usage', 'UTILITY & SERVICE', '₹180'),
        ('Wallet top-up', 'CREDIT · 26 OCT', '₹5,000'),
        ('Plan renewal', 'INVOICE · OCT', '₹1,999'),
      ],
      'AI usage' => const [
        ('Draft replies', 'SUGGESTIONS USED', '86'),
        ('Rewrites', 'SUGGESTIONS USED', '42'),
        ('Summaries', 'CONVERSATIONS', '14'),
      ],
      'Call details' => const [
        ('Outgoing', 'ANSWERED CALLS', '24'),
        ('Incoming', 'ANSWERED CALLS', '12'),
        ('Missed', 'FOLLOW-UP NEEDED', '6'),
      ],
      'Link tracking' => const [
        ('Autumn collection', 'UNIQUE CLICKS', '128'),
        ('Order tracking', 'UNIQUE CLICKS', '58'),
      ],
      'Automation log' || 'Chatbot conversation' || 'WhatsApp flow' => const [
        ('Welcome journey', 'COMPLETED', '186'),
        ('Order follow-up', 'COMPLETED', '50'),
        ('Support hand-off', 'TO YOUR TEAM', '12'),
      ],
      _ => const [
        ('Customer updates', 'DELIVERED', '842'),
        ('Campaign messages', 'DELIVERED', '386'),
        ('Follow-up messages', 'DELIVERED', '20'),
      ],
    };
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Reports',
    subtitle: 'A clearer view of the conversations that matter.',
    actions: [
      AppIconButton(
        tooltip: 'Export report preview',
        onPressed: () => notice(
          context,
          'Report export is a preview. No customer data is exported.',
        ),
        icon: const AppIcon(Icons.file_download_outlined, size: 20),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<String>(
          initialValue: report,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Report'),
          items: [
            for (final r in reportNames)
              DropdownMenuItem(value: r, child: Text(r)),
          ],
          onChanged: (v) => setState(() => report = v!),
        ),
        const SizedBox(height: 14),
        AppButton.outlinedIcon(
          onPressed: () async {
            final chosen = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2025),
              lastDate: DateTime(2028),
              initialDateRange: range,
            );
            if (chosen != null) setState(() => range = chosen);
          },
          icon: const AppIcon(Icons.date_range_outlined, size: 17),
          label: Text(
            '${range.start.day}/${range.start.month} – ${range.end.day}/${range.end.month}/${range.end.year}',
          ),
        ),
        const Section('At a glance'),
        StatsGrid(values: metrics),
        const Section('Last 7 days'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 28),
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: [
                                  55.0,
                                  82.0,
                                  66.0,
                                  109.0,
                                  92.0,
                                  121.0,
                                  100.0,
                                ][i],
                                decoration: BoxDecoration(
                                  color: i == 5 ? T.green : T.selected,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                ['T', 'F', 'S', 'S', 'M', 'T', 'W'][i],
                                style: mono(size: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        Section(
          report == 'Agent performance'
              ? 'Team performance'
              : 'Report breakdown',
        ),
        for (final (name, detail, total) in breakdown)
          AppListTile(
            contentPadding: EdgeInsets.zero,
            leading: const AppIcon(Icons.insights_outlined, color: T.brass),
            title: Text(name, style: const TextStyle(fontSize: 13)),
            subtitle: Text(detail, style: mono(size: 10)),
            trailing: Text(total, style: mono(size: 11, color: T.green)),
          ),
        const SizedBox(height: 20),
        const Center(
          child: Pill('Sample report data', color: T.brass, fill: T.wash),
        ),
      ],
    ),
  );
}

class BillingPage extends StatelessWidget {
  const BillingPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Billing & plans',
    subtitle: 'A clear picture of your workspace spending.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          color: T.firm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SAMPLE WALLET BALANCE',
                style: mono(
                  size: 10,
                  color: T.control,
                ).copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 18),
              Text('₹4,820.00', style: mono(size: 32, color: T.paper)),
              const SizedBox(height: 22),
              AppButton.filled(
                onPressed: () => sheet(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Add credit',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      const LabeledField(
                        'Amount',
                        value: '1000',
                        keyboard: TextInputType.number,
                      ),
                      const Text(
                        'Payment setup is not connected in this preview.',
                        style: TextStyle(color: T.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      AppButton.filled(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Add credit'),
              ),
            ],
          ),
        ),
        const Section('Your plan'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    'Business',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  Pill('Sample plan'),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Shared inbox, automation, and a little more room to grow.',
                style: TextStyle(color: T.secondary, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 16),
              AppButton.outlined(
                onPressed: () => context.push('/manage/plans'),
                child: const Text('View plans'),
              ),
            ],
          ),
        ),
        const Section('Recent activity'),
        for (final (title, date, amount) in [
          ('Wallet top-up', '26 OCT · CREDIT', '+ ₹5,000'),
          ('Messaging usage', '27 OCT · DEBIT', '− ₹180'),
          ('Plan renewal', '01 OCT · INVOICE', '₹1,999'),
        ])
          AppListTile(
            contentPadding: EdgeInsets.zero,
            leading: const AppIcon(Icons.receipt_long_outlined, color: T.brass),
            title: Text(title, style: const TextStyle(fontSize: 13)),
            subtitle: Text(date, style: mono(size: 9)),
            trailing: Text(
              amount,
              style: mono(
                size: 12,
                color: amount.startsWith('+') ? T.green : T.ink,
              ),
            ),
            onTap: () => sheet(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  InfoLine('Amount', amount),
                  InfoLine('Date', date),
                  const InfoLine('Status', 'Sample transaction'),
                  const InfoLine('Reference', 'TXN-2026-1028'),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
