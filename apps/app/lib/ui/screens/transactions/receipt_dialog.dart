import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';

/// Leitura de nota fiscal (NFC-e): câmera no celular ou link/chave colados. Devolve a prévia
/// confirmada pelo usuário — nada é lançado sem passar pelo formulário.
Future<ReceiptPreview?> showReceiptDialog(BuildContext context, WidgetRef ref, String entityId) {
  return showDialog<ReceiptPreview>(
    context: context,
    builder: (_) => _ReceiptDialog(entityId: entityId),
  );
}

class _ReceiptDialog extends ConsumerStatefulWidget {
  const _ReceiptDialog({required this.entityId});
  final String entityId;
  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  final _code = TextEditingController();
  ReceiptPreview? _preview;
  bool _busy = false;

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage()));
    if (value != null && mounted) {
      _code.text = value;
      await _read();
    }
  }

  Future<void> _read() async {
    if (_code.text.trim().isEmpty) return showError(context, 'Leia o QR Code ou cole o link/chave da nota');
    setState(() => _busy = true);
    try {
      final p = await ref.read(repositoryProvider).receiptPreview(widget.entityId, _code.text.trim());
      setState(() => _preview = p);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return AlertDialog(
      title: const Text('Ler nota fiscal'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (p == null) ...[
                Text(
                  'Use o QR Code impresso no cupom (NFC-e). A hoink. consulta a nota no site da Secretaria da Fazenda.',
                  style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (!kIsWeb) ...[
                  FilledButton.icon(
                    key: const Key('scan-receipt'),
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Symbols.qr_code_scanner, size: 18),
                    label: const Text('Escanear QR Code'),
                  ),
                  const SizedBox(height: 16),
                  Text('ou', textAlign: TextAlign.center, style: HoinkText.bodySm),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('receipt-code'),
                  controller: _code,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Link do QR Code ou chave de acesso',
                    helperText: 'A chave tem 44 números e fica abaixo do QR Code.',
                  ),
                ),
              ] else
                _PreviewView(p),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (p == null)
          FilledButton(
            key: const Key('read-receipt-confirm'),
            onPressed: _busy ? null : _read,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Ler nota'),
          )
        else
          FilledButton(
            key: const Key('use-receipt'),
            onPressed: () => Navigator.pop(context, p),
            child: const Text('Usar estes dados'),
          ),
      ],
    );
  }
}

class _PreviewView extends StatelessWidget {
  const _PreviewView(this.p);
  final ReceiptPreview p;

  @override
  Widget build(BuildContext context) {
    final muted = HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.alreadyRegistered) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HoinkColors.errorContainer,
              borderRadius: BorderRadius.circular(HoinkRadius.md),
            ),
            child: Text(
              'Esta nota já foi lançada.',
              style: HoinkText.bodyMd.copyWith(color: HoinkColors.onErrorContainer),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(p.issuerName ?? 'Loja CNPJ ${p.cnpj}', style: HoinkText.headlineSm),
        Text(
          [
            if (p.issuedAt != null) formatBrDate(p.issuedAt!) else monthLabel(p.issuedMonth),
            ?p.paymentMethod,
            ?p.suggestedCategoryName,
          ].join(' • '),
          style: muted,
        ),
        const SizedBox(height: 12),
        if (p.totalCents != null)
          MoneyText(p.totalCents!, style: HoinkText.headlineLg)
        else
          Text('Valor não disponível: informe no formulário.', style: HoinkText.bodyMd),
        if (p.discountCents != null && p.discountCents! > 0)
          Text('Desconto de ${formatBRL(p.discountCents!)}', style: muted),
        if (p.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('${p.items.length} ${p.items.length == 1 ? 'item' : 'itens'}', style: HoinkText.labelMd),
          for (final i in p.items.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(i.description, style: HoinkText.bodySm, overflow: TextOverflow.ellipsis),
                  ),
                  Text(formatBRL(i.totalCents), style: HoinkText.bodySm),
                ],
              ),
            ),
          if (p.items.length > 8) Text('… e mais ${p.items.length - 8}', style: muted),
        ],
        const SizedBox(height: 12),
        Text(
          p.source == 'SEFAZ' ? 'Dados da consulta oficial da Secretaria da Fazenda. Confira antes de salvar.' : 'Não foi possível abrir a consulta da Fazenda (alguns estados pedem captcha). Usamos os dados do QR Code; complete o que faltar.',
          style: muted,
        ),
      ],
    );
  }
}

/// Câmera para ler o QR Code (Android/iOS).
class _ScannerPage extends StatefulWidget {
  const _ScannerPage();
  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aponte para o QR Code da nota')),
    body: MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
        if (value == null || _done) return;
        _done = true;
        Navigator.pop(context, value);
      },
    ),
  );
}
