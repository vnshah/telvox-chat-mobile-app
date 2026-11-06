import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';

/// The three product messages the web inbox's "Send a product" makes.
enum ProductMessage {
  single('single_product', 'Single Product'),
  multiple('multiple_product', 'Multiple Products'),
  catalogue('catalogue', 'Catalogue');

  const ProductMessage(this.type, this.label);
  final String type, label;
}

/// Products from the number's catalogues, as the web's product form sends
/// them: one product, up to 30 in a list (with a header), or the whole
/// catalogue behind a thumbnail product. Answers with the send's fields.
class ProductSendPage extends StatefulWidget {
  const ProductSendPage(this.session, {super.key});
  final MobileSession session;

  /// The most products one list message takes, as the web form allows.
  static const maxProducts = 30;
  @override
  State<ProductSendPage> createState() => _ProductSendPageState();
}

class _ProductSendPageState extends State<ProductSendPage> {
  var kind = ProductMessage.single;
  List<Json>? catalogues;
  Json? catalogue;
  List<Json> products = [];
  int? product;
  final picked = <int>{};
  final header = TextEditingController(),
      body = TextEditingController(),
      footer = TextEditingController();
  bool loadingProducts = false;
  String? error;

  MobileApi get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    loadCatalogues();
  }

  @override
  void dispose() {
    header.dispose();
    body.dispose();
    footer.dispose();
    super.dispose();
  }

  Future<void> loadCatalogues() async {
    try {
      final list = rows((await api.get('inbox/get-catalogues'))['catalogues']);
      if (!mounted) return;
      if (list.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Catalogues not available.')),
        );
        return;
      }
      setState(() => catalogues = list);
      // The first catalogue opens chosen, as on the web.
      await choose(list.first);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> choose(Json next) async {
    setState(() {
      catalogue = next;
      products = [];
      product = null;
      picked.clear();
      loadingProducts = true;
    });
    try {
      final list = rows(
        (await api.get(
          'inbox/get-products',
          query: {'catalogue_id': next['id']},
        ))['products'],
      );
      if (mounted && catalogue == next) setState(() => products = list);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
  }

  String? optional(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// The web form's checks, in its words, then the send's fields.
  void send() {
    final text = body.text.trim();
    String? problem;
    if (text.isEmpty) {
      problem = 'Please enter message';
    } else if (catalogue == null) {
      problem = 'Please select a catalogue';
    } else if (kind != ProductMessage.multiple && product == null) {
      problem = 'Please select a product';
    } else if (kind == ProductMessage.multiple && picked.isEmpty) {
      problem = 'Please select at least one product';
    } else if (kind == ProductMessage.multiple && optional(header) == null) {
      // WhatsApp refuses a product list without a header.
      problem = 'Please enter a header';
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.pop<Json>(context, {
      'message_type': kind.type,
      'body': text,
      if (kind != ProductMessage.catalogue)
        'catalog_id': '${catalogue!['fb_catalogue_id']}',
      if (kind == ProductMessage.multiple)
        // The server reads the list as ids joined by commas.
        'multipleProduct': [
          for (final p in products)
            if (picked.contains(number(p['id']))) number(p['id']),
        ].join(',')
      else
        'singleProduct': product,
      'header': kind == ProductMessage.multiple ? optional(header) : null,
      'footer': optional(footer),
    });
  }

  Widget label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: T.secondary,
      ),
    ),
  );

  Widget input(
    String key,
    TextEditingController c,
    String hint, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: AppTextFormField(
      key: ValueKey('product-$key'),
      controller: c,
      bordered: true,
      minLines: lines > 1 ? lines : null,
      maxLines: lines > 1 ? lines + 4 : 1,
      decoration: InputDecoration(hintText: hint),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final list = catalogues;
    final multiple = kind == ProductMessage.multiple;
    return Scaffold(
      appBar: AppBar(title: const Text('Send a product')),
      body: list == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(error!, textAlign: TextAlign.center),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SegmentedButton<ProductMessage>(
                    showSelectedIcon: false,
                    segments: [
                      for (final k in ProductMessage.values)
                        ButtonSegment(value: k, label: Text(k.label)),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setState(() {
                      kind = s.first;
                      error = null;
                    }),
                  ),
                ),
                label('Catalogue'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<Object?>(
                    key: const ValueKey('product-catalogue'),
                    initialValue: catalogue?['id'],
                    isExpanded: true,
                    items: [
                      for (final c in list)
                        DropdownMenuItem(
                          value: c['id'],
                          child: Text(
                            '${c['name']} (${c['product_count'] ?? 0} Products)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      final next = list.firstWhere((c) => c['id'] == id);
                      if (next != catalogue) choose(next);
                    },
                  ),
                ),
                if (loadingProducts)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else if (multiple) ...[
                  label(
                    'Products (Max ${ProductSendPage.maxProducts}) · '
                    'Selected: ${picked.length} / ${ProductSendPage.maxProducts}',
                  ),
                  for (final p in products)
                    if (number(p['id']) case final int id)
                      CheckboxListTile(
                        key: ValueKey('product-$id'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('${p['name'] ?? ''}'),
                        subtitle: Text('${p['price'] ?? ''}'),
                        value: picked.contains(id),
                        onChanged:
                            !picked.contains(id) &&
                                picked.length >= ProductSendPage.maxProducts
                            ? null
                            : (on) => setState(
                                () => on == true
                                    ? picked.add(id)
                                    : picked.remove(id),
                              ),
                      ),
                ] else ...[
                  label(
                    kind == ProductMessage.catalogue
                        ? 'Thumbnail Product'
                        : 'Product',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('product-single-${catalogue?['id']}'),
                      initialValue: product,
                      isExpanded: true,
                      hint: const Text('Choose…'),
                      items: [
                        for (final p in products)
                          if (number(p['id']) case final int id)
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                '${p['name'] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (id) => setState(() => product = id),
                    ),
                  ),
                ],
                if (multiple) ...[
                  label('Header *'),
                  input('header', header, 'Enter Header'),
                ],
                label('Add your message *'),
                input('body', body, 'Add your message...', lines: 3),
                label('Footer'),
                input('footer', footer, 'Enter Footer'),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      error!,
                      style: const TextStyle(color: T.danger, fontSize: 13),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: AppButton.filled(
                    key: const ValueKey('product-send'),
                    onPressed: loadingProducts ? null : send,
                    child: const Text('Send'),
                  ),
                ),
              ],
            ),
    );
  }
}
