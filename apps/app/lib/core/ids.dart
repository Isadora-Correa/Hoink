import 'dart:math';

final _rand = Random.secure();

/// Chave de idempotência para operações que movimentam dinheiro (evita lançamentos duplicados em reenvios).
String newIdempotencyKey() => List.generate(24, (_) => _rand.nextInt(16).toRadixString(16)).join();
