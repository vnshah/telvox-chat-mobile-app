import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/mobile/orders.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// Orders and payments in a chat, from the bodies the server stores: a
/// customer's cart, a request to pay, and an order update.
void main() {
  // A customer's cart exactly as WhatsApp sent it, its catalogue not synced:
  // the server could add no product details.
  const rawOrder = {
    'id': 'wamid.order',
    'type': 'order',
    'order': {
      'text': null,
      'catalog_id': '4151852421801994',
      'product_items': [
        {
          'currency': 'INR',
          'quantity': 1,
          'item_price': 1400,
          'product_retailer_id': '7m5kt2kwb8',
        },
      ],
    },
  };
  const orderDetails = {
    'type': 'interactiveOrderDetails',
    'component': {
      'type': 'order_details',
      'body': {'text': 'Please pay the registration fee below.'},
      'footer': {'text': 'Secure payment by Razorpay'},
      'action': {
        'name': 'review_and_pay',
        'parameters': {
          'reference_id': 'WABA_DIR_23',
          'type': 'digital-goods',
          'currency': 'INR',
          'total_amount': {'value': 100, 'offset': 100},
          'order': {
            'status': 'pending',
            'expiration': {
              'description':
                  'Please complete the payment within 24 hours to avoid '
                  'cancellation.',
            },
            'items': [
              {
                'retailer_id': 'vvw78ofpt1',
                'name': 'Acne-Prone Skin Care 15ml',
                'amount': {'value': 100, 'offset': 100},
                'quantity': 1,
              },
            ],
            'subtotal': {'value': 100, 'offset': 100},
          },
        },
      },
    },
  };
  const orderStatus = {
    'type': 'interactiveOrderStatus',
    'component': {
      'type': 'order_status',
      'body': {
        'text':
            'Your order information:\n 📦 Your order has been partially '
            'shipped.',
      },
      'action': {
        'name': 'review_order',
        'parameters': {
          'reference_id': 'WABA8',
          'order': {
            'status': 'partially_shipped',
            'description': 'Remaining items will be sent soon.',
          },
        },
      },
    },
  };

  ApiMessage message(String type, int direction, Json body) => ApiMessage({
    'id': 1,
    'type': direction,
    'message_type': type,
    'message_body': type == 'order' ? 'Order attached' : '',
    'message_body_json': body,
    'created_at': '2026-11-09T12:01:23Z',
  });

  group('reading orders', () {
    test('money as WhatsApp writes it', () {
      expect(money(1400, 'INR'), '₹1,400.00');
      expect(money(1234567.5, 'INR'), '₹1,234,567.50');
      expect(money(12.5, 'usd'), r'$12.50');
      expect(money(9, 'AED'), 'AED 9.00');
      expect(money(-50, 'INR'), '-₹50.00');
    });

    test('a cart is counted from WhatsApp\'s own items, synced or not', () {
      final order = orderOf(message('order', 2, rawOrder))!;
      expect(order.countLabel, '1 item');
      expect(money(order.total, order.currency), '₹1,400.00');
      expect(order.named, isFalse);
      expect(order.items.single.retailerId, '7m5kt2kwb8');
    });

    test('the server\'s product details name the items', () {
      final order = orderOf(
        message('order', 2, {
          ...rawOrder,
          'order': {
            'product_items': [
              {
                'currency': 'INR',
                'quantity': 2,
                'item_price': 700,
                'product_retailer_id': 'oil',
              },
              {
                'currency': 'INR',
                'quantity': 1,
                'item_price': 99.5,
                'product_retailer_id': 'comb',
              },
            ],
            'text': 'Please gift wrap',
          },
          'products': [
            {
              'retailer_id': 'oil',
              'name': 'Complete Hair Oil',
              'image_url': 'https://img.test/oil.jpg',
            },
            {'retailer_id': 'comb', 'name': 'Wooden comb', 'image_url': ''},
          ],
          'thumbnail_product': {'image_url': 'https://img.test/oil.jpg'},
        }),
      )!;
      expect(order.countLabel, '3 items');
      expect(money(order.total, order.currency), '₹1,499.50');
      expect(order.named, isTrue);
      expect(order.note, 'Please gift wrap');
      expect(order.thumbnail, 'https://img.test/oil.jpg');
    });

    test('a payment request: items, total, reference and expiry', () {
      final details = orderDetailsOf(
        message('interactiveOrderDetails', 1, orderDetails),
      )!;
      expect(details.items.single.name, 'Acne-Prone Skin Care 15ml');
      expect(money(details.total!, details.currency), '₹1.00');
      expect(details.reference, 'WABA_DIR_23');
      expect(orderStatusLabel(details.status), 'Pending');
      expect(details.expiry, contains('24 hours'));
    });

    test('an order update', () {
      final status = orderStatusOf(
        message('interactiveOrderStatus', 1, orderStatus),
      )!;
      expect(orderStatusLabel(status.status), 'Partially shipped');
      expect(status.reference, 'WABA8');
    });

    test('a reply quote names a cart, not "Order attached"', () {
      expect(message('order', 2, rawOrder).content.summary, 'Order: 1 item');
    });
  });

  group('in the chat', () {
    Future<void> show(WidgetTester tester, List<ApiMessage> messages) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: Scaffold(
            body: ListView(
              children: [
                for (final m in messages)
                  LiveMessageView(
                    message: m,
                    apiBase: 'https://chat.example.test/api/mobile/v1/',
                    first: true,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a cart shows its count and total, and opens in full', (
      tester,
    ) async {
      await show(tester, [message('order', 2, rawOrder)]);
      expect(find.byKey(const ValueKey('order-card')), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(find.text('₹1,400.00 (estimated total)'), findsOneWidget);
      expect(find.text('Order attached'), findsNothing);

      await tester.tap(find.text('View sent cart'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderCartPage), findsOneWidget);
      // Not synced: the item shows by its catalogue id, and says why.
      expect(find.text('Item 7m5kt2kwb8'), findsOneWidget);
      expect(find.text('Quantity: 1'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
        '₹1,400.00',
      );
      expect(find.textContaining('not synced'), findsOneWidget);
    });

    testWidgets('a payment request shows its order and Review and pay', (
      tester,
    ) async {
      await show(tester, [message('interactiveOrderDetails', 1, orderDetails)]);
      expect(
        find.text('Please pay the registration fee below.'),
        findsOneWidget,
      );
      expect(find.text('Acne-Prone Skin Care 15ml'), findsOneWidget);
      expect(find.text('1 item · ₹1.00'), findsOneWidget);
      expect(find.text('Secure payment by Razorpay'), findsOneWidget);
      // The items are in the card, not repeated in the text.
      expect(find.textContaining('Order pending'), findsNothing);

      await tester.tap(find.text('Review and pay'));
      await tester.pumpAndSettle();
      expect(find.text('Order WABA_DIR_23'), findsOneWidget);
      expect(find.text('Status: Pending'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('an order update shows where the order is', (tester) async {
      await show(tester, [message('interactiveOrderStatus', 1, orderStatus)]);
      expect(find.byKey(const ValueKey('order-status')), findsOneWidget);
      expect(find.text('Order partially shipped'), findsOneWidget);
      expect(find.text('Remaining items will be sent soon.'), findsOneWidget);
      expect(find.textContaining('Your order information'), findsOneWidget);
    });

    testWidgets('review images', (tester) async {
      await loadUiFonts();
      Directory('build/review').createSync(recursive: true);
      tester.view.physicalSize = const Size(412, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chat = GlobalKey(), cart = GlobalKey();
      await renderWithRealShadows(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: chat,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: T.themeFor(TargetPlatform.android),
              home: Scaffold(
                backgroundColor: const Color(0xFFEFE7DE),
                body: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    for (final m in [
                      message('order', 2, rawOrder),
                      message('interactiveOrderDetails', 1, orderDetails),
                      message('interactiveOrderStatus', 1, orderStatus),
                    ])
                      LiveMessageView(
                        message: m,
                        apiBase: 'https://chat.example.test/api/mobile/v1/',
                        first: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await saveReviewImage(tester, chat, 'build/review/orders-chat.png');
        await tester.pumpWidget(
          RepaintBoundary(
            key: cart,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: T.themeFor(TargetPlatform.android),
              home: OrderCartPage(
                orderOf(message('order', 2, rawOrder))!,
                sentAt: '2026-11-09T12:01:23Z',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await saveReviewImage(tester, cart, 'build/review/orders-cart.png');
      });
      await tester.pumpWidget(const SizedBox());
    });
  });
}
