import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/page.dart';
import '../reports/reports_screen.dart' show formatReportCell;

final assistantSuggestionsProvider = FutureProvider<List<String>>(
  (ref) => ref.read(repositoryProvider).assistantSuggestions(),
);

/// Costelinha: perguntas sobre as finanças respondidas com números calculados pela hoink.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <({String question, AssistantAnswer? answer, Object? error})>[];
  bool _busy = false;

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.length < 2 || _busy) return;
    _input.clear();
    setState(() {
      _messages.add((question: q, answer: null, error: null));
      _busy = true;
    });
    final entityId = ref.read(currentEntityProvider)?.id;
    try {
      final a = await ref.read(repositoryProvider).ask(entityId, q);
      setState(() => _messages[_messages.length - 1] = (question: q, answer: a, error: null));
    } catch (e) {
      setState(() => _messages[_messages.length - 1] = (question: q, answer: null, error: e));
    } finally {
      if (mounted) setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final suggestions = ref.watch(assistantSuggestionsProvider).value ?? const <String>[];
    final quick = HoinkCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Symbols.bolt, size: 18, color: HoinkColors.pine),
              const SizedBox(width: 6),
              Text('Perguntas rápidas', style: HoinkText.labelMd),
            ],
          ),
          const SizedBox(height: 10),
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size(0, 42)),
                onPressed: _busy ? null : () => _ask(s),
                child: Row(
                  children: [
                    Expanded(child: Text(s, overflow: TextOverflow.ellipsis)),
                    const Icon(Symbols.arrow_forward, size: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    final how = HoinkCard(
      color: HoinkColors.surfaceLow,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Como a Costelinha responde', style: HoinkText.labelMd),
          const SizedBox(height: 6),
          Text(
            'Perguntas sobre o seu dinheiro são respondidas com números calculados pela hoink. a partir dos seus dados '
            '(saldos, contas, faturas, cofrinhos e índices do Banco Central). Dúvidas comuns, como "o que é o CDI", '
            'têm respostas prontas. Não usa IA paga, não movimenta dinheiro nem indica produtos específicos.',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
          ),
        ],
      ),
    );

    final chat = HoinkCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const IconBadge(
                  Symbols.psychology,
                  background: HoinkColors.tertiaryFixed,
                  foreground: HoinkColors.tertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Costelinha', style: HoinkText.headlineSm),
                      Text(
                        '${ref.watch(currentEntityProvider)?.name ?? 'Consolidado (Total)'} • dados de hoje',
                        style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: wide ? 520 : 460,
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Oi! Pergunte sobre seu dinheiro — por exemplo, "Quanto posso investir este mês?"',
                        textAlign: TextAlign.center,
                        style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _Exchange(message: _messages[i], onAsk: _ask),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('assistant-input'),
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: const InputDecoration(hintText: 'Pergunte algo sobre suas finanças…'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('assistant-send'),
                  onPressed: _busy ? null : () => _ask(_input.text),
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Symbols.send, size: 18),
                  label: const Text('Enviar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return ModulePage(
      title: 'Costelinha IA',
      subtitle: 'Sua assistente financeira: respostas prontas e cálculos feitos com os seus dados.',
      maxWidth: 1200,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 320, child: Column(children: [quick, const SizedBox(height: 16), how])),
              const SizedBox(width: 20),
              Expanded(child: chat),
            ],
          )
        else ...[
          chat,
          const SizedBox(height: 16),
          quick,
          const SizedBox(height: 16),
          how,
        ],
      ],
    );
  }
}

class _Exchange extends StatelessWidget {
  const _Exchange({required this.message, required this.onAsk});
  final ({String question, AssistantAnswer? answer, Object? error}) message;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final a = message.answer;
    final money = a?.facts.where((f) => f.type == 'money').toList() ?? const <AssistantFact>[];
    final others = a?.facts.where((f) => f.type != 'money').toList() ?? const <AssistantFact>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: HoinkColors.pine, borderRadius: BorderRadius.circular(HoinkRadius.lg)),
              child: Text(message.question, style: HoinkText.bodyMd.copyWith(color: HoinkColors.ivory)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (message.error != null)
          Text(
            'Não consegui responder agora. Tente de novo.',
            style: HoinkText.bodyMd.copyWith(color: HoinkColors.error),
          )
        else if (a == null)
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HoinkColors.surfaceLow,
              borderRadius: BorderRadius.circular(HoinkRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(a.title, style: HoinkText.labelMd.copyWith(color: HoinkColors.primary)),
                    ),
                    Pill(
                      a.isReadyAnswer ? 'Resposta pronta' : 'Calculado pela hoink.',
                      icon: a.isReadyAnswer ? Symbols.menu_book : Symbols.calculate,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(a.text, style: HoinkText.bodyMd),
                if (money.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  HeroCard(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 12,
                      children: [
                        for (final f in money)
                          SizedBox(
                            width: 170,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.label.toUpperCase(),
                                  style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer),
                                ),
                                MoneyText((f.value as num).toInt(), style: HoinkText.headlineSm, color: Colors.white),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                for (final f in others)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(f.label, style: HoinkText.bodySm)),
                        Text(formatReportCell(f.type, f.value), style: HoinkText.labelSm),
                      ],
                    ),
                  ),
                if (a.sources.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Fontes: ${a.sources.map((s) => '${s.label}${s.date == null ? '' : ' (${formatBrDate(s.date!)})'}').join('; ')}',
                    style: HoinkText.bodySm.copyWith(color: HoinkColors.outline, fontSize: 11),
                  ),
                ],
                if (a.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final s in a.suggestions) ActionChip(label: Text(s), onPressed: () => onAsk(s))],
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
