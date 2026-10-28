import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'conversation.dart';
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
    actions: [
      IconButton(
        tooltip: 'Create template',
        onPressed: () => context.push('/template/new'),
        icon: const Icon(Icons.add),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBox(
          hint: 'Search templates',
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final c in ['All', 'Utility', 'Marketing'])
              ChoiceChip(
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
                        const Icon(
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
      bottom: FilledButton.icon(
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
        icon: const Icon(Icons.send_outlined, size: 18),
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
                      const Divider(),
                      TextButton(
                        onPressed: () => context.push('/order/2048'),
                        child: const Text(
                          'View order',
                          style: TextStyle(color: T.brass),
                        ),
                      ),
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

class TemplateFormPage extends StatefulWidget {
  const TemplateFormPage({super.key});
  @override
  State<TemplateFormPage> createState() => _TemplateFormPageState();
}

class _TemplateFormPageState extends State<TemplateFormPage> {
  final form = GlobalKey<FormState>();
  String category = 'Utility';
  String body = 'Hi {{1}}, thanks for reaching out. How can we help you today?';
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Create template',
    subtitle: 'Clear, personal messages your customers will appreciate.',
    bottom: FilledButton(
      onPressed: () {
        if (!form.currentState!.validate()) return;
        sheet(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Template draft'),
              const SizedBox(height: 16),
              Panel(color: T.outgoing, child: Text(body)),
              const SizedBox(height: 16),
              const Text(
                'This is a design preview. Template submission will be connected later.',
                style: TextStyle(color: T.muted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to draft'),
              ),
            ],
          ),
        );
      },
      child: const Text('Preview template'),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LabeledField(
            'Template name',
            hint: 'e.g. support_welcome',
            required: true,
          ),
          const Eyebrow('Category'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final c in ['Utility', 'Marketing', 'Authentication'])
                ChoiceChip(
                  label: Text(c),
                  selected: category == c,
                  onSelected: (_) => setState(() => category = c),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const LabeledField('Language', value: 'English'),
          const LabeledField('Header · optional', hint: 'A short introduction'),
          LabeledField(
            'Message body',
            value: body,
            lines: 5,
            required: true,
            onChanged: (v) => body = v,
          ),
          const Text(
            'Use {{1}}, {{2}} for personalised values.',
            style: TextStyle(color: T.muted, fontSize: 11),
          ),
          const SizedBox(height: 20),
          const LabeledField('Footer · optional', hint: 'Your closing line'),
          const LabeledField(
            'Button label · optional',
            hint: 'e.g. View order',
          ),
        ],
      ),
    ),
  );
}

class QuickRepliesPage extends StatefulWidget {
  const QuickRepliesPage({super.key, this.pick = false});
  final bool pick;
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
    actions: [
      IconButton(
        tooltip: 'Add quick reply',
        onPressed: _add,
        icon: const Icon(Icons.add),
      ),
    ],
    child: Column(
      children: [
        SearchBox(
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
                onTap: () {
                  if (widget.pick) {
                    context.pop(r.$2);
                  } else {
                    sheet(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(r.$1, style: mono(size: 16, color: T.green)),
                          const SizedBox(height: 20),
                          Text(r.$2),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context.push(
                                '/contacts?draft=${Uri.encodeComponent(r.$2)}',
                              );
                            },
                            child: const Text('Choose a conversation'),
                          ),
                        ],
                      ),
                    );
                  }
                },
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
  void _add() => sheet(
    context,
    EditorSheet(
      title: 'New quick reply',
      fields: const [('Shortcut', ''), ('Reply', '')],
      onSave: (values) => setState(() => replies.add((values[0], values[1]))),
    ),
  );
}

class AiPage extends StatefulWidget {
  const AiPage({super.key, this.returnDraft = false});
  final bool returnDraft;
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  String mode = 'Draft reply', tone = 'Warm', result = '';
  final draft = TextEditingController(
    text: 'Thanks for your message! Your order is packed and will arrive by Friday.',
  );
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'AI assist',
    subtitle: 'A helping hand. Your voice, always.',
    bottom: result.isEmpty
        ? null
        : FilledButton(
            onPressed: () {
              if (widget.returnDraft) {
                context.pop(result);
              } else {
                context.push('/contacts?draft=${Uri.encodeComponent(result)}');
              }
            },
            child: const Text('Use this draft'),
          ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Panel(
          color: T.selected,
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 24, color: T.green),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Thoughtful replies start with a little inspiration.',
                  style: TextStyle(fontSize: 13, color: T.green, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const Section('What would you like to do?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in [
              'Draft reply',
              'Rewrite',
              'Translate',
              'Summarise',
              'Suggest template',
              'Extract fields',
            ])
              ChoiceChip(
                label: Text(value),
                selected: mode == value,
                onSelected: (_) => setState(() {
                  mode = value;
                  result = '';
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        LabeledField(
          mode == 'Summarise'
              ? 'Conversation context'
              : 'Your draft or instructions',
          controller: draft,
          lines: 4,
        ),
        const Eyebrow('Tone'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['Warm', 'Professional', 'Concise'])
              ChoiceChip(
                label: Text(value),
                selected: tone == value,
                onSelected: (_) => setState(() => tone = value),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => setState(
            () => result = switch (mode) {
              'Translate' => 'आपके संदेश के लिए धन्यवाद! आपका ऑर्डर पैक हो गया है और शुक्रवार तक पहुँच जाएगा।',
              'Summarise' => 'Ananya asked about order ST-2048. Delivery is expected by Friday. The invoice has been shared. No further action is required.',
              'Extract fields' => 'Customer: Ananya Shah\nOrder: ST-2048\nExpected delivery: Friday\nTopic: Order enquiry',
              'Suggest template' => 'Recommended: shipping_update\nCategory: Utility\nVariables: Ananya · ST-2048',
              _ =>
                tone == 'Concise'
                    ? 'Your order is packed and arrives by Friday. Thank you, Ananya!'
                    : 'Hi Ananya! Your order is packed with care and should arrive by Friday. We’ve also shared your invoice. Let us know if there’s anything else we can help with. 🌿',
            },
          ),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: const Text('Generate preview'),
        ),
        if (result.isNotEmpty) ...[
          const Section('Suggested response'),
          Panel(child: Text(result, style: const TextStyle(height: 1.7))),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              draft.text = result;
              result = '';
            }),
            child: const Text('Edit this draft'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Sample suggestions for design review. Review every draft before sharing.',
          style: TextStyle(color: T.muted, fontSize: 11, height: 1.5),
        ),
      ],
    ),
  );
}

class CataloguePage extends StatefulWidget {
  const CataloguePage({super.key, this.contact});
  final String? contact;
  @override
  State<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends State<CataloguePage> {
  String search = '', category = 'All';
  @override
  Widget build(BuildContext context) {
    final list = products
        .where(
          (p) =>
              p.name.toLowerCase().contains(search.toLowerCase()) &&
              (category == 'All' || p.category == category),
        )
        .toList();
    return PageFrame(
      title: 'Catalogue',
      subtitle: 'Thoughtfully made, for everyday.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBox(
            hint: 'Search products',
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in [
                'All',
                'Bags & carry',
                'Desk essentials',
                'Home & living',
              ])
                ChoiceChip(
                  label: Text(c),
                  selected: category == c,
                  onSelected: (_) => setState(() => category = c),
                ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth > 600 ? 3 : 2,
                childAspectRatio: .67,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                return InkWell(
                  onTap: () => context.push(
                    '/product/${p.id}${widget.contact == null ? '' : '?contact=${widget.contact}'}',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ProductArt(icon: p.icon, color: p.color),
                      ),
                      const SizedBox(height: 12),
                      Text(p.category, style: mono(size: 9)),
                      const SizedBox(height: 5),
                      Text(
                        p.name,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(p.price, style: mono(size: 13, color: T.ink)),
                    ],
                  ),
                );
              },
            ),
          ),
          if (list.isEmpty)
            const EmptyView(
              title: 'No products found',
              description: 'Try another search or category.',
              icon: Icons.shopping_bag_outlined,
            ),
        ],
      ),
    );
  }
}

class ProductPage extends ConsumerWidget {
  const ProductPage(this.id, {super.key, this.contact});
  final String id;
  final String? contact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = products.firstWhere(
      (p) => p.id == id,
      orElse: () => products.first,
    );
    return PageFrame(
      title: 'Product details',
      bottom: FilledButton.icon(
        onPressed: () {
          if (contact != null) {
            ref
                .read(previewProvider.notifier)
                .send(contact!, '${p.name}\n${p.price}', type: 'image');
            context.pop();
            notice(context, 'Product added to preview conversation.');
          } else {
            context.push('/contacts?product=$id');
          }
        },
        icon: const Icon(Icons.share_outlined, size: 18),
        label: const Text('Share in a conversation'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 280,
            child: ProductArt(icon: p.icon, color: p.color),
          ),
          const SizedBox(height: 26),
          Eyebrow(p.category),
          const SizedBox(height: 10),
          Text(p.name, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(p.price, style: mono(size: 23, color: T.ink)),
              const Spacer(),
              const Pill('In stock', dot: true),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Made with care for the moments in between. A considered everyday essential, designed to feel at home in your routine.',
            style: TextStyle(height: 1.8, color: T.secondary),
          ),
          const Section('The details'),
          const InfoLine('Colour', 'Natural'),
          const InfoLine('Collection', 'Everyday essentials'),
          InfoLine('Product ID', 'SN-${p.id.toUpperCase()}'),
          const InfoLine('Delivery', '3–5 business days'),
        ],
      ),
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Orders',
    subtitle: 'From the first hello to a happy delivery.',
    child: Column(
      children: [
        const SearchBox(hint: 'Search orders'),
        const SizedBox(height: 20),
        for (final (id, name, status, total) in [
          ('2048', 'Ananya Shah', 'Packed', '₹1,290'),
          ('2047', 'Priya Nair', 'Shipped', '₹1,580'),
          ('2046', 'Kabir Kapoor', 'Delivered', '₹690'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Panel(
              child: InkWell(
                onTap: () => context.push('/order/$id'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#ST-$id', style: mono(size: 13, color: T.ink)),
                        const Spacer(),
                        Pill(status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Everyday essentials',
                          style: TextStyle(fontSize: 12, color: T.muted),
                        ),
                        const Spacer(),
                        Text(total, style: mono(size: 13, color: T.ink)),
                      ],
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

class OrderPage extends StatelessWidget {
  const OrderPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Order #ST-$id',
    actions: [
      IconButton(
        tooltip: 'Message customer',
        onPressed: () => context.push('/chat/ananya'),
        icon: const Icon(Icons.chat_bubble_outline, size: 20),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Pill('Packed', dot: true),
            Spacer(),
            Eyebrow('28 OCT 2026'),
          ],
        ),
        const Section('Customer'),
        const Panel(
          child: Column(
            children: [
              InfoLine('Name', 'Ananya Shah'),
              InfoLine('Phone', '+91 98765 43210'),
              InfoLine(
                'Address',
                '12, Riverfront Apartments\nAhmedabad, Gujarat · 380009',
              ),
            ],
          ),
        ),
        const Section('Order items'),
        Panel(
          child: Column(
            children: [
              Row(
                children: [
                  const ProductArt(
                    icon: Icons.shopping_bag_outlined,
                    small: true,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Everyday canvas tote',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text(
                          'Natural · Qty 1',
                          style: TextStyle(color: T.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text('₹1,290', style: mono(color: T.ink)),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const InfoLine('Subtotal', '₹1,290'),
              const InfoLine('Delivery', 'Complimentary'),
              const Divider(),
              const InfoLine('Total', '₹1,290'),
            ],
          ),
        ),
        const Section('Delivery timeline'),
        for (final step in [
          ('Order confirmed', 'Yesterday · 14:20', true),
          ('Packed with care', 'Today · 09:15', true),
          ('On its way', 'Waiting for pickup', false),
          ('Delivered', 'Expected Friday', false),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Icon(
                  step.$3 ? Icons.check_circle : Icons.circle_outlined,
                  color: step.$3 ? T.green : T.control,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.$1,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(step.$2, style: mono(size: 10)),
                    ],
                  ),
                ),
              ],
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
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create ticket',
        backgroundColor: T.green,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => context.push('/ticket/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Tickets',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    const Pill('Support', color: T.brass, fill: T.wash),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Every issue deserves a little care.',
                  style: TextStyle(color: T.muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                SearchBox(
                  hint: 'Search tickets or customers',
                  onChanged: (v) => setState(() => search = v),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final s in ['Open', 'Pending', 'Resolved', 'All'])
                      ChoiceChip(
                        label: Text(s),
                        selected: status == s,
                        onSelected: (_) => setState(() => status = s),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: tickets.isEmpty
                ? const EmptyView(
                    title: 'All clear in this view.',
                    description: 'Your team is keeping things moving.',
                    icon: Icons.task_alt_rounded,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                    children: [
                      for (final t in tickets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Panel(
                            child: InkWell(
                              onTap: () => context.push('/ticket/${t.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('#${t.id}', style: mono(size: 11)),
                                      const Spacer(),
                                      Pill(
                                        t.priority,
                                        color: t.priority == 'High'
                                            ? T.danger
                                            : T.brass,
                                        fill: t.priority == 'High'
                                            ? const Color(0xFFF6E0E7)
                                            : T.wash,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    t.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Avatar(
                                        person(state, t.personId).name,
                                        size: 28,
                                        color: person(state, t.personId).color,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          person(state, t.personId).name,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Pill(t.status),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.schedule,
                                        size: 13,
                                        color: T.brass,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        t.priority == 'High'
                                            ? 'Response due in 24m'
                                            : 'Within response target',
                                        style: mono(
                                          size: 9,
                                          color: t.priority == 'High'
                                              ? T.danger
                                              : T.muted,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        t.department,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: T.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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
      bottom: FilledButton.icon(
        onPressed: () => context.push('/chat/${p.id}'),
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
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
                IconButton(
                  tooltip: 'Customer details',
                  onPressed: () => context.push('/customer/${p.id}'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
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
                ChoiceChip(
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
    bottom: FilledButton(
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
          DropdownButtonFormField<String>(
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
                ChoiceChip(
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

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Calls',
    subtitle: 'Some things are better said out loud.',
    actions: [
      IconButton(
        tooltip: 'New call',
        onPressed: () => context.push('/contacts?pick=call'),
        icon: const Icon(Icons.add_call),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final f in ['All', 'Missed'])
              ChoiceChip(
                label: Text(f),
                selected: filter == f,
                onSelected: (_) => setState(() => filter = f),
              ),
          ],
        ),
        const Section('Today'),
        for (final c in [
          ('Ananya Shah', 'ananya', '10:12 · 3m 24s', false),
          ('Ishita Rao', 'ishita', '09:32 · Missed call', true),
          ('Rohan Mehta', 'rohan', '09:10 · 1m 42s', false),
        ])
          if (filter == 'All' || c.$4)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              leading: Avatar(c.$1),
              title: Text(
                c.$1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      c.$4 ? Icons.call_missed : Icons.call_made,
                      size: 14,
                      color: c.$4 ? T.danger : T.green,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      c.$3,
                      style: mono(size: 10, color: c.$4 ? T.danger : T.muted),
                    ),
                  ],
                ),
              ),
              trailing: IconButton(
                tooltip: 'Call ${c.$1}',
                onPressed: () => context.push('/call/${c.$2}'),
                icon: const Icon(Icons.call_outlined, size: 21),
              ),
            ),
        const Section('Call previews'),
        MenuRow(
          'Incoming call',
          Icons.ring_volume_outlined,
          route: '/call/incoming',
        ),
        MenuRow(
          'Call settings',
          Icons.settings_outlined,
          route: '/settings/calls',
        ),
      ],
    ),
  );
}

class CallPage extends ConsumerStatefulWidget {
  const CallPage(this.id, {super.key, this.incoming = false});
  final String id;
  final bool incoming;
  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  bool muted = false, speaker = false, accepted = false;
  @override
  Widget build(BuildContext context) {
    final p = person(ref.watch(previewProvider), widget.id);
    final incoming = widget.incoming && !accepted;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: T.firm,
      ),
      child: Scaffold(
        backgroundColor: T.firm,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: T.paper,
                      ),
                    ),
                    const Spacer(),
                    const Pill(
                      'Call preview',
                      color: T.paper,
                      fill: T.secondary,
                    ),
                  ],
                ),
                const Spacer(),
                Avatar(p.name, size: 106, color: p.color),
                const SizedBox(height: 26),
                Text(
                  p.name,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: T.paper),
                ),
                const SizedBox(height: 10),
                Text(p.phone, style: mono(size: 13, color: T.control)),
                const SizedBox(height: 24),
                Text(
                  incoming
                      ? 'Incoming WhatsApp voice call'
                      : 'Voice call · 00:00',
                  style: mono(size: 12, color: T.control),
                ),
                const Spacer(),
                if (!incoming)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _control(
                        muted ? Icons.mic_off_outlined : Icons.mic_none_rounded,
                        'Mute',
                        muted,
                        () => setState(() => muted = !muted),
                      ),
                      _control(
                        Icons.volume_up_outlined,
                        'Speaker',
                        speaker,
                        () => setState(() => speaker = !speaker),
                      ),
                      _control(
                        Icons.note_alt_outlined,
                        'Notes',
                        false,
                        () => sheet(
                          context,
                          const Column(
                            children: [
                              LabeledField(
                                'Call notes',
                                hint: 'Keep a note of the conversation',
                                lines: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        IconButton.filled(
                          tooltip: incoming ? 'Decline call' : 'End call',
                          style: IconButton.styleFrom(
                            backgroundColor: T.danger,
                            fixedSize: const Size(66, 66),
                          ),
                          onPressed: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/more');
                            }
                          },
                          icon: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          incoming ? 'Decline' : 'End call',
                          style: const TextStyle(
                            color: T.control,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    if (incoming)
                      Column(
                        children: [
                          IconButton.filled(
                            tooltip: 'Accept call',
                            style: IconButton.styleFrom(
                              backgroundColor: T.green,
                              fixedSize: const Size(66, 66),
                            ),
                            onPressed: () => setState(() => accepted = true),
                            icon: const Icon(
                              Icons.call,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Accept',
                            style: TextStyle(color: T.control, fontSize: 11),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Preview only · no call is placed',
                  style: mono(size: 10, color: T.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _control(
    IconData icon,
    String title,
    bool selected,
    VoidCallback action,
  ) => Column(
    children: [
      IconButton(
        tooltip: title,
        style: IconButton.styleFrom(
          backgroundColor: selected ? T.paper : T.secondary,
          fixedSize: const Size(52, 52),
        ),
        onPressed: action,
        icon: Icon(icon, color: selected ? T.ink : T.paper),
      ),
      const SizedBox(height: 9),
      Text(title, style: const TextStyle(color: T.control, fontSize: 11)),
    ],
  );
}
