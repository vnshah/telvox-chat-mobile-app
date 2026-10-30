import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'theme.dart';

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key, this.contact});
  final String? contact;
  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  String search = '', category = 'All';
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Message templates',
    subtitle: 'A thoughtful start to every conversation.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBox(
          value: search,
          hint: 'Search templates',
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final c in ['All', 'Utility', 'Marketing'])
              AppChoiceChip(
                label: Text(c),
                selected: c == category,
                onSelected: (_) => setState(() => category = c),
              ),
          ],
        ),
        const SizedBox(height: 18),
        for (final t in templates.where(
          (t) =>
              '${t.name} ${t.title}'.toLowerCase().contains(
                search.toLowerCase(),
              ) &&
              (category == 'All' || category == t.category),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Panel(
              child: InkWell(
                onTap: () => context.push(
                  '/template/${t.id}${widget.contact == null ? '' : '?contact=${widget.contact}'}',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Pill(
                          t.status,
                          color: t.status == 'Approved' ? T.green : T.brass,
                          fill: t.status == 'Approved' ? T.selected : T.wash,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(t.name, style: mono(size: 10)),
                    const SizedBox(height: 14),
                    Text(
                      t.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: T.secondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Pill(t.category, color: T.brass, fill: T.wash),
                        const SizedBox(width: 8),
                        Text('English', style: mono(size: 10)),
                        const Spacer(),
                        const AppIcon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: T.brass,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (templates
            .where(
              (t) =>
                  '${t.name} ${t.title}'.toLowerCase().contains(
                    search.toLowerCase(),
                  ) &&
                  (category == 'All' || category == t.category),
            )
            .isEmpty)
          const EmptyView(
            title: 'No matching templates',
            description: 'Try another search or category.',
            icon: Icons.article_outlined,
          ),
      ],
    ),
  );
}

class TemplatePreviewPage extends ConsumerStatefulWidget {
  const TemplatePreviewPage(this.id, {super.key, this.contact});
  final String id;
  final String? contact;
  @override
  ConsumerState<TemplatePreviewPage> createState() =>
      _TemplatePreviewPageState();
}

class _TemplatePreviewPageState extends ConsumerState<TemplatePreviewPage> {
  String name = 'Ananya', order = 'ST-2048';
  @override
  Widget build(BuildContext context) {
    final template = templates.firstWhere(
      (t) => t.id == widget.id,
      orElse: () => templates.first,
    );
    final body = template.body
        .replaceAll('{{1}}', name.isEmpty ? '{{1}}' : name)
        .replaceAll('{{2}}', order.isEmpty ? '{{2}}' : order);
    return PageFrame(
      title: template.title,
      subtitle: template.name,
      bottom: AppButton.filledIcon(
        onPressed: template.status != 'Approved'
            ? null
            : () {
                if (widget.contact != null) {
                  ref
                      .read(previewProvider.notifier)
                      .send(widget.contact!, body);
                  context.pop();
                  notice(
                    context,
                    'Template added to the preview conversation.',
                  );
                } else {
                  context.push('/contacts?template=${widget.id}');
                }
              },
        icon: const AppIcon(Icons.send_outlined, size: 18),
        label: Text(
          widget.contact == null
              ? 'Choose a conversation'
              : 'Add to conversation',
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Pill(template.status),
              const SizedBox(width: 8),
              Pill(template.category, color: T.brass, fill: T.wash),
            ],
          ),
          const Section('Personalise message'),
          LabeledField(
            'Customer name · {{1}}',
            value: name,
            onChanged: (v) => setState(() => name = v),
          ),
          if (template.body.contains('{{2}}'))
            LabeledField(
              'Order reference · {{2}}',
              value: order,
              onChanged: (v) => setState(() => order = v),
            ),
          const Section('Message preview'),
          Panel(
            color: T.wash,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  color: T.outgoing,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STUDIO NORTH',
                        style: mono(size: 10, color: T.green),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        body,
                        style: const TextStyle(fontSize: 13, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Thoughtfully made, for everyday.',
                        style: const TextStyle(color: T.muted, fontSize: 10),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Preview only. No message is sent to WhatsApp.',
            style: TextStyle(fontSize: 11, color: T.muted),
          ),
        ],
      ),
    );
  }
}

/// Picker for existing quick replies; managing them is out of mobile scope.
class QuickRepliesPage extends StatefulWidget {
  const QuickRepliesPage({super.key});
  @override
  State<QuickRepliesPage> createState() => _QuickRepliesPageState();
}

class _QuickRepliesPageState extends State<QuickRepliesPage> {
  String search = '';
  final replies = <(String, String)>[
    (
      '/hello',
      'Hi there! Welcome to Studio North. How can we help you today? 🌿',
    ),
    (
      '/shipping',
      'Orders usually arrive in 3–5 business days. We’ll share tracking details as soon as yours ships.',
    ),
    (
      '/thanks',
      'You’re most welcome! Always happy to help. Have a lovely day.',
    ),
    (
      '/returns',
      'We accept returns within 7 days of delivery. Could you share your order number?',
    ),
  ];
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Quick replies',
    subtitle: 'A little less typing. The same personal touch.',
    child: Column(
      children: [
        SearchBox(
          value: search,
          hint: 'Search saved replies',
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 20),
        for (final r in replies.where(
          (r) => '${r.$1} ${r.$2}'.toLowerCase().contains(search.toLowerCase()),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: InkWell(
                onTap: () => context.pop(r.$2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$1, style: mono(size: 12, color: T.green)),
                    const SizedBox(height: 10),
                    Text(
                      r.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: T.secondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class TicketsPage extends ConsumerStatefulWidget {
  const TicketsPage({super.key});
  @override
  ConsumerState<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends ConsumerState<TicketsPage> {
  String status = 'Open', search = '';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(previewProvider);
    final tickets = state.tickets
        .where(
          (t) =>
              (status == 'All' || t.status == status) &&
              '${t.title} ${t.id} ${person(state, t.personId).name}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: AppFab(
        tooltip: 'Create ticket',

        onPressed: () => context.push('/ticket/new'),
        child: const AppIcon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchBox(
                  value: search,
                  hint: 'Search tickets or customers',
                  dense: true,
                  onChanged: (v) => setState(() => search = v),
                ),
                const SizedBox(height: 8),
                PlatformFilters(
                  options: const ['Open', 'Pending', 'Resolved', 'All'],
                  selected: status,
                  onSelected: (value) => setState(() => status = value),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: tickets.isEmpty
                ? const EmptyView(
                    title: 'All clear in this view.',
                    description: 'Your team is keeping things moving.',
                    icon: Icons.task_alt_rounded,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: tickets.length,
                    separatorBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.only(left: 72),
                      child: Divider(),
                    ),
                    itemBuilder: (context, i) {
                      final t = tickets[i];
                      final p = person(state, t.personId);
                      return InkWell(
                        key: ValueKey('ticket-row-${t.id}'),
                        onTap: () => context.push('/ticket/${t.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Avatar(p.name, size: 40, color: p.color),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          t.priority,
                                          style: mono(
                                            size: 10,
                                            color: t.priority == 'High'
                                                ? T.danger
                                                : T.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${p.name} · #${t.id}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: T.muted,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          t.status,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: T.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class TicketDetailPage extends ConsumerWidget {
  const TicketDetailPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewProvider);
    final t = state.tickets.firstWhere(
      (t) => t.id == id,
      orElse: () => state.tickets.first,
    );
    final p = person(state, t.personId);
    return PageFrame(
      title: 'Ticket #${t.id}',
      subtitle: t.title,
      bottom: AppButton.filledIcon(
        onPressed: () => context.push('/chat/${p.id}'),
        icon: const AppIcon(Icons.chat_bubble_outline, size: 18),
        label: const Text('Open conversation'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Pill(t.status),
              const SizedBox(width: 8),
              Pill(
                t.priority,
                color: t.priority == 'High' ? T.danger : T.brass,
                fill: T.wash,
              ),
            ],
          ),
          const Section('Customer'),
          Panel(
            child: Row(
              children: [
                Avatar(p.name, color: p.color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(p.phone, style: mono(size: 10)),
                    ],
                  ),
                ),
                AppIconButton(
                  tooltip: 'Customer details',
                  onPressed: () => context.push('/customer/${p.id}'),
                  icon: const AppIcon(Icons.arrow_forward, size: 18),
                ),
              ],
            ),
          ),
          const Section('Ticket details'),
          Panel(
            child: Column(
              children: [
                InfoLine('Department', t.department),
                const InfoLine('Assigned to', 'Renav Shah'),
                const InfoLine('Created', 'Today · 09:40'),
                const InfoLine('Channel', 'WhatsApp'),
                InfoLine('Priority', t.priority),
              ],
            ),
          ),
          const Section('Status'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['Open', 'Pending', 'Resolved'])
                AppChoiceChip(
                  label: Text(s),
                  selected: t.status == s,
                  onSelected: (_) =>
                      ref.read(previewProvider.notifier).ticketStatus(t.id, s),
                ),
            ],
          ),
          const Section('Tools'),
          MenuRow(
            'Internal notes',
            Icons.notes_outlined,
            route: '/customer/${p.id}/notes',
          ),
          MenuRow(
            'Labels',
            Icons.sell_outlined,
            route: '/customer/${p.id}/tags',
          ),
          MenuRow(
            'Assignment',
            Icons.person_outline,
            route: '/customer/${p.id}/assign',
          ),
          MenuRow(
            'Disposition',
            Icons.fact_check_outlined,
            onTap: () => sheet(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set disposition',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  for (final value in [
                    'Resolved · Information provided',
                    'Resolved · Order updated',
                    'Follow-up required',
                    'Escalated to team',
                  ])
                    MenuRow(
                      value,
                      Icons.radio_button_unchecked,
                      onTap: () {
                        Navigator.pop(context);
                        notice(context, 'Disposition selected in preview.');
                      },
                    ),
                ],
              ),
            ),
          ),
          const Section('Activity'),
          const Panel(
            color: T.wash,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigned to you',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 5),
                Text(
                  'Today · 09:42',
                  style: TextStyle(color: T.muted, fontSize: 11),
                ),
                SizedBox(height: 16),
                Text(
                  'Ticket created from WhatsApp',
                  style: TextStyle(fontSize: 13),
                ),
                SizedBox(height: 5),
                Text(
                  'Today · 09:40',
                  style: TextStyle(color: T.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TicketFormPage extends ConsumerStatefulWidget {
  const TicketFormPage({super.key});
  @override
  ConsumerState<TicketFormPage> createState() => _TicketFormPageState();
}

class _TicketFormPageState extends ConsumerState<TicketFormPage> {
  final form = GlobalKey<FormState>(), subject = TextEditingController();
  String customer = 'ananya', priority = 'Medium';
  @override
  void dispose() {
    subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Create ticket',
    subtitle: 'Give your customer’s question a place to land.',
    bottom: AppButton.filled(
      onPressed: () {
        if (!form.currentState!.validate()) return;
        ref
            .read(previewProvider.notifier)
            .ticket(subject.text, customer, priority);
        context.pop();
        notice(context, 'Ticket created in preview.');
      },
      child: const Text('Create ticket'),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            'Subject',
            controller: subject,
            hint: 'What does the customer need?',
            required: true,
          ),
          AppDropdownField<String>(
            initialValue: customer,
            decoration: const InputDecoration(labelText: 'Customer'),
            items: [
              for (final p in ref.watch(previewProvider).people)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => customer = v!,
          ),
          const SizedBox(height: 22),
          const LabeledField('Department', value: 'Support'),
          const Eyebrow('Priority'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final p in ['Low', 'Medium', 'High'])
                AppChoiceChip(
                  label: Text(p),
                  selected: priority == p,
                  onSelected: (_) => setState(() => priority = p),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const LabeledField(
            'Description',
            hint: 'Add a little context for your team',
            lines: 5,
          ),
          const LabeledField('Assigned to', value: 'You'),
        ],
      ),
    ),
  );
}
