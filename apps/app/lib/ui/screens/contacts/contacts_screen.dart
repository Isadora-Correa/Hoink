import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/api_client.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../shell/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transactions_screen.dart' show settleDialog;

final contactsProvider = FutureProvider.family<List<Contact>, ({String entityId, String? kind})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).contacts(a.entityId, kind: a.kind);
});

final contactProvider = FutureProvider.family<Contact, ({String entityId, String id})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).contact(a.entityId, a.id);
});

/// Clientes e fornecedores do ambiente atual, com resumo financeiro de cada um.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String _kind = 'CLIENT';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final entity = ref.watch(currentEntityProvider) ?? (ref.watch(entitiesProvider).value ?? const []).firstOrNull;
    if (entity == null) return const Center(child: CircularProgressIndicator());
    final list = ref.watch(contactsProvider((entityId: entity.id, kind: _kind)));

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 8, wide ? 24 : 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clientes e Fornecedores',
                            style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(
                              color: HoinkColors.primary,
                            ),
                          ),
                          Text(
                            '${entity.name} • faturado, recebido e em aberto de cada contato',
                            style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('new-contact'),
                      onPressed: () => showContactForm(context, ref, entity.id, kind: _kind),
                      icon: const Icon(Symbols.person_add, size: 18),
                      label: Text(wide ? 'Novo contato' : 'Novo'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: HoinkColors.pine,
                        selectedForegroundColor: HoinkColors.ivory,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 'CLIENT',
                          label: Text('Clientes'),
                          icon: Icon(Symbols.handshake, size: 16),
                        ),
                        ButtonSegment(
                          value: 'SUPPLIER',
                          label: Text('Fornecedores'),
                          icon: Icon(Symbols.local_shipping, size: 16),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                    SizedBox(
                      width: 320,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nome',
                          prefixIcon: Icon(Symbols.search, size: 20),
                        ),
                        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                list.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => ErrorState(e),
                  data: (contacts) {
                    final shown = contacts.where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q)).toList();
                    if (shown.isEmpty) {
                      return HoinkCard(
                        child: EmptyState(
                          title: _kind == 'CLIENT' ? 'Nenhum cliente' : 'Nenhum fornecedor',
                          message: _kind == 'CLIENT'
                              ? 'Cadastre clientes para acompanhar cobranças, recebimentos parciais e inadimplência.'
                              : 'Cadastre fornecedores para acompanhar contas a pagar e o histórico de pagamentos.',
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final c in shown) ...[
                          _ContactCard(contact: c, asClient: _kind == 'CLIENT'),
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.asClient});
  final Contact contact;
  final bool asClient;

  @override
  Widget build(BuildContext context) {
    final s = contact.summary;
    final open = asClient ? s.receivableOpenCents : s.payableOpenCents;
    final overdue = asClient ? s.receivableOverdueCents : s.payableOverdueCents;
    return HoinkCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('/contatos/${contact.entityId}/${contact.id}'),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: asClient ? HoinkColors.primaryFixed : HoinkColors.tertiaryFixed,
            child: Text(
              contact.name.characters.first.toUpperCase(),
              style: HoinkText.headlineSm.copyWith(color: asClient ? HoinkColors.pine : HoinkColors.tertiaryContainer),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: HoinkText.headlineSm),
                Text(
                  [contact.formattedDocument, contact.email].whereType<String>().join(' • ').isEmpty
                      ? contactKindLabels[contact.kind]!
                      : [contact.formattedDocument, contact.email].whereType<String>().join(' • '),
                  style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                asClient ? 'A receber' : 'A pagar',
                style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
              MoneyText(open, style: HoinkText.headlineSm),
              if (overdue > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Pill(
                    'Em atraso ${formatBRL(overdue)}',
                    background: HoinkColors.errorContainer,
                    foreground: HoinkColors.onErrorContainer,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cadastro/edição de contato.
Future<void> showContactForm(
  BuildContext context,
  WidgetRef ref,
  String entityId, {
  String kind = 'CLIENT',
  Contact? contact,
}) async {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(text: contact?.name);
  final document = TextEditingController(text: contact?.formattedDocument);
  final email = TextEditingController(text: contact?.email);
  final phone = TextEditingController(text: contact?.phone);
  final notes = TextEditingController(text: contact?.notes);
  var k = contact?.kind ?? kind;
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  contact == null ? 'Novo contato' : 'Editar contato',
                  style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary),
                ),
                const SizedBox(height: 16),
                if (error != null) ...[
                  Text(error!, style: HoinkText.bodySm.copyWith(color: HoinkColors.error)),
                  const SizedBox(height: 8),
                ],
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final e in contactKindLabels.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                  ],
                  selected: {k},
                  onSelectionChanged: (s) => setState(() => k = s.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('contact-name'),
                  controller: name,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                  decoration: const InputDecoration(labelText: 'Nome ou razão social'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: document,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    return d.isEmpty || d.length == 11 || d.length == 14 ? null : 'CPF (11) ou CNPJ (14 dígitos)';
                  },
                  decoration: const InputDecoration(labelText: 'CPF ou CNPJ (opcional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail (opcional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefone (opcional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Serviços, contrato ou observações'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('save-contact'),
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    try {
                      await ref.read(repositoryProvider).saveContact(entityId, {
                        'kind': k,
                        'name': name.text.trim(),
                        'document': document.text.trim(),
                        'email': email.text.trim(),
                        'phone': phone.text.trim(),
                        'notes': notes.text.trim(),
                      }, id: contact?.id);
                      ref.read(dataVersionProvider.notifier).bump();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on ApiException catch (e) {
                      setState(() => error = e.fieldErrors.values.firstOrNull?.first ?? e.message);
                    }
                  },
                  child: Text(contact == null ? 'Cadastrar' : 'Salvar'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Detalhe do contato: resumo (faturado × recebido, em aberto, em atraso) e histórico financeiro.
class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({super.key, required this.entityId, required this.contactId});
  final String entityId;
  final String contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(contactProvider((entityId: entityId, id: contactId)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e),
          data: (c) {
            final s = c.summary;
            Widget stat(String label, int cents, {Color? color}) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer)),
                const SizedBox(height: 6),
                MoneyText(cents, style: HoinkText.headlineSm, color: color ?? Colors.white),
              ],
            );
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Voltar',
                              onPressed: () => context.canPop() ? context.pop() : context.go('/contatos'),
                              icon: const Icon(Symbols.arrow_back),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, style: HoinkText.headlineLgMobile.copyWith(color: HoinkColors.primary)),
                                  Text(
                                    [
                                      contactKindLabels[c.kind],
                                      c.formattedDocument,
                                      c.email,
                                      c.phone,
                                    ].whereType<String>().join(' • '),
                                    style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => showContactForm(context, ref, entityId, contact: c),
                              icon: const Icon(Symbols.edit),
                            ),
                          ],
                        ),
                        if (c.notes != null && c.notes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(48, 4, 0, 0),
                            child: Text(c.notes!, style: HoinkText.bodySm.copyWith(color: HoinkColors.outline)),
                          ),
                        const SizedBox(height: 16),
                        if (c.isClient)
                          HeroCard(
                            child: Wrap(
                              spacing: 32,
                              runSpacing: 16,
                              children: [
                                stat('Faturado', s.billedCents),
                                stat('Recebido', s.receivedCents, color: HoinkColors.mint),
                                stat('A receber', s.receivableOpenCents),
                                stat('Em atraso', s.receivableOverdueCents, color: HoinkColors.tertiaryFixedDim),
                              ],
                            ),
                          ),
                        if (c.isClient && c.isSupplier) const SizedBox(height: 12),
                        if (c.isSupplier)
                          HeroCard(
                            child: Wrap(
                              spacing: 32,
                              runSpacing: 16,
                              children: [
                                stat('Comprado', s.purchasedCents),
                                stat('Pago', s.paidCents, color: HoinkColors.mint),
                                stat('A pagar', s.payableOpenCents),
                                stat('Em atraso', s.payableOverdueCents, color: HoinkColors.tertiaryFixedDim),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (c.isClient)
                              FilledButton.icon(
                                onPressed: () =>
                                    context.push('/lancamentos/novo?tipo=INCOME&contato=${c.id}&ambiente=$entityId'),
                                icon: const Icon(Symbols.request_quote, size: 18),
                                label: const Text('Nova cobrança'),
                              ),
                            if (c.isSupplier)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.push('/lancamentos/novo?tipo=EXPENSE&contato=${c.id}&ambiente=$entityId'),
                                icon: const Icon(Symbols.receipt_long, size: 18),
                                label: const Text('Nova conta a pagar'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        HoinkCard(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Histórico financeiro',
                                style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary),
                              ),
                              if (c.transactions.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                    'Sem lançamentos ainda.',
                                    style: HoinkText.bodyMd.copyWith(color: HoinkColors.outline),
                                  ),
                                ),
                              for (final t in c.transactions) ...[
                                TransactionTile(
                                  t,
                                  onTap: () => context.push('/lancamentos/${t.entityId}/${t.id}'),
                                  trailingExtra: t.isOpen
                                      ? IconButton(
                                          tooltip: t.isIn ? 'Registrar recebimento' : 'Pagar',
                                          icon: const Icon(Symbols.check_circle, color: HoinkColors.surfaceTint),
                                          onPressed: () => settleDialog(context, ref, t),
                                        )
                                      : null,
                                ),
                                if (t != c.transactions.last) const Divider(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
  }
}
