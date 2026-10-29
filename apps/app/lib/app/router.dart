import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/providers.dart';
import '../ui/screens/accounts/accounts_screen.dart';
import '../ui/screens/accounts/statement_screen.dart';
import '../ui/screens/auth/auth_screens.dart';
import '../ui/screens/cards/cards_screen.dart';
import '../ui/screens/debts/debts_screen.dart';
import '../ui/screens/investments/investments_screen.dart';
import '../ui/screens/patrimony/patrimony_screen.dart';
import '../ui/screens/piggy/piggy_screen.dart';
import '../ui/screens/planning/planning_screen.dart';
import '../ui/screens/dashboard/dashboard_screen.dart';
import '../ui/screens/contacts/contacts_screen.dart';
import '../ui/screens/contacts/payables_screen.dart';
import '../ui/screens/placeholder/coming_soon_screen.dart';
import '../ui/screens/recurring/recurring_screen.dart';
import '../ui/screens/settings/settings_screen.dart';
import '../ui/screens/transactions/transaction_form_screen.dart';
import '../ui/screens/transactions/transactions_screen.dart';
import '../ui/shell/app_shell.dart';

const _publicPaths = {'/login', '/cadastro', '/esqueci-senha', '/redefinir-senha'};

/// Notifica o roteador quando o estado de autenticação muda.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) => resolveRedirect(
      loading: ref.read(authProvider).isLoading,
      loggedIn: ref.read(authProvider).value != null,
      location: state.matchedLocation,
      uri: state.uri,
    ),
    routes: [
      GoRoute(path: '/carregando', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/cadastro', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/esqueci-senha', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/redefinir-senha',
        builder: (_, s) => ResetPasswordScreen(email: s.uri.queryParameters['email']),
      ),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          GoRoute(
            path: '/lancamentos',
            builder: (_, s) => TransactionsScreen(initialQuery: s.uri.queryParameters['q']),
            routes: [
              GoRoute(
                path: 'novo',
                builder: (_, s) => TransactionFormScreen(
                  initialType: s.uri.queryParameters['tipo'],
                  initialRecurring: s.uri.queryParameters['recorrente'] == '1',
                  initialContactId: s.uri.queryParameters['contato'],
                  entityId: s.uri.queryParameters['ambiente'],
                ),
              ),
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) => TransactionFormScreen(
                  entityId: s.pathParameters['entityId'],
                  transactionId: s.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/contas',
            builder: (_, _) => const AccountsScreen(),
            routes: [
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) =>
                    StatementScreen(entityId: s.pathParameters['entityId']!, accountId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/recorrencias',
            builder: (_, _) => const RecurringScreen(),
            routes: [
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) =>
                    RecurringDetailScreen(entityId: s.pathParameters['entityId']!, ruleId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/contatos',
            builder: (_, _) => const ContactsScreen(),
            routes: [
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) =>
                    ContactDetailScreen(entityId: s.pathParameters['entityId']!, contactId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/contas-a-pagar',
            builder: (_, s) =>
                PayablesScreen(initialKind: s.uri.queryParameters['tipo'] == 'pagar' ? 'payable' : 'receivable'),
          ),
          GoRoute(path: '/configuracoes', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: '/cofrinhos',
            builder: (_, _) => const PiggyScreen(),
            routes: [
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) =>
                    PiggyDetailScreen(entityId: s.pathParameters['entityId']!, piggyId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/investimentos',
            builder: (_, _) => const InvestmentsScreen(),
            routes: [
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) => InvestmentDetailScreen(
                  entityId: s.pathParameters['entityId']!,
                  investmentId: s.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(path: '/patrimonio', builder: (_, _) => const PatrimonyScreen()),
          GoRoute(path: '/planejamento', builder: (_, _) => const PlanningScreen()),
          GoRoute(
            path: '/cartoes',
            builder: (_, _) => const CardsScreen(),
            routes: [
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) =>
                    CardDetailScreen(entityId: s.pathParameters['entityId']!, cardId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/dividas',
            builder: (_, _) => const DebtsScreen(),
            routes: [
              GoRoute(
                path: 'nova',
                builder: (_, s) => DebtFormScreen(entityId: s.uri.queryParameters['ambiente']),
              ),
              GoRoute(
                path: ':entityId/:id',
                builder: (_, s) =>
                    DebtDetailScreen(entityId: s.pathParameters['entityId']!, debtId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/costelinha',
            builder: (_, _) => const ComingSoonScreen(
              title: 'Costelinha IA',
              icon: Symbols.psychology,
              phase: 'Fase 4',
              description: 'Sua assistente financeira: o backend calcula os números e a Costelinha explica, sempre com base nos seus dados reais.',
            ),
          ),
          GoRoute(
            path: '/relatorios',
            builder: (_, _) => const ComingSoonScreen(
              title: 'Relatórios',
              icon: Symbols.bar_chart,
              phase: 'Fase 4',
              description: 'Relatórios mensais, trimestrais e anuais com exportação em PDF, XLSX e CSV.',
            ),
          ),
        ],
      ),
    ],
  );
});

/// Regras de redirecionamento por autenticação, preservando o destino original (deep links)
/// em `?from=` enquanto a sessão carrega ou o usuário faz login.
@visibleForTesting
String? resolveRedirect({required bool loading, required bool loggedIn, required String location, required Uri uri}) {
  final from = uri.queryParameters['from'];
  final target = from != null && from.startsWith('/') && !from.startsWith('//') ? from : '/';
  String withFrom(String path) =>
      location == '/' ? path : Uri(path: path, queryParameters: {'from': uri.toString()}).toString();

  if (location == '/carregando') {
    if (loading) return null;
    return loggedIn
        ? target
        : (target == '/' ? '/login' : Uri(path: '/login', queryParameters: {'from': target}).toString());
  }
  if (loading) return withFrom('/carregando');
  final public = _publicPaths.contains(location);
  if (!loggedIn && !public) return withFrom('/login');
  if (loggedIn && public) return target;
  return null;
}
