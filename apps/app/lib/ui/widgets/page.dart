import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../shell/app_shell.dart';
import 'common.dart';
import '../../core/money_input.dart';

/// Estrutura padrão das telas de módulo: título, subtítulo, ação principal e conteúdo centralizado.
class ModulePage extends StatelessWidget {
  const ModulePage({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    required this.children,
    this.maxWidth = 1100,
    this.leading,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? leading;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 8, wide ? 24 : 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 8)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(
                              color: HoinkColors.primary,
                            ),
                          ),
                          if (subtitle != null)
                            Text(subtitle!, style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (action != null) ...[const SizedBox(width: 12), action!],
                  ],
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Ambientes exibidos no escopo atual (todos no Total; senão o ambiente escolhido).
List<FinancialEntity> entitiesInScope(WidgetRef ref) {
  final scope = ref.watch(effectiveScopeProvider);
  final entities = ref.watch(entitiesProvider).value ?? const <FinancialEntity>[];
  final current = ref.watch(currentEntityProvider);
  return scope == Scope.total ? entities : [?current];
}

/// Cabeçalho de ambiente (Pessoal / Profissional) nas listas do escopo Total.
class EntityHeading extends StatelessWidget {
  const EntityHeading(this.entity, {super.key, this.trailing});
  final FinancialEntity entity;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(entity.isPersonal ? Symbols.person : Symbols.business_center, color: HoinkColors.pine),
        const SizedBox(width: 8),
        Expanded(
          child: Text(entity.name, style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Executa uma ação de escrita, recarrega os dados e mostra o resultado.
Future<bool> runAction(BuildContext context, WidgetRef ref, Future<void> Function() action, String success) async {
  try {
    await action();
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) showSuccess(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// Indicador compacto (rótulo + valor).
class KpiTile extends StatelessWidget {
  const KpiTile(this.label, this.cents, {super.key, this.icon, this.color, this.width = 220, this.caption});
  final String label;
  final int cents;
  final IconData? icon;
  final Color? color;
  final double width;
  final String? caption;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: HoinkCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: color ?? HoinkColors.pine), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MoneyText(cents, style: HoinkText.headlineMd, color: cents < 0 ? HoinkColors.error : null),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
          ],
        ],
      ),
    ),
  );
}

/// Linha "rótulo ........ valor" usada em resumos.
class ValueRow extends StatelessWidget {
  const ValueRow(this.label, this.cents, {super.key, this.bold = false, this.color});
  final String label;
  final int cents;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: (bold ? HoinkText.labelMd : HoinkText.bodyMd).copyWith(color: HoinkColors.onSurfaceVariant),
          ),
        ),
        Text(
          formatBRL(cents),
          style: (bold ? HoinkText.labelMd : HoinkText.bodyMd).copyWith(
            color: color ?? HoinkColors.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// Botão que abre o seletor de data.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.fieldKey});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: fieldKey,
    icon: const Icon(Symbols.calendar_today, size: 18),
    label: Text('$label: ${formatBrDate(isoDate(value))}'),
    onPressed: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (d != null) onChanged(d);
    },
  );
}

/// Campo de valor em reais (texto livre "1.234,56").
class MoneyField extends StatelessWidget {
  const MoneyField({super.key, required this.controller, required this.label, this.helper, this.fieldKey});
  final TextEditingController controller;
  final String label;
  final String? helper;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [BrlInputFormatter()],
    decoration: InputDecoration(labelText: label, prefixText: 'R\$ ', helperText: helper, helperMaxLines: 2),
  );
}

/// Aviso destacado (alertas de orçamento, caixa negativo).
class AlertBanner extends StatelessWidget {
  const AlertBanner(this.messages, {super.key, this.icon = Symbols.warning});
  final List<String> messages;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: HoinkColors.tertiaryFixed, borderRadius: BorderRadius.circular(HoinkRadius.md)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: HoinkColors.tertiaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in messages) Text(m, style: HoinkText.bodyMd.copyWith(color: HoinkColors.onTertiaryFixed)),
            ],
          ),
        ),
      ],
    ),
  );
}
