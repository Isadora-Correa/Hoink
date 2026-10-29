import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hoink/core/token_storage.dart';
import 'package:hoink/data/repository.dart';
import 'package:hoink/main.dart';
import 'package:hoink/state/providers.dart';
import 'package:hoink/ui/widgets/hoink_logo.dart';
import 'package:hoink/ui/widgets/scope_switcher.dart';

import 'fakes.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeRepository repo,
  String? token,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo as HoinkRepository),
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage(token) as TokenStorage),
      ],
      child: const HoinkApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('logo é desenhada a partir do vetor oficial', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: HoinkLogo(height: 48))));
    final size = tester.getSize(find.byType(HoinkLogo));
    expect(size.height, 48);
    expect(size.width, greaterThan(size.height * 2.5));
    expect(find.bySemanticsLabel('hoink.'), findsOneWidget);
  });

  testWidgets('sem sessão, abre o login e valida o formulário', (tester) async {
    await pumpApp(tester, repo: FakeRepository());
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Informe seu e-mail'), findsOneWidget);
    expect(find.text('Informe a senha'), findsOneWidget);
  });

  testWidgets('erro de credenciais é exibido', (tester) async {
    final repo = FakeRepository()..loginError = 'E-mail ou senha incorretos';
    await pumpApp(tester, repo: repo);
    await tester.enterText(find.byKey(const Key('login-email')), 'miguel@hoink.dev');
    await tester.enterText(find.byType(TextFormField).at(1), 'errada123');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos'), findsOneWidget);
  });

  testWidgets('login leva ao dashboard desktop com dados do backend', (tester) async {
    await pumpApp(tester, repo: FakeRepository());
    await tester.enterText(find.byKey(const Key('login-email')), 'miguel@hoink.dev');
    await tester.enterText(find.byType(TextFormField).at(1), 'hoink1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Miguel!'), findsOneWidget);
    expect(find.text('Minhas Contas'), findsOneWidget); // barra lateral
    expect(find.text('Evolução do seu dinheiro'), findsOneWidget);
    expect(find.text('Supermercado Pão de Açúcar'), findsOneWidget);
    expect(find.textContaining('12.480,00', findRichText: true), findsWidgets);
  });

  testWidgets('layout mobile usa barra inferior e botão Novo', (tester) async {
    await pumpApp(tester, repo: FakeRepository(), token: 'token-123456789012345678901', size: const Size(400, 900));
    expect(find.text('Olá, Miguel!'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Novo'), findsOneWidget);
  });

  testWidgets('cria despesa pelo formulário enviando centavos ao backend', (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    await tester.tap(find.text('Novo Lançamento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '350,00');
    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição da despesa'), 'Supermercado');
    await tester.tap(find.text('Mercado').last);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Nubank Ultravioleta').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    expect(repo.created, hasLength(1));
    expect(repo.created.single, containsPair('amountCents', 35000));
    expect(repo.created.single, containsPair('categoryId', 'c1'));
    expect(repo.created.single, containsPair('type', 'EXPENSE'));
    expect(repo.created.single, containsPair('status', 'SETTLED'));
  });

  testWidgets('sem conta profissional, o seletor Pessoal/Pro/Total não aparece', (tester) async {
    final repo = FakeRepository()..withBusiness = false;
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    expect(find.byType(ScopeSwitcher), findsWidgets);
    expect(find.descendant(of: find.byType(ScopeSwitcher), matching: find.text('Pro')), findsNothing);
    expect(find.descendant(of: find.byType(ScopeSwitcher), matching: find.text('Total')), findsNothing);
  });

  testWidgets('com conta profissional, o seletor aparece', (tester) async {
    await pumpApp(tester, repo: FakeRepository(), token: 'token-123456789012345678901');
    expect(find.descendant(of: find.byType(ScopeSwitcher), matching: find.text('Pro')), findsOneWidget);
    expect(find.descendant(of: find.byType(ScopeSwitcher), matching: find.text('Total')), findsOneWidget);
  });

  testWidgets('configurações oferecem foto de perfil e conta profissional', (tester) async {
    await pumpApp(tester, repo: FakeRepository(), token: 'token-123456789012345678901');
    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pick-avatar')), findsOneWidget);
    expect(find.text('Adicionar foto'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.byKey(const Key('business-toggle')));
    expect(toggle.value, isTrue);
  });

  testWidgets('cria conta recorrente mensal de valor variável pelo formulário', (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    await tester.tap(find.text('Novo Lançamento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '250,00');
    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição da despesa'), 'Conta de energia');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Nubank Ultravioleta').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('recurring-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recurring-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Variável'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    expect(repo.created, isEmpty);
    expect(repo.createdRecurring, hasLength(1));
    expect(repo.createdRecurring.single, containsPair('amountCents', 25000));
    expect(repo.createdRecurring.single, containsPair('frequency', 'MONTHLY'));
    expect(repo.createdRecurring.single, containsPair('amountKind', 'VARIABLE'));
    expect(repo.createdRecurring.single, containsPair('type', 'EXPENSE'));
  });

  testWidgets('tela de recorrências mostra estado vazio com ação de criar', (tester) async {
    await pumpApp(tester, repo: FakeRepository(), token: 'token-123456789012345678901');
    await tester.tap(find.text('Recorrências'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma recorrência'), findsWidgets);
    expect(find.byKey(const Key('new-recurring')), findsOneWidget);
  });

  testWidgets('cadastra cliente com CPF/CNPJ validado no app', (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    await tester.tap(find.text('Clientes e Fornecedores'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum cliente'), findsWidgets);
    await tester.tap(find.byKey(const Key('new-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('contact-name')), 'Studio Alpha');
    await tester.enterText(find.widgetWithText(TextFormField, 'CPF ou CNPJ (opcional)'), '123');
    await tester.tap(find.byKey(const Key('save-contact')));
    await tester.pumpAndSettle();
    expect(find.text('CPF (11) ou CNPJ (14 dígitos)'), findsOneWidget);
    expect(repo.savedContacts, isEmpty);
    await tester.enterText(find.widgetWithText(TextFormField, 'CPF ou CNPJ (opcional)'), '12.345.678/0001-90');
    await tester.tap(find.byKey(const Key('save-contact')));
    await tester.pumpAndSettle();
    expect(repo.savedContacts.single, containsPair('name', 'Studio Alpha'));
    expect(repo.savedContacts.single, containsPair('kind', 'CLIENT'));
  });

  testWidgets('contas a pagar e receber mostram totais e itens em aberto', (tester) async {
    await pumpApp(tester, repo: FakeRepository(), token: 'token-123456789012345678901');
    await tester.tap(find.text('Pagar e Receber'));
    await tester.pumpAndSettle();
    expect(find.text('Contas a pagar e receber'), findsOneWidget);
    expect(find.text('Supermercado Pão de Açúcar'), findsOneWidget);
    expect(find.textContaining('350,00', findRichText: true), findsWidgets);
  });

  testWidgets('cartões: mostra limite e fatura, e registra compra parcelada', (tester) async {
    final repo = FakeRepository()..cardList = [fakeCard()];
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    await tester.tap(find.text('Cartões'));
    await tester.pumpAndSettle();
    expect(find.text('Nubank Roxinho'), findsOneWidget);
    expect(find.textContaining('Usado R\$'), findsOneWidget);
    expect(find.textContaining('A pagar:'), findsOneWidget);

    await tester.tap(find.text('Nubank Roxinho'));
    await tester.pumpAndSettle();
    expect(find.text('Notebook (2/10)'), findsOneWidget);
    expect(find.textContaining('Parcela 2/10'), findsOneWidget);
    expect(find.byKey(const Key('pay-invoice')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-purchase')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('purchase-description')), 'Geladeira');
    await tester.enterText(find.byKey(const Key('purchase-total')), '3.600,00');
    await tester.tap(find.byKey(const Key('purchase-installments')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12x').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-purchase')));
    await tester.pumpAndSettle();
    expect(repo.purchases.single, containsPair('totalCents', 360000));
    expect(repo.purchases.single, containsPair('installments', 12));
  });

  testWidgets('dívidas: simula o cronograma pela API antes de cadastrar', (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    await tester.tap(find.text('Dívidas'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma dívida cadastrada'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-debt')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('debt-principal')), '10.000,00');
    await tester.enterText(find.byKey(const Key('debt-rate')), '1,5');
    await tester.enterText(find.byKey(const Key('debt-count')), '12');
    await tester.ensureVisible(find.byKey(const Key('simulate-debt')));
    await tester.tap(find.byKey(const Key('simulate-debt')));
    await tester.pumpAndSettle();
    expect(repo.simulated.single, containsPair('principalCents', 1000000));
    expect(repo.simulated.single, containsPair('monthlyRatePpm', 15000));
    expect(find.text('Simulação'), findsOneWidget);
    expect(find.text('R\$ 888,49'), findsWidgets);
  });

  testWidgets('planejamento: projeção 30/60/90, orçamento com alerta e reserva', (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo: repo, token: 'token-123456789012345678901');
    await tester.tap(find.text('Planejamento'));
    await tester.pumpAndSettle();
    expect(find.text('Fluxo de caixa projetado'), findsOneWidget);
    expect(find.text('Próximos 30 dias'), findsOneWidget);
    await tester.tap(find.text('90 dias'));
    await tester.pumpAndSettle();
    expect(find.text('Próximos 90 dias'), findsOneWidget);
    expect(find.text('Mercado: 85% do orçamento usado'), findsOneWidget);
    expect(find.text('Reserva de emergência'), findsOneWidget);
    expect(find.textContaining('Faltam R\$'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('new-budget')));
    await tester.tap(find.byKey(const Key('new-budget')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-limit')), '800');
    await tester.tap(find.byKey(const Key('save-budget')));
    await tester.pumpAndSettle();
    expect(repo.budgetsSaved.single, ('c1', 80000, 8000));
  });
}
