import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../state/providers.dart';
import '../widgets/hoink_logo.dart';
import '../widgets/scope_switcher.dart';
import '../widgets/user_avatar.dart';

class NavItem {
  const NavItem(this.path, this.label, this.icon, {this.badge, this.iconColor});
  final String path;
  final String label;
  final IconData icon;
  final String? badge;
  final Color? iconColor;
}

const sideNav = [
  NavItem('/', 'Início', Symbols.grid_view),
  NavItem('/lancamentos', 'Lançamentos', Symbols.receipt_long),
  NavItem('/recorrencias', 'Recorrências', Symbols.event_repeat),
  NavItem('/contas-a-pagar', 'Pagar e Receber', Symbols.request_quote),
  NavItem('/contatos', 'Clientes e Fornecedores', Symbols.groups),
  NavItem('/contas', 'Minhas Contas', Symbols.account_balance),
  NavItem('/cartoes', 'Cartões', Symbols.credit_card),
  NavItem('/dividas', 'Dívidas', Symbols.credit_score),
  NavItem('/cofrinhos', 'Cofrinhos', Symbols.savings, iconColor: HoinkColors.tertiaryFixedDim),
  NavItem('/investimentos', 'Investimentos', Symbols.trending_up),
  NavItem('/planejamento', 'Planejamento', Symbols.calendar_month),
  NavItem('/costelinha', 'Costelinha IA', Symbols.psychology, badge: 'IA', iconColor: HoinkColors.surfaceTint),
  NavItem('/relatorios', 'Relatórios', Symbols.bar_chart),
  NavItem('/configuracoes', 'Configurações', Symbols.settings),
];

const bottomNav = [
  NavItem('/', 'Início', Symbols.home),
  NavItem('/lancamentos', 'Extrato', Symbols.receipt_long),
  NavItem('/cofrinhos', 'Cofrinhos', Symbols.savings),
  NavItem('/investimentos', 'Investir', Symbols.trending_up),
  NavItem('/costelinha', 'Costelinha', Symbols.psychology),
];

const desktopBreakpoint = 1024.0;

/// Ativo quando a rota é o item ou uma sub-rota dele (`/contas` não marca `/contas-a-pagar`).
bool _isActive(String location, String path) =>
    path == '/' ? location == '/' : (location == path || location.startsWith('$path/'));

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final hideFab =
        location.startsWith('/lancamentos/') || location.startsWith('/configuracoes') || location == '/dividas/nova';

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(location: location),
            Expanded(
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final index = bottomNav.indexWhere((n) => _isActive(location, n.path));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _MobileHeader(),
            Expanded(child: child),
          ],
        ),
      ),
      floatingActionButton: hideFab
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/lancamentos/novo'),
              backgroundColor: HoinkColors.pine,
              foregroundColor: HoinkColors.ivory,
              shape: const StadiumBorder(),
              icon: const Icon(Symbols.add),
              label: const Text('Novo', style: HoinkText.headlineSm),
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: HoinkColors.surfaceLowest,
        // Telas fora da barra inferior (Contas, Configurações) não destacam nenhum item.
        indicatorColor: index < 0 ? Colors.transparent : HoinkColors.surfaceContainer,
        selectedIndex: index < 0 ? 0 : index,
        labelTextStyle: WidgetStatePropertyAll(HoinkText.labelSm.copyWith(color: HoinkColors.pine)),
        onDestinationSelected: (i) => context.go(bottomNav[i].path),
        destinations: [
          for (final n in bottomNav)
            NavigationDestination(
              icon: Icon(n.icon, color: HoinkColors.pine),
              label: n.label,
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: HoinkColors.surfaceLowest,
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(alignment: Alignment.centerLeft, child: HoinkLogo(height: 34)),
          ),
          const SizedBox(height: 24),
          const ScopeSwitcher(compact: true, expand: true),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [for (final n in sideNav) _SideNavTile(item: n, active: _isActive(location, n.path))],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNavTile extends StatelessWidget {
  const _SideNavTile({required this.item, required this.active});
  final NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? HoinkColors.primaryFixed : HoinkColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? HoinkColors.pine : Colors.transparent,
        borderRadius: BorderRadius.circular(HoinkRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(HoinkRadius.md),
          hoverColor: HoinkColors.surfaceHigh,
          onTap: () => context.go(item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: active ? fg : (item.iconColor ?? fg)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: HoinkText.bodyMd.copyWith(
                      color: active ? fg : HoinkColors.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (item.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: HoinkColors.tertiaryFixed,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(item.badge!, style: HoinkText.labelSm.copyWith(color: HoinkColors.onTertiaryFixed)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MonthPicker extends ConsumerWidget {
  const MonthPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final ctrl = ref.read(monthProvider.notifier);
    return Container(
      decoration: BoxDecoration(color: HoinkColors.surfaceLow, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Mês anterior',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.chevron_left, size: 18),
            onPressed: () => ctrl.set(shiftMonth(month, -1)),
          ),
          const Icon(Symbols.calendar_today, size: 16, color: HoinkColors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(monthLabel(month), style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurface)),
          IconButton(
            tooltip: 'Próximo mês',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.chevron_right, size: 18),
            onPressed: () => ctrl.set(shiftMonth(month, 1)),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar();
  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xE6FFFFFF),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          const MonthPicker(),
          const SizedBox(width: 16),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _search,
                  style: HoinkText.bodySm,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (q) =>
                      context.go(Uri(path: '/lancamentos', queryParameters: q.isEmpty ? null : {'q': q}).toString()),
                  decoration: const InputDecoration(
                    hintText: 'Buscar lançamentos...',
                    prefixIcon: Icon(Symbols.search, size: 18),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => context.push('/lancamentos/novo'),
            icon: const Icon(Symbols.add, size: 18),
            label: const Text('Novo Lançamento'),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: HoinkColors.surfaceHighest),
          const SizedBox(width: 12),
          if (user != null) UserMenu(showName: true, name: user.name, initials: user.initials),
        ],
      ),
    );
  }
}

class UserMenu extends ConsumerWidget {
  const UserMenu({super.key, required this.name, required this.initials, this.showName = false});
  final String name;
  final String initials;
  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Conta',
      position: PopupMenuPosition.under,
      onSelected: (v) async {
        switch (v) {
          case 'contas':
            context.go('/contas');
          case 'recorrencias':
            context.go('/recorrencias');
          case 'pagar':
            context.go('/contas-a-pagar');
          case 'contatos':
            context.go('/contatos');
          case 'cartoes':
            context.go('/cartoes');
          case 'dividas':
            context.go('/dividas');
          case 'planejamento':
            context.go('/planejamento');
          case 'config':
            context.go('/configuracoes');
          case 'sair':
            await ref.read(authProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'contas', child: Text('Minhas Contas')),
        PopupMenuItem(value: 'recorrencias', child: Text('Recorrências')),
        PopupMenuItem(value: 'pagar', child: Text('Pagar e Receber')),
        PopupMenuItem(value: 'contatos', child: Text('Clientes e Fornecedores')),
        PopupMenuItem(value: 'cartoes', child: Text('Cartões')),
        PopupMenuItem(value: 'dividas', child: Text('Dívidas')),
        PopupMenuItem(value: 'planejamento', child: Text('Planejamento')),
        PopupMenuItem(value: 'config', child: Text('Configurações')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'sair', child: Text('Sair')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const UserAvatar(),
          if (showName) ...[
            const SizedBox(width: 10),
            Text(name, style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurface)),
          ],
        ],
      ),
    );
  }
}

class _MobileHeader extends ConsumerWidget {
  const _MobileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          const HoinkLogo(height: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: ScopeSwitcher(compact: true)),
            ),
          ),
          const SizedBox(width: 10),
          if (user != null) UserMenu(name: user.name, initials: user.initials),
        ],
      ),
    );
  }
}
