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
  // Preview scope matches the live app: shared inbox, ticket inbox,
  // settings and notifications only.
  routes: [
    for (final (path, mode) in [('/login', 'login'), ('/verify', 'verify')])
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
            template: state.uri.queryParameters['template'],
            draft: state.uri.queryParameters['draft'],
          ),
        ),
        GoRoute(path: '/tickets', builder: (_, _) => const TicketsPage()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
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
    GoRoute(
      path: '/template/:id',
      builder: (_, s) => TemplatePreviewPage(
        s.pathParameters['id']!,
        contact: s.uri.queryParameters['contact'],
      ),
    ),
    GoRoute(
      path: '/quick-replies',
      builder: (_, _) => const QuickRepliesPage(),
    ),
    GoRoute(path: '/ticket/new', builder: (_, _) => const TicketFormPage()),
    GoRoute(
      path: '/ticket/:id',
      builder: (_, s) => TicketDetailPage(s.pathParameters['id']!),
    ),
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
