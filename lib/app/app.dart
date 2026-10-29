import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../ui/auth.dart';
import '../ui/business.dart';
import '../ui/conversation.dart';
import '../ui/inbox.dart';
import '../ui/management.dart';
import '../ui/preview.dart';
import '../ui/settings.dart';
import '../ui/theme.dart';

GoRouter createRouter({String initialLocation = '/login'}) => GoRouter(
  initialLocation: initialLocation,
  errorBuilder: (context, state) => PageFrame(
    title: 'Page not found',
    child: EmptyView(
      title: 'Let’s find your way back.',
      description:
          'This screen isn’t available. Your conversations are a tap away.',
      action: 'Go to inbox',
      onAction: () => context.go('/inbox'),
    ),
  ),
  routes: [
    for (final (path, mode) in [
      ('/login', 'login'),
      ('/forgot-password', 'forgot'),
      ('/verify', 'verify'),
      ('/reset-password', 'reset'),
    ])
      GoRoute(path: path, builder: (_, _) => AuthPage(mode)),
    GoRoute(path: '/', redirect: (_, _) => '/login'),
    GoRoute(path: '/workspaces', builder: (_, _) => const WorkspacePage()),
    ShellRoute(
      builder: (_, _, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/inbox', builder: (_, _) => const InboxPage()),
        GoRoute(
          path: '/contacts',
          builder: (_, state) => ContactsPage(
            pick: state.uri.queryParameters['pick'] == 'true',
            call: state.uri.queryParameters['pick'] == 'call',
            template: state.uri.queryParameters['template'],
            product: state.uri.queryParameters['product'],
            draft: state.uri.queryParameters['draft'],
          ),
        ),
        GoRoute(path: '/tickets', builder: (_, _) => const TicketsPage()),
        GoRoute(path: '/more', builder: (_, _) => const MorePage()),
      ],
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (_, s) => ChatPage(
        s.pathParameters['id']!,
        initialDraft: s.uri.queryParameters['draft'],
      ),
    ),
    GoRoute(path: '/contact/new', builder: (_, _) => const ContactFormPage()),
    GoRoute(
      path: '/contact/:id/edit',
      builder: (_, s) => ContactFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/customer/:id',
      builder: (_, s) => CustomerPage(s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/customer/:id/:tool',
      builder: (_, s) =>
          ContactToolPage(s.pathParameters['id']!, s.pathParameters['tool']!),
    ),
    GoRoute(
      path: '/templates',
      builder: (_, s) =>
          TemplatesPage(contact: s.uri.queryParameters['contact']),
    ),
    GoRoute(path: '/template/new', builder: (_, _) => const TemplateFormPage()),
    GoRoute(
      path: '/template/:id',
      builder: (_, s) => TemplatePreviewPage(
        s.pathParameters['id']!,
        contact: s.uri.queryParameters['contact'],
      ),
    ),
    GoRoute(
      path: '/quick-replies',
      builder: (_, s) =>
          QuickRepliesPage(pick: s.uri.queryParameters['pick'] == 'true'),
    ),
    GoRoute(
      path: '/ai',
      builder: (_, s) =>
          AiPage(returnDraft: s.uri.queryParameters['contact'] != null),
    ),
    GoRoute(
      path: '/catalogue',
      builder: (_, s) =>
          CataloguePage(contact: s.uri.queryParameters['contact']),
    ),
    GoRoute(
      path: '/product/:id',
      builder: (_, s) => ProductPage(
        s.pathParameters['id']!,
        contact: s.uri.queryParameters['contact'],
      ),
    ),
    GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
    GoRoute(
      path: '/order/:id',
      builder: (_, s) => OrderPage(s.pathParameters['id']!),
    ),
    GoRoute(path: '/ticket/new', builder: (_, _) => const TicketFormPage()),
    GoRoute(
      path: '/ticket/:id',
      builder: (_, s) => TicketDetailPage(s.pathParameters['id']!),
    ),
    GoRoute(path: '/calls', builder: (_, _) => const CallsPage()),
    GoRoute(
      path: '/call/incoming',
      builder: (_, _) => const CallPage('ananya', incoming: true),
    ),
    GoRoute(
      path: '/call/:id',
      builder: (_, s) => CallPage(s.pathParameters['id']!),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const NotificationsPage(),
    ),
    GoRoute(
      path: '/notifications/permission',
      builder: (_, _) => const PermissionPage(),
    ),
    GoRoute(
      path: '/settings/notifications',
      builder: (_, _) => const PreferencePage('notifications'),
    ),
    GoRoute(
      path: '/settings/calls',
      builder: (_, _) => const PreferencePage('calls'),
    ),
    GoRoute(
      path: '/settings/business',
      builder: (_, _) => const BusinessProfilePage(),
    ),
    GoRoute(
      path: '/settings/security',
      builder: (_, _) => const SecurityPage(),
    ),
    GoRoute(path: '/settings/help', builder: (_, _) => const HelpPage()),
    GoRoute(
      path: '/settings/about',
      builder: (_, _) => const HelpPage(about: true),
    ),
    GoRoute(
      path: '/legal/:id',
      builder: (_, s) => HelpPage(legal: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/hub/:id',
      builder: (_, s) => HubPage(s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/manage/:id/new',
      builder: (_, s) => ModuleFormPage(s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/manage/:id/:index/edit',
      builder: (_, s) => ModuleFormPage(
        s.pathParameters['id']!,
        index: int.parse(s.pathParameters['index']!),
      ),
    ),
    GoRoute(
      path: '/manage/:id/:index',
      builder: (_, s) => ModuleDetailPage(
        s.pathParameters['id']!,
        int.parse(s.pathParameters['index']!),
      ),
    ),
    GoRoute(
      path: '/manage/:id',
      builder: (_, s) => ModulePage(s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/workflow/:id',
      builder: (_, s) => FlowPage(s.pathParameters['id']!),
    ),
    GoRoute(path: '/campaigns', builder: (_, _) => const CampaignsPage()),
    GoRoute(path: '/campaign/new', builder: (_, _) => const CampaignFormPage()),
    GoRoute(
      path: '/campaign/:id',
      builder: (_, s) => CampaignDetailPage(s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, s) =>
          ReportsPage(initial: s.uri.queryParameters['type'] ?? 'Delivery'),
    ),
    GoRoute(path: '/billing', builder: (_, _) => const BillingPage()),
    GoRoute(path: '/preview', builder: (_, _) => const PreviewPage()),
    GoRoute(
      path: '/preview/states',
      builder: (_, s) =>
          StatePreviewPage(initial: s.uri.queryParameters['state'] ?? 'empty'),
    ),
  ],
);

class TelvoxApp extends ConsumerStatefulWidget {
  const TelvoxApp({super.key, this.router, this.platform});
  final TargetPlatform? platform;
  final GoRouter? router;
  @override
  ConsumerState<TelvoxApp> createState() => _TelvoxAppState();
}

class _TelvoxAppState extends ConsumerState<TelvoxApp> {
  late final router = widget.router ?? createRouter();
  @override
  void dispose() {
    if (widget.router == null) router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform =
        widget.platform ??
        ref.watch(platformPreviewProvider) ??
        defaultTargetPlatform;
    return MaterialApp.router(
      title: 'Telvox Chat',
      debugShowCheckedModeBanner: false,
      theme: T.themeFor(platform),
      builder: (_, child) => CupertinoTheme(
        data: T.cupertino,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(
            systemNavigationBarColor: platform == TargetPlatform.iOS
                ? Colors.white
                : T.paper,
          ),
          child: child!,
        ),
      ),
      routerConfig: router,
    );
  }
}
