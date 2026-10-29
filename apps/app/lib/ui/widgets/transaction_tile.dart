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

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            IconBadge(transactionIcon(t.type, t.category?.icon), background: bg, foreground: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HoinkText.headlineSm.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (t.isRecurring)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Symbols.event_repeat,
                            size: 14,
                            color: HoinkColors.surfaceTint,
                            semanticLabel: 'Recorrente',
                          ),
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
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  t.signedAmount,
                  signed: true,
                  style: HoinkText.headlineSm,
                  color: isIncome ? HoinkColors.surfaceTint : HoinkColors.onSurface,
                ),
                const SizedBox(height: 4),
                if (showStatus && t.effectiveStatus != 'SETTLED')
                  StatusPill(t.effectiveStatus)
                else
                  Text(formatShortDate(t.displayDate), style: HoinkText.bodySm.copyWith(color: HoinkColors.outline)),
                // Recebimento/pagamento parcial: mostra quanto ainda falta.
                if (t.isOpen && t.settledAmountCents > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Falta ${formatBRL(t.remainingCents)}',
                      style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            ?trailingExtra,
          ],
        ),
      ),
    );
  }
}
