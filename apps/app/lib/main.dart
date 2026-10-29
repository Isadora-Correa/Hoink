import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'state/providers.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // URLs limpas no Web (/lancamentos em vez de /#/lancamentos), permitindo deep links.
  usePathUrlStrategy();
  // Expõe a árvore de acessibilidade no Web (leitores de tela e testes E2E por papel/rótulo).
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  await initializeDateFormatting('pt_BR');
  runApp(const ProviderScope(child: HoinkApp()));
}

class HoinkApp extends ConsumerWidget {
  const HoinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Olhinho: valores em texto comum (formatBRL) não observam o provider; redesenha a árvore inteira
    // preservando o estado (formulários, navegação), para que nenhum valor fique visível.
    ref.listen(hideValuesProvider, (_, _) {
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
    return MaterialApp.router(
      title: 'hoink.',
      debugShowCheckedModeBanner: false,
      theme: buildHoinkTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
