import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';
import '../../widgets/page.dart';

final cardsProvider = FutureProvider.family<List<CreditCard>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).cards(entityId);
});

final cardProvider = FutureProvider.family<CreditCard, ({String entityId, String id})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).card(a.entityId, a.id);
});

final invoiceProvider = FutureProvider.family<Invoice, ({String entityId, String cardId, String? month})>((
  ref,
  a,
) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).invoice(a.entityId, a.cardId, month: a.month);
});

Color _invoiceColor(String status) => switch (status) {
  'PAID' => HoinkColors.surfaceTint,
  'OVERDUE' => HoinkColors.error,
  'CLOSED' || 'PARTIAL' => HoinkColors.tertiaryContainer,
  _ => HoinkColors.onSurfaceVariant,
};

class InvoicePill extends StatelessWidget {
  const InvoicePill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Pill(
    invoiceStatusLabels[status] ?? status,
    dot: _invoiceColor(status),
    background: status == 'OVERDUE' ? HoinkColors.errorContainer : HoinkColors.surfaceLow,
    foreground: status == 'OVERDUE' ? HoinkColors.onErrorContainer : HoinkColors.onSurface,
  );
}

/// Cartões de crédito: limite, fatura atual e faturas a pagar.
class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = entitiesInScope(ref);
    final single = shown.length == 1 ? shown.first : null;
    return ModulePage(
      title: 'Cartões de crédito',
      subtitle: 'Compras e parcelas entram como despesa uma vez só; pagar a fatura é uma transferência da sua conta.',
      action: single != null && single.canWrite
          ? FilledButton.icon(
              key: const Key('new-card'),
              onPressed: () => showCardForm(context, ref, single.id),
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('Novo cartão'),
            )
          : null,
      children: [
        for (final e in shown) ...[
          if (shown.length > 1)
            EntityHeading(
              e,
              trailing: e.canWrite
                  ? TextButton.icon(
                      onPressed: () => showCardForm(context, ref, e.id),
                      icon: const Icon(Symbols.add, size: 18),
                      label: const Text('Novo cartão'),
                    )
                  : null,
            ),
          _EntityCards(entity: e),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _EntityCards extends ConsumerWidget {
  const _EntityCards({required this.entity});
  final FinancialEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(cardsProvider(entity.id))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(cardsProvider(entity.id))),
          data: (cards) {
            if (cards.isEmpty) {
              return HoinkCard(
                child: EmptyState(
                  title: 'Nenhum cartão cadastrado',
                  message: 'Cadastre o cartão com limite, fechamento e vencimento para acompanhar faturas e parcelas.',
                  action: entity.canWrite
                      ? FilledButton(
                          onPressed: () => showCardForm(context, ref, entity.id),
                          child: const Text('Cadastrar cartão'),
                        )
                      : null,
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
                final w = (c.maxWidth - (cols - 1) * 16) / cols;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width: w,
                        child: _CardTile(card: card),
                      ),
                  ],
                );
              },
            );
          },
        );
  }
}

/// Visual do cartão (superfície verde-pinho) com limite usado e disponível.
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.card});
  final CreditCard card;

  @override
  Widget build(BuildContext context) {
    final used = card.limitCents > 0 ? card.usedCents / card.limitCents : 0.0;
    return HeroCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.credit_card, color: HoinkColors.mint, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HoinkText.headlineSm.copyWith(color: HoinkColors.ivory),
                ),
              ),
              if (card.brand != null)
                Text(card.brand!, style: HoinkText.labelSm.copyWith(color: HoinkColors.primaryFixedDim)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'DISPONÍVEL',
            style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer, letterSpacing: 1),
          ),
          MoneyText(card.availableCents, style: HoinkText.headlineMd, color: Colors.white),
          const SizedBox(height: 12),
          ProgressRail(value: used, color: HoinkColors.pigPink, track: const Color(0x33FFFFFF)),
          const SizedBox(height: 6),
          Text(
            'Usado ${formatBRL(card.usedCents)} de ${formatBRL(card.limitCents)}',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.primaryFixedDim),
          ),
          Text(
            'Fecha dia ${card.closingDay} • vence dia ${card.dueDay}',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.primaryFixedDim),
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card});
  final CreditCard card;

  @override
  Widget build(BuildContext context) {
    final inv = card.currentInvoice;
    final pending = card.pendingInvoices;
    return InkWell(
      borderRadius: BorderRadius.circular(HoinkRadius.xl),
      onTap: () => context.push('/cartoes/${card.entityId}/${card.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardFace(card: card),
          const SizedBox(height: 10),
          HoinkCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Fatura de ${monthLabel(inv.month)}', style: HoinkText.labelMd)),
                    InvoicePill(inv.status),
                  ],
                ),
                const SizedBox(height: 6),
                MoneyText(inv.totalCents, style: HoinkText.headlineSm),
                Text(
                  'Fecha ${formatBrDate(inv.closingDate)} • vence ${formatBrDate(inv.dueDate)}',
                  style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
                for (final p in pending) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      Icon(
                        p.status == 'OVERDUE' ? Symbols.warning : Symbols.receipt_long,
                        size: 16,
                        color: _invoiceColor(p.status),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'A pagar: ${monthLabel(p.month)} (vence ${formatBrDate(p.dueDate)})',
                          style: HoinkText.bodySm,
                        ),
                      ),
                      Text(formatBRL(p.remainingCents), style: HoinkText.labelMd),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cadastro/edição do cartão. Fechamento e vencimento só são definidos no cadastro.
Future<void> showCardForm(BuildContext context, WidgetRef ref, String entityId, {CreditCard? card}) async {
  final accounts = (await ref.read(accountsProvider(entityId).future)).where((a) => !a.archived).toList();
  if (!context.mounted) return;
  final name = TextEditingController(text: card?.name);
  final institution = TextEditingController(text: card?.institution);
  final brand = TextEditingController(text: card?.brand);
  final limit = TextEditingController(text: card == null ? '' : formatAmount(card.limitCents));
  var closing = card?.closingDay ?? 3;
  var due = card?.dueDay ?? 10;
  var paymentAccountId = card?.paymentAccountId ?? accounts.firstOrNull?.id;
  final days = [for (var d = 1; d <= 31; d++) d];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(card == null ? 'Novo cartão' : 'Editar cartão'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('card-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome do cartão', hintText: 'Ex.: Nubank Roxinho'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: institution,
                        decoration: const InputDecoration(labelText: 'Banco'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: brand,
                        decoration: const InputDecoration(labelText: 'Bandeira'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MoneyField(controller: limit, label: 'Limite total', fieldKey: const Key('card-limit')),
                if (card == null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: closing,
                          decoration: const InputDecoration(labelText: 'Dia do fechamento'),
                          items: [for (final d in days) DropdownMenuItem(value: d, child: Text('$d'))],
                          onChanged: (v) => setState(() => closing = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: due,
                          decoration: const InputDecoration(labelText: 'Dia do vencimento'),
                          items: [for (final d in days) DropdownMenuItem(value: d, child: Text('$d'))],
                          onChanged: (v) => setState(() => due = v!),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: paymentAccountId,
                  decoration: const InputDecoration(labelText: 'Conta que paga a fatura'),
                  items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                  onChanged: (v) => setState(() => paymentAccountId = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('save-card'),
            onPressed: () async {
              final cents = parseBRLToCents(limit.text);
              if (name.text.trim().isEmpty || cents == null || cents < 0) {
                showError(ctx, 'Informe o nome e o limite do cartão');
                return;
              }
              final body = <String, Object?>{
                'name': name.text.trim(),
                'institution': institution.text.trim().isEmpty ? null : institution.text.trim(),
                'brand': brand.text.trim().isEmpty ? null : brand.text.trim(),
                'limitCents': cents,
                'paymentAccountId': paymentAccountId,
                if (card == null) 'closingDay': closing,
                if (card == null) 'dueDay': due,
              };
              final ok = await runAction(
                ctx,
                ref,
                () => ref.read(repositoryProvider).saveCard(entityId, body, id: card?.id),
                card == null ? 'Cartão cadastrado' : 'Cartão atualizado',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

/// Detalhe do cartão com navegação entre faturas.
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({super.key, required this.entityId, required this.cardId});
  final String entityId;
  final String cardId;
  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  String? _month;

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardProvider((entityId: widget.entityId, id: widget.cardId)));
    return cardAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e),
      data: (card) {
        final month = _month ?? card.currentInvoice.month;
        final invoice = ref.watch(invoiceProvider((entityId: widget.entityId, cardId: card.id, month: month)));
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final face = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardFace(card: card),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('new-purchase'),
                  onPressed: () => showPurchaseForm(context, ref, card),
                  icon: const Icon(Symbols.add_shopping_cart, size: 18),
                  label: const Text('Nova compra'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showCardForm(context, ref, card.entityId, card: card),
                  icon: const Icon(Symbols.edit, size: 18),
                  label: const Text('Editar'),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await runAction(
                      context,
                      ref,
                      () => ref.read(repositoryProvider).archiveCard(card.entityId, card.id),
                      'Cartão arquivado',
                    );
                    if (ok && context.mounted) context.go('/cartoes');
                  },
                  child: const Text('Arquivar'),
                ),
              ],
            ),
          ],
        );
        final invoicePane = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Fatura anterior',
                  onPressed: () => setState(() => _month = shiftMonth(month, -1)),
                  icon: const Icon(Symbols.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Fatura de ${monthLabel(month)}',
                    textAlign: TextAlign.center,
                    style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary),
                  ),
                ),
                IconButton(
                  tooltip: 'Próxima fatura',
                  onPressed: () => setState(() => _month = shiftMonth(month, 1)),
                  icon: const Icon(Symbols.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            invoice.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorState(e),
              data: (inv) => _InvoiceView(card: card, invoice: inv),
            ),
          ],
        );
        return ModulePage(
          title: card.name,
          subtitle: card.paymentAccountName == null
              ? 'Cartão de crédito'
              : 'Fatura paga pela conta ${card.paymentAccountName}',
          leading: IconButton(onPressed: () => context.go('/cartoes'), icon: const Icon(Symbols.arrow_back)),
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 340, child: face),
                  const SizedBox(width: 24),
                  Expanded(child: invoicePane),
                ],
              )
            else ...[
              face,
              const SizedBox(height: 20),
              invoicePane,
            ],
          ],
        );
      },
    );
  }
}

class _InvoiceView extends ConsumerWidget {
  const _InvoiceView({required this.card, required this.invoice});
  final CreditCard card;
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = invoice.summary;
    final canPay = s.id != null && s.remainingCents > 0 && s.status != 'OPEN';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoinkCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: MoneyText(s.totalCents, style: HoinkText.headlineLg)),
                  InvoicePill(s.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Fecha em ${formatBrDate(s.closingDate)} • vence em ${formatBrDate(s.dueDate)}',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ValueRow('Pago', s.paidCents),
              ValueRow('Falta pagar', s.remainingCents, bold: true),
              if (s.id != null && s.remainingCents > 0) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('pay-invoice'),
                  onPressed: () => showPayInvoice(context, ref, card, s),
                  icon: const Icon(Symbols.payments, size: 18),
                  label: Text(canPay ? 'Pagar fatura' : 'Antecipar pagamento'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        HoinkCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: invoice.items.isEmpty
              ? const EmptyState(title: 'Fatura sem compras', message: 'As compras e parcelas deste mês aparecem aqui.')
              : Column(
                  children: [
                    for (final it in invoice.items) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: IconBadge(categoryIcon(it.txn.category?.icon)),
                        title: Text(it.txn.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if (it.purchaseDate != null) 'Compra em ${formatBrDate(it.purchaseDate!)}',
                            if (it.installmentCount > 1) 'Parcela ${it.installmentNumber}/${it.installmentCount}',
                            ?it.txn.category?.name,
                          ].join(' • '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatBRL(it.txn.amountCents), style: HoinkText.labelMd),
                            if (it.purchaseId != null)
                              PopupMenuButton<String>(
                                tooltip: 'Opções da compra',
                                onSelected: (_) => _deletePurchase(context, ref, it),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'delete', child: Text('Excluir compra (todas as parcelas)')),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (it != invoice.items.last) const Divider(height: 1),
                    ],
                  ],
                ),
        ),
        if (invoice.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Pagamentos', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
          const SizedBox(height: 8),
          HoinkCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                for (final p in invoice.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconBadge(Symbols.check_circle),
                    title: Text('Pagamento em ${formatBrDate(p.date)}'),
                    trailing: Text(formatBRL(p.amountCents), style: HoinkText.labelMd),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _deletePurchase(BuildContext context, WidgetRef ref, InvoiceItem it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir compra?'),
        content: Text(
          it.installmentCount > 1
              ? 'Todas as ${it.installmentCount} parcelas serão removidas e o limite será liberado.'
              : 'A compra será removida e o limite liberado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).deletePurchase(card.entityId, card.id, it.purchaseId!),
      'Compra excluída',
    );
  }
}

/// Compra à vista ou parcelada. O app só envia o total e o número de parcelas: a divisão é feita na API.
Future<void> showPurchaseForm(BuildContext context, WidgetRef ref, CreditCard card) async {
  final categories = (await ref.read(categoriesProvider(card.entityId).future))
      .where((c) => c.kind == 'EXPENSE')
      .toList();
  if (!context.mounted) return;
  final description = TextEditingController();
  final total = TextEditingController();
  var installments = 1;
  var date = DateTime.now();
  String? categoryId;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Compra no ${card.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('purchase-description'),
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                const SizedBox(height: 12),
                MoneyField(controller: total, label: 'Valor total', fieldKey: const Key('purchase-total')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('purchase-installments'),
                  initialValue: installments,
                  decoration: const InputDecoration(labelText: 'Parcelas'),
                  items: [
                    for (var n = 1; n <= 24; n++) DropdownMenuItem(value: n, child: Text(n == 1 ? 'À vista' : '${n}x')),
                  ],
                  onChanged: (v) => setState(() => installments = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
                const SizedBox(height: 12),
                DateField(label: 'Data da compra', value: date, onChanged: (d) => setState(() => date = d)),
                const SizedBox(height: 8),
                Text(
                  'Disponível: ${formatBRL(card.availableCents)}. Compras a partir do dia ${card.closingDay} entram na fatura seguinte.',
                  style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('save-purchase'),
            onPressed: () async {
              final cents = parseBRLToCents(total.text);
              if (description.text.trim().isEmpty || cents == null || cents <= 0) {
                showError(ctx, 'Informe a descrição e o valor');
                return;
              }
              final ok = await runAction(
                ctx,
                ref,
                () => ref.read(repositoryProvider).createPurchase(card.entityId, card.id, {
                  'description': description.text.trim(),
                  'totalCents': cents,
                  'installments': installments,
                  'purchaseDate': isoDate(date),
                  'categoryId': categoryId,
                }),
                installments > 1 ? 'Compra parcelada em ${installments}x registrada' : 'Compra registrada',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    ),
  );
}

/// Pagamento da fatura: transferência da conta escolhida para o cartão (não é nova despesa).
Future<void> showPayInvoice(BuildContext context, WidgetRef ref, CreditCard card, InvoiceSummary inv) async {
  final accounts = (await ref.read(accountsProvider(card.entityId).future)).where((a) => !a.archived).toList();
  if (!context.mounted) return;
  final amount = TextEditingController(text: formatAmount(inv.remainingCents));
  var date = DateTime.now();
  var from = card.paymentAccountId ?? accounts.firstOrNull?.id;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Pagar fatura de ${monthLabel(inv.month)}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Falta pagar ${formatBRL(inv.remainingCents)}', style: HoinkText.bodyMd),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: from,
                decoration: const InputDecoration(labelText: 'Pagar com a conta'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${formatBRL(a.balanceCents)})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => from = v),
              ),
              const SizedBox(height: 12),
              MoneyField(
                controller: amount,
                label: 'Valor',
                helper: 'Pode pagar só uma parte; o restante continua em aberto.',
                fieldKey: const Key('invoice-amount'),
              ),
              const SizedBox(height: 12),
              DateField(label: 'Data', value: date, onChanged: (d) => setState(() => date = d)),
              const SizedBox(height: 8),
              Text(
                'O pagamento é uma transferência entre suas contas: as compras já foram contadas como despesa.',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirm-pay-invoice'),
            onPressed: () async {
              final cents = parseBRLToCents(amount.text);
              if (from == null || cents == null || cents <= 0 || cents > inv.remainingCents) {
                showError(ctx, 'Escolha a conta e um valor até ${formatBRL(inv.remainingCents)}');
                return;
              }
              final ok = await runAction(
                ctx,
                ref,
                () => ref
                    .read(repositoryProvider)
                    .payInvoice(
                      card.entityId,
                      card.id,
                      inv.id!,
                      fromAccountId: from!,
                      date: isoDate(date),
                      amountCents: cents,
                    ),
                cents == inv.remainingCents ? 'Fatura paga' : 'Pagamento parcial registrado',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Pagar'),
          ),
        ],
      ),
    ),
  );
}
