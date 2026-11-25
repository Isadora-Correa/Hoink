import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/hoink_logo.dart';
import '../widgets/notification_bell.dart';
import '../widgets/pig_avatar.dart';
import '../widgets/scope_switcher.dart';
import '../widgets/user_avatar.dart';

class NavItem {
  const NavItem(
    this.path,
    this.label,
    this.icon, {
    this.badge,
    this.iconColor,
    this.businessOnly = false,
    this.pig = false,
  });
  final String path;
  final String label;
  final IconData icon;
  final String? badge;
  final Color? iconColor;
  final bool businessOnly;

  /// Usa o porquinho da marca no lugar do ícone (Costelinha).
  final bool pig;
}

/// Menu lateral em grupos curtos. `businessOnly`: só aparece com conta profissional.
const sideNavGroups = <(String?, List<NavItem>)>[
  (
    null,
    [
      NavItem('/', 'Início', Symbols.grid_view),
      NavItem('/lancamentos', 'Lançamentos', Symbols.receipt_long),
      NavItem('/contas-a-pagar', 'Pagar e Receber', Symbols.request_quote),
    ],
  ),
  (
    'Contas',
    [
      NavItem('/contas', 'Minhas Contas', Symbols.account_balance),
      NavItem('/extrato', 'Extrato', Symbols.description),
      NavItem('/cartoes', 'Cartões', Symbols.credit_card),
    ],
  ),
  (
    'Planejar',
    [
      NavItem('/planejamento', 'Planejamento', Symbols.calendar_month),
      NavItem('/recorrencias', 'Contas fixas', Symbols.event_repeat),
      NavItem('/dividas', 'Dívidas', Symbols.credit_score),
    ],
  ),
  (
    'Guardar e investir',
    [
      NavItem('/cofrinhos', 'Cofrinhos', Symbols.savings, iconColor: HoinkColors.tertiaryFixedDim),
      NavItem('/investimentos', 'Investimentos', Symbols.trending_up),
      NavItem('/patrimonio', 'Patrimônio', Symbols.account_balance_wallet),
    ],
  ),
  (
    'Mais',
    [
      NavItem('/costelinha', 'Costelinha', Symbols.psychology, pig: true),
      NavItem('/relatorios', 'Relatórios', Symbols.bar_chart),
      NavItem('/contatos', 'Clientes e Fornecedores', Symbols.groups, businessOnly: true),
      NavItem('/configuracoes', 'Configurações', Symbols.settings),
    ],
  ),
];

/// Todos os itens do menu (para destaque do item ativo e testes).
final sideNav = [for (final g in sideNavGroups) ...g.$2];

/// Barra inferior do celular. O item do meio (Costelinha) é o botão em destaque, elevado.
const bottomNav = [
  NavItem('/', 'Início', Symbols.home),
  NavItem('/lancamentos', 'Lançamentos', Symbols.receipt_long),
  NavItem('/costelinha', 'Costelinha', Symbols.psychology, pig: true),
  NavItem('/cofrinhos', 'Cofrinhos', Symbols.savings),
  NavItem('/investimentos', 'Investir', Symbols.trending_up),
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
    // "Novo lançamento" só na aba de Lançamentos; nas outras abas o botão não faz sentido.
    final showFab = location == '/lancamentos';

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
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final center = bottomNav.indexWhere((n) => n.pig);
    // O botão do Costelinha fica fora da Scaffold para receber toques também na parte que sobe acima da barra.
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _MobileHeader(),
                Expanded(child: child),
              ],
            ),
          ),
          floatingActionButton: !showFab
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => context.push('/lancamentos/novo'),
                  backgroundColor: HoinkColors.pine,
                  foregroundColor: HoinkColors.ivory,
                  shape: const StadiumBorder(),
                  icon: const Icon(Symbols.add),
                  label: const Text('Novo', style: HoinkText.headlineSm),
                ),
          bottomNavigationBar: HoinkBottomBar(selectedIndex: index, onSelected: (i) => context.go(bottomNav[i].path)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: safeBottom + HoinkBottomBar.height - HoinkBottomBar.buttonCenterY - HoinkBottomBar.buttonSize / 2,
          child: Center(
            child: _CostelinhaButton(active: index == center, onTap: () => context.go(bottomNav[center].path)),
          ),
        ),
      ],
    );
  }
}

/// Barra inferior do celular: 4 abas + espaço central para o botão do Costelinha,
/// com uma "bolha" arredondada saindo para cima e um degradê suave que separa a barra do conteúdo.
class HoinkBottomBar extends StatelessWidget {
  const HoinkBottomBar({super.key, required this.selectedIndex, required this.onSelected});
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 70.0;
  static const buttonSize = 46.0;

  /// Centro do botão, medido a partir do topo da barra.
  static const buttonCenterY = 18.0;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return CustomPaint(
      painter: const _BottomBarPainter(),
      child: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < bottomNav.length; i++)
                Expanded(
                  child: bottomNav[i].pig
                      ? _CenterLabel(label: bottomNav[i].label, active: i == selectedIndex, onTap: () => onSelected(i))
                      : _BottomBarItem(item: bottomNav[i], active: i == selectedIndex, onTap: () => onSelected(i)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarPainter extends CustomPainter {
  const _BottomBarPainter();

  /// Bordinha branca colada no botão: círculo só um pouco maior que ele, sem "abas" largas dos lados.
  static const _ring = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final w = size.width;
    final h = size.height;

    // Degradê acima da barra: o conteúdo "some" suavemente antes da navegação.
    const fade = 28.0;
    final fadeRect = Rect.fromLTWH(0, -fade, w, fade);
    canvas.drawRect(
      fadeRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00103E37), Color(0x14103E37)],
        ).createShader(fadeRect),
    );

    // Barra + bordinha redonda em volta do botão do Costelinha.
    final bar = Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    final ring = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx, HoinkBottomBar.buttonCenterY),
          radius: HoinkBottomBar.buttonSize / 2 + _ring,
        ),
      );
    final path = Path.combine(PathOperation.union, bar, ring);
    canvas.drawShadow(path, const Color(0x55103E37), 6, false);
    canvas.drawPath(path, Paint()..color = HoinkColors.surfaceLowest);
  }

  @override
  bool shouldRepaint(_BottomBarPainter oldDelegate) => false;
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({required this.item, required this.active, required this.onTap});
  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        containedInkWell: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: active ? HoinkColors.surfaceContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(item.icon, size: 22, color: HoinkColors.pine, fill: active ? 1 : 0),
            ),
            const SizedBox(height: 4),
            _NavLabel(item.label, active: active),
          ],
        ),
      ),
    );
  }
}

/// Rótulo da aba em uma linha só: encolhe em telas estreitas em vez de quebrar ("Lançamento / s").
class _NavLabel extends StatelessWidget {
  const _NavLabel(this.text, {required this.active});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style: HoinkText.labelSm.copyWith(
          color: HoinkColors.pine,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// Espaço do meio da barra: só o rótulo; o círculo fica por cima, desenhado pelo [_CostelinhaButton].
class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ExcludeSemantics(child: _NavLabel(label, active: active)),
      ),
    ),
  );
}

class _CostelinhaButton extends StatelessWidget {
  const _CostelinhaButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = HoinkBottomBar.buttonSize;
    return Semantics(
      label: 'Costelinha',
      button: true,
      selected: active,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: HoinkColors.pine,
          border: Border.all(color: active ? HoinkColors.primaryFixed : HoinkColors.pine, width: 3),
          boxShadow: [
            BoxShadow(
              color: HoinkColors.pine.withValues(alpha: active ? 0.45 : 0.3),
              blurRadius: active ? 12 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const Center(child: PigAvatar(size: 26, background: false)),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBusiness = ref.watch(hasBusinessProvider);
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
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, items) in sideNavGroups) ...[
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
                        child: Text(
                          title.toUpperCase(),
                          style: HoinkText.labelSm.copyWith(color: HoinkColors.outline, letterSpacing: 1),
                        ),
                      ),
                    for (final n in items)
                      if (!n.businessOnly || hasBusiness) _SideNavTile(item: n, active: _isActive(location, n.path)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNavTile extends StatefulWidget {
  const _SideNavTile({required this.item, required this.active});
  final NavItem item;
  final bool active;

  @override
  State<_SideNavTile> createState() => _SideNavTileState();
}

/// Item do menu lateral. Ativo: fundo verde com texto claro (o hover só clareia um pouco o verde).
/// Inativo: no hover ganha um fundo verde bem suave e o texto/ícone escurecem para o verde da marca.
class _SideNavTileState extends State<_SideNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active = widget.active;
    final fg = active ? HoinkColors.primaryFixed : (_hover ? HoinkColors.pine : HoinkColors.onSurfaceVariant);
    final bg = active
        ? (_hover ? Color.lerp(HoinkColors.pine, Colors.white, 0.08)! : HoinkColors.pine)
        : (_hover ? HoinkColors.pine.withValues(alpha: 0.06) : Colors.transparent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        key: Key('nav-${item.path}'),
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.go(item.path),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(HoinkRadius.md)),
              child: Row(
                children: [
                  item.pig
                      ? const PigAvatar(size: 22, background: false)
                      : Icon(item.icon, size: 20, color: active || _hover ? fg : (item.iconColor ?? fg)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: HoinkText.bodyMd.copyWith(
                        color: fg,
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
      ),
    );
  }
}

class MonthPicker extends ConsumerWidget {
  const MonthPicker({super.key, this.expanded = false});

  /// Ocupa a largura toda, com o mês no centro e as setas nas pontas (telas de conteúdo).
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final ctrl = ref.read(monthProvider.notifier);
    return Container(
      decoration: BoxDecoration(color: HoinkColors.surfaceLow, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Mês anterior',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.chevron_left, size: 18),
            onPressed: () => ctrl.set(shiftMonth(month, -1)),
          ),
          if (expanded) const Spacer(),
          const Icon(Symbols.calendar_today, size: 16, color: HoinkColors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(monthLabel(month), style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurface)),
          if (expanded) const Spacer(),
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
          const PrivacyToggle(),
          const NotificationBell(),
          // Sem "Novo Lançamento" aqui: a barra aparece em todas as abas e a tela de Lançamentos já tem o seu.
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
          case 'patrimonio':
            context.go('/patrimonio');
          case 'config':
            context.go('/configuracoes');
          case 'extrato':
            context.go('/extrato');
          case 'guia':
            context.go('/guia-de-testes');
          case 'sair':
            await ref.read(authProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'contas', child: Text('Minhas Contas')),
        PopupMenuItem(value: 'extrato', child: Text('Extrato')),
        PopupMenuItem(value: 'recorrencias', child: Text('Recorrências')),
        PopupMenuItem(value: 'pagar', child: Text('Pagar e Receber')),
        PopupMenuItem(value: 'contatos', child: Text('Clientes e Fornecedores')),
        PopupMenuItem(value: 'cartoes', child: Text('Cartões')),
        PopupMenuItem(value: 'dividas', child: Text('Dívidas')),
        PopupMenuItem(value: 'planejamento', child: Text('Planejamento')),
        PopupMenuItem(value: 'patrimonio', child: Text('Patrimônio')),
        PopupMenuItem(value: 'config', child: Text('Configurações')),
        PopupMenuItem(value: 'guia', child: Text('Guia de testes')),
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
          const PrivacyToggle(),
          const NotificationBell(),
          if (user != null) UserMenu(name: user.name, initials: user.initials),
        ],
      ),
    );
  }
}
