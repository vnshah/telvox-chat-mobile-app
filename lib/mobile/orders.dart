import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'message_content.dart' show readableText;
import 'models.dart';

/// Orders and payments in a chat, as WhatsApp shows them to the customer and
/// the web inbox previews them: a customer's cart ([orderOf]), a request to
/// pay for an order ([orderDetailsOf]), and an update on an order's progress
/// ([orderStatusOf]).
///
/// Amounts come from WhatsApp's own payload, so a cart is right whether or
/// not its catalogue is synced here; the server only adds each product's
/// name and picture when it has them.

/// One line of an order: what, how many, and at what unit price.
typedef OrderItem = ({
  String retailerId,
  String name,
  String image,
  int quantity,
  num price,
});

/// A customer's cart sent from the business's catalogue.
class CustomerOrder {
  const CustomerOrder({
    required this.items,
    required this.currency,
    this.note = '',
    this.thumbnail = '',
  });
  final List<OrderItem> items;
  final String currency;

  /// What the customer typed with the cart, if anything.
  final String note;
  final String thumbnail;

  int get count => items.fold(0, (sum, i) => sum + i.quantity);
  num get total => items.fold<num>(0, (sum, i) => sum + i.quantity * i.price);

  /// Whether every product is named; when not, its catalogue is not synced.
  bool get named => items.every((i) => i.name.isNotEmpty);

  String get countLabel => '$count ${count == 1 ? 'item' : 'items'}';
}

CustomerOrder? orderOf(ApiMessage m) {
  if (m.type != 'order') return null;
  final body = object(decoded(m.json['message_body_json']));
  final order = object(body['order']);
  final raw = rows(order['product_items']);
  if (raw.isEmpty) return null;
  // The server's products: the same items in the same order, with the
  // catalogue's name and picture where it has them.
  final known = <String, Json>{
    for (final p in rows(body['products']))
      if (readableText(p['retailer_id']).isNotEmpty)
        readableText(p['retailer_id']): p,
  };
  final items = [
    for (final i in raw)
      () {
        final id = readableText(i['product_retailer_id']);
        final p = known[id] ?? const <String, dynamic>{};
        return (
          retailerId: id,
          name: readableText(p['name']).trim(),
          image: readableText(p['image_url']).trim(),
          quantity: int.tryParse('${i['quantity']}') ?? 1,
          price: num.tryParse('${i['item_price']}') ?? 0,
        );
      }(),
  ];
  final thumb = readableText(object(body['thumbnail_product'])['image_url']);
  return CustomerOrder(
    items: items,
    currency: readableText(raw.first['currency']).ifBlank('INR'),
    note: readableText(order['text']).trim(),
    thumbnail: thumb.isNotEmpty
        ? thumb
        : items
              .firstWhere((i) => i.image.isNotEmpty, orElse: () => items.first)
              .image,
  );
}

/// A request to pay for an order: WhatsApp's order details message.
class OrderDetails {
  const OrderDetails({
    required this.items,
    required this.currency,
    required this.total,
    this.subtotal,
    this.tax,
    this.shipping,
    this.discount,
    this.reference = '',
    this.status = '',
    this.expiry = '',
    this.button = 'Review and pay',
  });
  final List<OrderItem> items;
  final String currency;
  final num? total, subtotal, tax, shipping, discount;
  final String reference, status, expiry, button;

  int get count => items.fold(0, (sum, i) => sum + i.quantity);
  String get countLabel => '$count ${count == 1 ? 'item' : 'items'}';
}

/// WhatsApp's money: a whole number with how many parts make one unit.
num? _amount(Object? raw) {
  final a = object(raw);
  final value = num.tryParse('${a['value']}');
  final offset = num.tryParse('${a['offset']}');
  if (value == null) return null;
  return offset == null || offset == 0 ? value : value / offset;
}

OrderDetails? orderDetailsOf(ApiMessage m) {
  if (m.type != 'interactiveOrderDetails') return null;
  final action = object(_component(m)['action']);
  final params = object(action['parameters']);
  final order = object(params['order']);
  if (order.isEmpty && params['total_amount'] == null) return null;
  final items = [
    for (final i in rows(order['items']))
      (
        retailerId: readableText(i['retailer_id']),
        name: readableText(i['name']).trim(),
        image: '',
        quantity: int.tryParse('${i['quantity']}') ?? 1,
        price: _amount(i['sale_amount']) ?? _amount(i['amount']) ?? 0,
      ),
  ];
  final subtotal = _amount(order['subtotal']);
  return OrderDetails(
    items: items,
    currency: readableText(params['currency']).ifBlank('INR'),
    total:
        _amount(params['total_amount']) ??
        subtotal ??
        items.fold<num>(0, (s, i) => s + i.quantity * i.price),
    subtotal: subtotal,
    tax: _amount(order['tax']),
    shipping: _amount(order['shipping']),
    discount: _amount(order['discount']),
    reference: readableText(params['reference_id']),
    status: readableText(order['status']),
    expiry: readableText(object(order['expiration'])['description']),
  );
}

/// An update on an order's progress: WhatsApp's order status message.
typedef OrderStatus = ({String status, String description, String reference});

OrderStatus? orderStatusOf(ApiMessage m) {
  if (m.type != 'interactiveOrderStatus') return null;
  final params = object(object(_component(m)['action'])['parameters']);
  final order = object(params['order']);
  final status = readableText(order['status']);
  if (status.isEmpty) return null;
  return (
    status: status,
    description: readableText(order['description']).trim(),
    reference: readableText(params['reference_id']),
  );
}

Json _component(ApiMessage m) {
  var body = object(decoded(m.json['message_body_json']));
  if (body.isEmpty) body = object(decoded(m.json['message_body']));
  return object(body['component']);
}

/// An order's status as people read it, as the web inbox words it.
String orderStatusLabel(String status) => switch (status) {
  'pending' => 'Pending',
  'processing' => 'Processing',
  'partially_shipped' => 'Partially shipped',
  'shipped' => 'Shipped',
  'completed' => 'Completed',
  'canceled' || 'cancelled' => 'Canceled',
  _ =>
    status.isEmpty
        ? ''
        : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}',
};

IconData orderStatusIcon(String status) => switch (status) {
  'processing' => Icons.inventory_2_outlined,
  'partially_shipped' || 'shipped' => Icons.local_shipping_outlined,
  'completed' => Icons.check_circle_outline,
  'canceled' || 'cancelled' => Icons.cancel_outlined,
  _ => Icons.receipt_long_outlined,
};

/// An amount as WhatsApp shows it: ₹1,400.00, $12.50, or "AED 12.00".
String money(num amount, String currency) {
  final symbol = switch (currency.toUpperCase()) {
    'INR' => '₹',
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    'BRL' => r'R$',
    'IDR' => 'Rp',
    _ => '${currency.toUpperCase()} ',
  };
  final fixed = amount.abs().toStringAsFixed(2);
  final whole = fixed.substring(0, fixed.length - 3);
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${amount < 0 ? '-' : ''}$symbol$grouped${fixed.substring(fixed.length - 3)}';
}

/// The cart in the bubble: its first product's picture, the item count and
/// the estimated total, as WhatsApp draws it.
class OrderCard extends StatelessWidget {
  const OrderCard(this.order, {super.key});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('order-card'),
    width: 250,
    margin: const EdgeInsets.only(top: 2, bottom: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .04),
      borderRadius: BorderRadius.circular(8),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        _Picture(order.thumbnail, size: 76),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: T.ink,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      order.countLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${money(order.total, order.currency)} (estimated total)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: T.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );
}

/// A request to pay, in the bubble under its text: the first item, how many,
/// and the total to pay.
class OrderDetailsCard extends StatelessWidget {
  const OrderDetailsCard(this.order, {super.key});
  final OrderDetails order;
  @override
  Widget build(BuildContext context) {
    final first = order.items.isEmpty ? '' : order.items.first.name;
    return Container(
      key: const ValueKey('order-details-card'),
      width: 250,
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: T.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long_outlined, color: T.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.isEmpty
                      ? 'Order'
                      : order.items.length > 1
                      ? '$first and ${order.items.length - 1} more'
                      : first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (order.items.isNotEmpty) order.countLabel,
                    if (order.total != null)
                      money(order.total!, order.currency),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: T.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An order update's status, above its text.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge(this.status, {super.key});
  final OrderStatus status;
  @override
  Widget build(BuildContext context) {
    final canceled =
        status.status == 'canceled' || status.status == 'cancelled';
    final color = canceled ? const Color(0xFFC02434) : T.green;
    return Container(
      key: const ValueKey('order-status'),
      width: 250,
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(orderStatusIcon(status.status), size: 20, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order ${orderStatusLabel(status.status).toLowerCase()}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (status.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.description,
                    style: const TextStyle(fontSize: 12.5, color: T.secondary),
                  ),
                ],
                if (status.reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Order ${status.reference}',
                    style: const TextStyle(fontSize: 12, color: T.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The customer's cart in full, as WhatsApp's "sent cart" lists it.
class OrderCartPage extends StatelessWidget {
  const OrderCartPage(this.order, {super.key, this.sentAt});
  final CustomerOrder order;
  final Object? sentAt;
  @override
  Widget build(BuildContext context) {
    const clock = MobileClock();
    final when = sentAt == null
        ? ''
        : '${clock.dayLabel(sentAt)} at ${clock.time(sentAt)}';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Customer’s cart')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            order.countLabel,
            style: const TextStyle(fontSize: 17, color: T.ink),
          ),
          const SizedBox(height: 14),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _Picture(item.image, size: 56),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name.isNotEmpty
                              ? item.name
                              : 'Item ${item.retailerId}',
                          style: const TextStyle(fontSize: 15, color: T.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Quantity: ${item.quantity}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: T.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    money(item.quantity * item.price, order.currency),
                    style: const TextStyle(fontSize: 15, color: T.ink),
                  ),
                ],
              ),
            ),
          const Divider(height: 28, color: T.hairline),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Estimated total',
                  style: TextStyle(fontSize: 15, color: T.ink),
                ),
              ),
              Text(
                money(order.total, order.currency),
                key: const ValueKey('cart-total'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
            ],
          ),
          if (when.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              when,
              style: const TextStyle(fontSize: 13.5, color: T.secondary),
            ),
          ],
          if (order.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Customer’s note',
              style: TextStyle(fontSize: 12.5, color: T.muted),
            ),
            const SizedBox(height: 2),
            Text(
              order.note,
              style: const TextStyle(fontSize: 14, color: T.ink),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            order.named
                ? 'The customer sees this estimate. You confirm the final '
                      'price, with any discount, tax and shipping, when you '
                      'ask for payment.'
                : 'Some products show by their catalogue ID: that catalogue '
                      'is not synced to Telvox. Connect it to see their names '
                      'and pictures.',
            style: const TextStyle(fontSize: 12, color: T.muted),
          ),
        ],
      ),
    );
  }
}

/// A payment request in full: what it charges for, and how the total adds up.
class OrderDetailsPage extends StatelessWidget {
  const OrderDetailsPage(this.order, {super.key});
  final OrderDetails order;
  @override
  Widget build(BuildContext context) {
    Widget line(String label, num? amount, {bool bold = false}) =>
        amount == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: bold ? 15 : 14,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                      color: bold ? T.ink : T.secondary,
                    ),
                  ),
                ),
                Text(
                  money(amount, order.currency),
                  style: TextStyle(
                    fontSize: bold ? 15 : 14,
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                    color: T.ink,
                  ),
                ),
              ],
            ),
          );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          order.reference.isEmpty ? 'Order' : 'Order ${order.reference}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (order.status.isNotEmpty)
            Text(
              'Status: ${orderStatusLabel(order.status)}',
              style: const TextStyle(fontSize: 14, color: T.secondary),
            ),
          const SizedBox(height: 8),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name.isNotEmpty
                              ? item.name
                              : 'Item ${item.retailerId}',
                          style: const TextStyle(fontSize: 15, color: T.ink),
                        ),
                        Text(
                          'Quantity: ${item.quantity}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: T.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    money(item.quantity * item.price, order.currency),
                    style: const TextStyle(fontSize: 15, color: T.ink),
                  ),
                ],
              ),
            ),
          const Divider(height: 24, color: T.hairline),
          line('Subtotal', order.subtotal),
          line('Discount', order.discount == null ? null : -order.discount!),
          line('Tax', order.tax),
          line('Shipping', order.shipping),
          line('Total', order.total, bold: true),
          if (order.expiry.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              order.expiry,
              style: const TextStyle(fontSize: 12.5, color: T.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture(this.url, {required this.size});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: T.surfaceHigh,
      child: Icon(Icons.shopping_bag_outlined, color: T.muted, size: size * .4),
    );
    return SizedBox(
      width: size,
      height: size,
      child: url.startsWith('http')
          ? Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}

extension on String {
  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
