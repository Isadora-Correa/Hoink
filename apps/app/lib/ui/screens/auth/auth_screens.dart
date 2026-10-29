import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/api_client.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/hoink_logo.dart';

String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Informe seu e-mail';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'E-mail inválido';
  return null;
}

/// Mesma política do backend: mínimo de 8 caracteres, com letras e números.
String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'A senha deve ter pelo menos 8 caracteres';
  if (!RegExp(r'[A-Za-z]').hasMatch(s)) return 'A senha deve conter letras';
  if (!RegExp(r'\d').hasMatch(s)) return 'A senha deve conter números';
  return null;
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: HoinkColors.ivory,
    body: Center(child: HoinkLogo(height: 56)),
  );
}

/// Layout das telas públicas: painel de marca (desktop) + formulário.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[const Center(child: HoinkLogo(height: 44)), const SizedBox(height: 32)],
              Text(title, style: HoinkText.headlineLg.copyWith(color: HoinkColors.primary)),
              const SizedBox(height: 6),
              Text(subtitle, style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant)),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: HoinkColors.ivory,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(48),
                      decoration: BoxDecoration(
                        color: HoinkColors.pine,
                        borderRadius: BorderRadius.circular(HoinkRadius.xl),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const HoinkLogo(height: 48, onDark: true),
                          const Spacer(),
                          Center(
                            child: SvgPicture.asset(
                              'assets/brand/hoink-mascote.svg',
                              height: 260,
                              semanticsLabel: 'Mascote hoink.',
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Seu dinheiro,\ndo seu jeito.',
                            style: HoinkText.displayHero.copyWith(color: HoinkColors.ivory),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: HoinkColors.pigPink,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Pessoal, profissional e consolidado — tudo sob controle.',
                            style: HoinkText.bodyLg.copyWith(color: HoinkColors.primaryFixedDim),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: form),
                ],
              )
            : form,
      ),
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError(this.message);
  final String? message;
  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HoinkColors.errorContainer, borderRadius: BorderRadius.circular(HoinkRadius.md)),
      child: Row(
        children: [
          const Icon(Symbols.error, size: 18, color: HoinkColors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message!, style: HoinkText.bodySm.copyWith(color: HoinkColors.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Senha',
    this.validator,
    this.autofill,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  final String label;
  final String? Function(String?)? validator;
  final String? autofill;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _obscure,
    validator: widget.validator ?? (v) => (v == null || v.isEmpty) ? 'Informe a senha' : null,
    autofillHints: widget.autofill == null ? null : [widget.autofill!],
    textInputAction: widget.onSubmitted == null ? null : TextInputAction.done,
    onFieldSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Symbols.lock, size: 20),
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
        icon: Icon(_obscure ? Symbols.visibility : Symbols.visibility_off, size: 20),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  );
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Bem-vindo de volta',
      subtitle: 'Entre para acompanhar suas finanças.',
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormError(_error),
              TextFormField(
                key: const Key('login-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: validateEmail,
                decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Symbols.mail, size: 20)),
              ),
              const SizedBox(height: 16),
              PasswordField(controller: _password, autofill: AutofillHints.password, onSubmitted: _submit),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/esqueci-senha'),
                  child: const Text('Esqueci minha senha'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('login-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: HoinkColors.ivory),
                      )
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Ainda não tem conta?', style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant)),
                  TextButton(onPressed: () => context.go('/cadastro'), child: const Text('Criar conta')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _withBusiness = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .signup(_name.text.trim(), _email.text.trim(), _password.text, withBusiness: _withBusiness);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Crie sua conta',
      subtitle: 'Comece pelo seu ambiente Pessoal; o Profissional é opcional.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FormError(_error),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (v) => (v ?? '').trim().length < 2 ? 'Informe seu nome' : null,
              decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Symbols.person, size: 20)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: validateEmail,
              decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Symbols.mail, size: 20)),
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              validator: validatePassword,
              autofill: AutofillHints.newPassword,
              onSubmitted: _submit,
            ),
            const SizedBox(height: 6),
            Text(
              'Mínimo de 8 caracteres, com letras e números.',
              style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('signup-business'),
              contentPadding: EdgeInsets.zero,
              value: _withBusiness,
              onChanged: (v) => setState(() => _withBusiness = v),
              title: Text('Também quero uma conta profissional (PJ)', style: HoinkText.labelMd),
              subtitle: Text(
                'Para separar as finanças da sua empresa. Dá para ativar depois em Configurações.',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Criando...' : 'Criar conta')),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Já tem conta?', style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant)),
                TextButton(onPressed: () => context.go('/login'), child: const Text('Entrar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).forgotPassword(_email.text.trim());
      if (mounted) context.go(Uri(path: '/redefinir-senha', queryParameters: {'email': _email.text.trim()}).toString());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Recuperar senha',
    subtitle: 'Enviaremos um código de redefinição para o seu e-mail.',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            validator: validateEmail,
            decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Symbols.mail, size: 20)),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Enviar código')),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.go('/login'), child: const Text('Voltar ao login')),
        ],
      ),
    ),
  );
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.email});
  final String? email;
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).resetPassword(_token.text.trim(), _password.text);
      if (!mounted) return;
      showSuccess(context, 'Senha redefinida. Entre com a nova senha.');
      context.go('/login');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Redefinir senha',
    subtitle: widget.email == null
        ? 'Informe o código recebido por e-mail e a nova senha.'
        : 'Se ${widget.email} estiver cadastrado, você receberá um código válido por 1 hora.',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormError(_error),
          TextFormField(
            controller: _token,
            validator: (v) => (v ?? '').trim().length < 20 ? 'Código inválido' : null,
            decoration: const InputDecoration(labelText: 'Código', prefixIcon: Icon(Symbols.key, size: 20)),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: 'Nova senha',
            validator: validatePassword,
            autofill: AutofillHints.newPassword,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Redefinir senha')),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.go('/login'), child: const Text('Voltar ao login')),
        ],
      ),
    ),
  );
}
