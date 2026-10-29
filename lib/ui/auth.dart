import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'theme.dart';

class AuthPage extends StatefulWidget {
  const AuthPage(this.mode, {super.key});
  final String mode;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  bool remember = true;
  bool visible = false;
  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final login = mode == 'login';
    final verify = mode == 'verify';
    final reset = mode == 'reset';
    final title = login
        ? 'Welcome back.'
        : verify
        ? 'Check your inbox.'
        : reset
        ? 'A fresh start.'
        : 'Let’s get you back in.';
    return Scaffold(
      backgroundColor: T.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Brand(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Pill('Preview', fill: T.wash, color: T.brass),
                    ],
                  ),
                  const SizedBox(height: 36),
                  const Eyebrow('Good conversations start here'),
                  const SizedBox(height: 14),
                  Text(title, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 14),
                  Text(
                    login
                        ? 'Your customers, your team, one thoughtful workspace.'
                        : verify
                        ? 'Enter the six-digit code sent to renav@studionorth.co.'
                        : reset
                        ? 'Choose a new password for your workspace.'
                        : 'Enter your work email and we’ll help you reset your password.',
                    style: const TextStyle(color: T.secondary, height: 1.6),
                  ),
                  const SizedBox(height: 30),
                  Panel(
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!verify && !reset)
                            AppTextFormField(
                              initialValue: login
                                  ? 'renav@studionorth.co'
                                  : null,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Work email',
                                hintText: 'name@company.com',
                              ),
                              validator: (v) =>
                                  v != null &&
                                      v.contains('@') &&
                                      v.contains('.')
                                  ? null
                                  : 'Enter a valid email address',
                            ),
                          if (!verify && !reset) const SizedBox(height: 20),
                          if (login || reset) ...[
                            AppTextFormField(
                              initialValue: login ? 'preview123' : null,
                              obscureText: !visible,
                              validator: (v) => v != null && v.length >= 8
                                  ? null
                                  : 'Use at least 8 characters',
                              decoration: InputDecoration(
                                labelText: reset ? 'New password' : 'Password',
                                hintText: 'At least 8 characters',
                                suffixIcon: AppIconButton(
                                  tooltip: visible
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: () =>
                                      setState(() => visible = !visible),
                                  icon: AppIcon(
                                    visible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (reset)
                            const LabeledField(
                              'Confirm password',
                              hint: 'Repeat your new password',
                              obscure: true,
                              required: true,
                            ),
                          if (verify)
                            AppTextFormField(
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              style: mono(size: 27, color: T.ink),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: '000000',
                                counterText: '',
                              ),
                              validator: (v) =>
                                  v != null && RegExp(r'^\d{6}$').hasMatch(v)
                                  ? null
                                  : 'Enter all six digits',
                            ),
                          if (login)
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 36,
                                      child: Checkbox.adaptive(
                                        value: remember,
                                        onChanged: (v) =>
                                            setState(() => remember = v!),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Remember me',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                AppButton.text(
                                  onPressed: () =>
                                      context.push('/forgot-password'),
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          AppButton.filled(
                            onPressed: () {
                              if (!form.currentState!.validate()) return;
                              if (login) {
                                context.go('/workspaces');
                              } else if (verify) {
                                context.go('/reset-password');
                              } else if (reset) {
                                notice(
                                  context,
                                  'Password preview complete. Sign in to continue.',
                                );
                                context.go('/login');
                              } else {
                                context.push('/verify');
                              }
                            },
                            child: Text(
                              login
                                  ? 'Sign in'
                                  : verify
                                  ? 'Verify code'
                                  : reset
                                  ? 'Save password'
                                  : 'Continue',
                            ),
                          ),
                          if (verify)
                            AppButton.text(
                              onPressed: () => notice(
                                context,
                                'This is a preview. No email is sent.',
                              ),
                              child: const Text('Resend code'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!login)
                    AppButton.text(
                      onPressed: () => context.go('/login'),
                      child: const Text('Back to sign in'),
                    ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      'A little closer to your customers.',
                      style: mono(size: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      AppButton.text(
                        onPressed: () => context.push('/legal/privacy'),
                        child: const Text(
                          'Privacy',
                          style: TextStyle(color: T.brass, fontSize: 11),
                        ),
                      ),
                      AppButton.text(
                        onPressed: () => context.push('/legal/terms'),
                        child: const Text(
                          'Terms',
                          style: TextStyle(color: T.brass, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Your workspaces',
    subtitle: 'Choose a connected business number.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const Eyebrow('Connected numbers'),
        const SizedBox(height: 12),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, name, phone) in [
                (0, 'Studio North', '+91 98765 00001'),
                (1, 'Studio North · Wholesale', '+91 98765 00002'),
              ]) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 66),
                    child: Divider(),
                  ),
                InkWell(
                  key: ValueKey('workspace-row-$i'),
                  onTap: () {
                    ref.read(previewProvider.notifier).workspace(name);
                    context.go('/inbox');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Avatar(name, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(phone, style: mono(size: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const AppIcon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: T.green,
                        ),
                        const SizedBox(width: 10),
                        const AppIcon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: T.brass,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Sample workspaces · Changes stay in this preview.',
          style: TextStyle(fontSize: 11, height: 1.5, color: T.muted),
        ),
      ],
    ),
  );
}
