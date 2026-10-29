import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Ícones de categoria armazenados pelo nome do Material Symbols (o mesmo usado nos protótipos).
const _byName = <String, IconData>{
  'restaurant': Symbols.restaurant,
  'shopping_cart': Symbols.shopping_cart,
  'home': Symbols.home,
  'directions_car': Symbols.directions_car,
  'medical_services': Symbols.medical_services,
  'sports_esports': Symbols.sports_esports,
  'school': Symbols.school,
  'bolt': Symbols.bolt,
  'subscriptions': Symbols.subscriptions,
  'more_horiz': Symbols.more_horiz,
  'payments': Symbols.payments,
  'trending_up': Symbols.trending_up,
  'work': Symbols.work,
  'add_circle': Symbols.add_circle,
  'inventory_2': Symbols.inventory_2,
  'account_balance': Symbols.account_balance,
  'badge': Symbols.badge,
  'computer': Symbols.computer,
  'campaign': Symbols.campaign,
  'business_center': Symbols.business_center,
  'receipt': Symbols.receipt,
  'credit_score': Symbols.credit_score,
  'design_services': Symbols.design_services,
  'storefront': Symbols.storefront,
  'savings': Symbols.savings,
  'category': Symbols.category,
  'pets': Symbols.pets,
  'flight': Symbols.flight,
  'checkroom': Symbols.checkroom,
  'fitness_center': Symbols.fitness_center,
  'redeem': Symbols.redeem,
};

IconData categoryIcon(String? name) => _byName[name] ?? Symbols.category;
List<String> get categoryIconNames => _byName.keys.toList();

IconData transactionIcon(String type, String? categoryIconName) {
  switch (type) {
    case 'TRANSFER':
      return Symbols.sync_alt;
    case 'CONTRIBUTION':
    case 'REDEMPTION':
      return Symbols.savings;
    case 'ADJUSTMENT':
      return Symbols.tune;
    case 'REFUND':
      return Symbols.undo;
    case 'WITHDRAWAL':
      return Symbols.output;
    default:
      return categoryIconName != null
          ? categoryIcon(categoryIconName)
          : (type == 'INCOME' ? Symbols.payments : Symbols.receipt_long);
  }
}
