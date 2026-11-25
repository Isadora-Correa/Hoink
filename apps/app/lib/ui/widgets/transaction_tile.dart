import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import 'common.dart';
import 'icons.dart';

/// Item de lançamento: ícone 40×40, descrição + categoria/conta, valor alinhado à direita.
class TransactionTile extends StatelessWidget {
  const TransactionTile(this.t, {super.key, this.onTap, this.showStatus = true, this.trailingExtra});
  final Txn t;
  final VoidCallback? onTap;
  final bool showStatus;
  final Widget? trailingExtra;

  @override
  Widget build(BuildContext context) {
    final isIncome = t.isIn && !t.isTransfer;
    final (bg, fg) = switch (t.type) {
      'INCOME' => (HoinkColors.surfaceContainer, HoinkColors.surfaceTint),
      'TRANSFER' => (HoinkColors.surfaceLow, HoinkColors.onSurfaceVariant),
      'CONTRIBUTION' || 'REDEMPTION' => (HoinkColors.tertiaryFixed, HoinkColors.tertiaryContainer),
      _ =>
        t.effectiveStatus == 'OVERDUE'
            ? (HoinkColors.errorContainer, HoinkColors.onErrorContainer)
            : (HoinkColors.surfaceLow, HoinkColors.pine),
    };
    final subtitle = [
      t.category?.name ??
          (t.isTransfer
              ? (transferClassificationLabels[t.transferClassification] ?? 'Transferência')
              : transactionTypeLabels[t.type]),
      t.account.name,
    ].whereType<String>().join(' • ');

    final title = Text(
      t.description,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: HoinkText.headlineSm.copyWith(fontSize: 15),
    );
    final details = Row(
      children: [
        if (t.isRecurring)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Symbols.event_repeat, size: 14, color: HoinkColors.surfaceTint, semanticLabel: 'Recorrente'),
          ),
        Flexible(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
          ),
        ),
      ],
    );
    final amount = MoneyText(
      t.signedAmount,
      signed: true,
      style: HoinkText.headlineSm,
      color: isIncome ? HoinkColors.surfaceTint : HoinkColors.onSurface,
    );
    final status = showStatus && t.effectiveStatus != 'SETTLED'
        ? StatusPill(t.effectiveStatus)
        : Text(formatShortDate(t.displayDate), style: HoinkText.bodySm.copyWith(color: HoinkColors.outline));
    // Recebimento/pagamento parcial: mostra quanto ainda falta.
    final remaining = t.isOpen && t.settledAmountCents > 0
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Falta ${formatBRL(t.remainingCents)}',
              style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
          )
        : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: LayoutBuilder(
          builder: (context, c) {
            final icon = IconBadge(transactionIcon(t.type, t.category?.icon), background: bg, foreground: fg);
            if (c.maxWidth >= 480) {
              return Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 2), details],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [amount, const SizedBox(height: 4), status, ?remaining],
                  ),
                  ?trailingExtra,
                ],
              );
            }
            // Celular: o nome usa a linha toda; embaixo, categoria/conta e depois status/data + valor.
            // Com valor e status ao lado, o nome ficava com ~80px e quebrava no meio ("Financia-mento").
            return Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 2),
                      details,
                      const SizedBox(height: 6),
                      Row(children: [status, const Spacer(), amount]),
                      ?remaining,
                    ],
                  ),
                ),
                ?trailingExtra,
              ],
            );
          },
        ),
      ),
    );
  }
}
