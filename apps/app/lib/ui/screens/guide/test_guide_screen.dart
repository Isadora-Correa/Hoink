import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/page.dart';

class _Check {
  const _Check(this.id, this.title, this.route, this.steps, this.expected);
  final String id;
  final String title;
  final String route;
  final List<String> steps;
  final String expected;
}

class _Group {
  const _Group(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<_Check> items;
}

/// Roteiro de testes com os dados de demonstração (miguel@hoink.dev). Cada item leva à tela certa.
const _groups = [
  _Group('Começo', Symbols.flag, [
    _Check('ambientes', 'Pessoal, Pro e Total', '/', [
      'No topo do menu, alterne entre Pessoal, Pro e Total.',
    ], 'Os números do Início mudam; no Total, o pró-labore entre PJ e PF não aparece como receita nem despesa.'),
    _Check('olhinho', 'Esconder valores (olhinho)', '/lancamentos', [
      'Toque no olho ao lado do sino, no topo.',
      'Navegue por Lançamentos, Cartões e Início.',
    ], 'Todo valor vira "R\$ ••••••" e os gráficos ficam borrados. Toque de novo para mostrar.'),
    _Check('mascara', 'Digitar valores', '/lancamentos/novo', [
      'No valor do lançamento, digite 1, depois 12, depois 1112.',
      'Digite a vírgula e 50.',
    ], 'Aparece 1,00 → 12,00 → 1.112,00 → 1.112,50.'),
  ]),
  _Group('Dia a dia', Symbols.receipt_long, [
    _Check('lancamento', 'Lançar uma despesa', '/lancamentos/novo', [
      'Informe valor, descrição, categoria e a conta Nubank Ultravioleta.',
      'Salve e abra Extrato → Nubank Ultravioleta.',
    ], 'O lançamento aparece no extrato e o saldo da conta diminui exatamente o valor.'),
    _Check('extrato', 'Extrato da conta', '/extrato', [
      'Escolha a conta no topo e troque o mês nas setas.',
    ], 'Saldo de abertura, cada movimentação com o saldo acumulado e o saldo de fechamento.'),
    _Check('nota', 'Ler nota fiscal', '/lancamentos/novo', [
      'Toque em "Ler nota fiscal".',
      'Escaneie o QR Code de um cupom (celular) ou cole o link do QR.',
    ], 'Loja, valor, data, categoria e itens vêm preenchidos; a mesma nota não pode ser lançada duas vezes.'),
    _Check('transferencia', 'Pró-labore PJ → PF', '/lancamentos/novo?tipo=TRANSFER', [
      'Escolha Transferência, de Banco Inter PJ para Nubank Ultravioleta, classificação Pró-labore.',
    ], 'Sai do PJ, entra no PF; não conta como receita nem despesa.'),
    _Check('recorrencia', 'Conta de luz variável', '/recorrencias', [
      'Abra "Conta de Luz • Enel" e pague a próxima ocorrência informando o valor real (ex.: 287,50).',
    ], 'Só aquela ocorrência muda; as próximas continuam com R\$ 250,00.'),
    _Check('conciliar', 'Conciliar saldo', '/contas', [
      'No menu (⋮) de uma conta, escolha Conciliar saldo e informe o saldo do banco.',
    ], 'A hoink. mostra a diferença e, se você quiser, cria um ajuste rastreável.'),
  ]),
  _Group('Contas e clientes', Symbols.request_quote, [
    _Check('receber', 'Recebimento parcial (ambiente Pro)', '/contas-a-pagar', [
      'No Pro, veja "Landing page Nexa" (R\$ 4.800,00 com R\$ 2.000,00 já recebidos) e registre mais um recebimento.',
    ], 'Mostra "Falta R\$ X" e o histórico de cada recebimento com a data.'),
    _Check('clientes', 'Faturado × recebido', '/contatos', [
      'No Pro, abra Studio Alpha e Nexa Tecnologia.',
    ], 'Totais de faturado, recebido, em aberto e em atraso, e o histórico do cliente.'),
  ]),
  _Group('Cartões e dívidas', Symbols.credit_card, [
    _Check('compra', 'Compra parcelada', '/cartoes', [
      'Abra Nubank Roxinho → Nova compra, 3x, R\$ 300,00.',
    ], 'O limite disponível cai R\$ 300,00 e cada fatura seguinte ganha uma parcela de R\$ 100,00.'),
    _Check('fatura', 'Pagar fatura sem duplicar', '/cartoes', [
      'Pague uma fatura pela conta Nubank Ultravioleta e depois veja o Início.',
    ], 'O saldo da conta cai, mas a despesa do mês não aumenta de novo (a compra já foi contada).'),
    _Check('divida', 'Parcela com multa, amortização e quitação', '/dividas', [
      'Abra "Financiamento Onix": pague uma parcela com multa, faça uma amortização e simule a quitação.',
    ], 'Principal, juros e multa aparecem separados; a quitação mostra quanto você economiza de juros.'),
  ]),
  _Group('Planejamento', Symbols.calendar_month, [
    _Check('projecao', 'Fluxo de caixa 30/60/90 dias', '/planejamento', [
      'Alterne entre 30, 60 e 90 dias.',
    ], 'Duas linhas: só o confirmado e com os previstos (recorrências).'),
    _Check('orcamento', 'Orçamentos e alertas', '/planejamento', [
      'Crie um orçamento baixo para Mercado (ex.: R\$ 100,00).',
    ], 'Aparece o alerta de orçamento estourado e uma notificação no sino.'),
  ]),
  _Group('Patrimônio', Symbols.savings, [
    _Check('cofrinho', 'Lista de desejos e conquistas', '/cofrinhos', [
      'Em "PS5 para o namorado", toque em Guardar e guarde R\$ 300,00.',
    ], 'O saldo da conta cai, o cofrinho sobe, a despesa do mês não muda e pode aparecer uma conquista.'),
    _Check('comprei', '"Comprei!"', '/cofrinhos', [
      'Abra um desejo e toque em Comprei!, lançando a compra.',
    ], 'O dinheiro volta para a conta e a compra vira uma única despesa; conquista "Desejo realizado".'),
    _Check('investimentos', 'Investimentos e comparador', '/investimentos', [
      'Abra Itaúsa → Atualizar cotação. Depois toque em Comparar.',
    ], 'O valor muda com o novo preço; o comparador mostra o líquido de cada aplicação após o IR.'),
    _Check('patrimonio', 'Patrimônio líquido', '/patrimonio', [
      'Confira ativos, passivos e a evolução mensal.',
    ], 'Dinheiro guardado em cofrinho ou investido não é somado duas vezes.'),
  ]),
  _Group('Inteligência', Symbols.psychology, [
    _Check('costelinha', 'Costelinha IA', '/costelinha', [
      'Toque em "Quanto posso investir este mês?".',
    ], 'Resposta com os números, as fontes e as datas; o dinheiro da reserva de emergência não entra como sobra.'),
    _Check('relatorios', 'Relatórios em PDF, planilha e CSV', '/relatorios', [
      'Escolha Receitas e despesas → Ver na tela → PDF.',
    ], 'Os valores do PDF são os mesmos da tela e do Início.'),
    _Check('notificacoes', 'Notificações', '/', [
      'Toque no sino no topo.',
    ], 'Avisos de contas vencendo, atrasadas e orçamentos; tocar leva à tela certa.'),
  ]),
  _Group('Conta', Symbols.settings, [
    _Check('perfil', 'Foto e conta profissional', '/configuracoes', [
      'Troque a foto de perfil e ative/desative a conta profissional.',
    ], 'A foto aparece no topo; sem conta profissional, o seletor Pessoal/Pro/Total some (os dados ficam guardados).'),
  ]),
];

const _prefsKey = 'hoink.test_guide.done';

/// Guia de testes: roteiro para conferir cada funcionalidade com os dados de demonstração.
class TestGuideScreen extends ConsumerStatefulWidget {
  const TestGuideScreen({super.key});
  @override
  ConsumerState<TestGuideScreen> createState() => _TestGuideScreenState();
}

class _TestGuideScreenState extends ConsumerState<TestGuideScreen> {
  Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((p) => setState(() => _done = (p.getStringList(_prefsKey) ?? const []).toSet()))
        .catchError((_) {});
  }

  void _toggle(String id) {
    setState(() => _done.contains(id) ? _done.remove(id) : _done.add(id));
    SharedPreferences.getInstance().then((p) => p.setStringList(_prefsKey, _done.toList())).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final total = _groups.fold<int>(0, (s, g) => s + g.items.length);
    final done = _done.length.clamp(0, total);
    return ModulePage(
      title: 'Guia de testes',
      subtitle: 'Um roteiro para conferir cada parte da hoink. Toque em "Abrir" para ir direto à tela e marque o que já testou.',
      children: [
        HoinkCard(
          color: HoinkColors.surfaceLow,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$done de $total testados', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
              const SizedBox(height: 8),
              ProgressRail(value: total == 0 ? 0 : done / total, height: 8),
              const SizedBox(height: 10),
              Text(
                'Os resultados esperados usam os dados de demonstração (login miguel@hoink.dev / hoink1234). '
                'Com a sua própria conta, os valores serão outros.',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final g in _groups) ...[
          Row(
            children: [
              Icon(g.icon, color: HoinkColors.pine, size: 20),
              const SizedBox(width: 8),
              Text(g.title, style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in g.items) ...[
            _CheckCard(check: c, done: _done.contains(c.id), onToggle: () => _toggle(c.id)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check, required this.done, required this.onToggle});
  final _Check check;
  final bool done;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => HoinkCard(
    padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(key: Key('guide-${check.id}'), value: done, onChanged: (_) => onToggle()),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                check.title,
                style: HoinkText.labelMd.copyWith(decoration: done ? TextDecoration.lineThrough : null),
              ),
              const SizedBox(height: 4),
              for (final (i, s) in check.steps.indexed) Text('${i + 1}. $s', style: HoinkText.bodySm),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Symbols.check_circle, size: 16, color: HoinkColors.surfaceTint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Esperado: ${check.expected}',
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.surfaceTint),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: () => context.push(check.route), child: const Text('Abrir')),
      ],
    ),
  );
}
