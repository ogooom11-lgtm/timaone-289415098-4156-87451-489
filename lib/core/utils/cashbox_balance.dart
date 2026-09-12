import '../storage/app_database.dart';
import 'currency_denoms.dart';

/// ملخص رصيد عملة واحدة في الصندوق.
class CurrencyCashSummary {
  final Currency currency;
  double currentTotal = 0;
  double afterDeliveryTotal = 0;
  final Map<String, double> byTypeCurrent = {};
  final Map<String, double> byTypeAfter = {};

  CurrencyCashSummary({required this.currency});

  String get displayName => CurrencyDenoms.displayName(currency);

  double pendingDeliveryImpact(int currencyId) {
    // الفرق بين بعد التسليم والحالي = أثر المعلقة على هذه العملة
    return afterDeliveryTotal - currentTotal;
  }
}

class CashboxBalanceCalculator {
  CashboxBalanceCalculator._();

  static Future<Map<int, CurrencyCashSummary>> calculate(
    AppDatabase db, {
    String boxType = 'كامل', // كامل | حركات | صرف
  }) async {
    final currencies = await db.getAllCurrencies();
    final transactions = await db.getAllTransactions();

    final summaries = <int, CurrencyCashSummary>{
      for (final c in currencies) c.id: CurrencyCashSummary(currency: c),
    };

    void apply({
      required bool afterDeliveryMode,
      required int? currencyId,
      required double value,
      required String source,
    }) {
      if (currencyId == null) return;
      final s = summaries[currencyId];
      if (s == null) return;
      if (afterDeliveryMode) {
        s.afterDeliveryTotal += value;
        s.byTypeAfter[source] = (s.byTypeAfter[source] ?? 0) + value;
      } else {
        s.currentTotal += value;
        s.byTypeCurrent[source] = (s.byTypeCurrent[source] ?? 0) + value;
      }
    }

    void processTx(Transaction transaction, {required bool afterDeliveryMode}) {
      if (transaction.movementState == 'ملغية' ||
          transaction.status == 'الغاء' ||
          transaction.status == 'ملغية') {
        return;
      }

      final type = transaction.type;
      final isExchange = type == 'حركة تسوية' || type.contains('صرف');

      if (boxType == 'حركات' && isExchange) return;
      if (boxType == 'صرف' && !isExchange) return;

      // 1. حركة تسليم
      if (type == 'حركة تسليم' || type.contains('تسليم')) {
        final include = transaction.status == 'تم التسليم' || afterDeliveryMode;
        if (include) {
          apply(
            afterDeliveryMode: afterDeliveryMode,
            currencyId: transaction.currencyId,
            value: -transaction.amount,
            source: 'تسليم (-)',
          );
          if (transaction.targetCurrencyId != null &&
              transaction.targetAmount != null) {
            apply(
              afterDeliveryMode: afterDeliveryMode,
              currencyId: transaction.targetCurrencyId,
              value: -transaction.targetAmount!,
              source: 'تسليم فرعي (-)',
            );
          }
        }
      }
      // 2. حركة استلام
      else if (type == 'حركة استلام' || type.contains('استلام')) {
        apply(
          afterDeliveryMode: afterDeliveryMode,
          currencyId: transaction.currencyId,
          value: transaction.amount,
          source: 'استلام (+)',
        );
        if (transaction.targetCurrencyId != null &&
            transaction.targetAmount != null) {
          apply(
            afterDeliveryMode: afterDeliveryMode,
            currencyId: transaction.targetCurrencyId,
            value: transaction.targetAmount!,
            source: 'استلام فرعي (+)',
          );
        }
      }
      // 3. حركة مرسلة — المستلم والأجور فقط يدخلان الصندوق.
      //    المبلغ المرسل لا يؤثّر على الأرصدة (يُسوَّى بين المكاتب).
      else if (type == 'حركة مرسلة' || type.contains('مرسلة')) {
        apply(
          afterDeliveryMode: afterDeliveryMode,
          currencyId: transaction.currencyId,
          value: transaction.amount,
          source: 'مرسلة مستلم (+)',
        );
        if (transaction.feesCurrencyId != null && transaction.fees != null) {
          apply(
            afterDeliveryMode: afterDeliveryMode,
            currencyId: transaction.feesCurrencyId,
            value: transaction.fees!,
            source: 'أجور الحوالة (+)',
          );
        }
      }
      // 4. حركة تسوية (صرف)
      else if (type == 'حركة تسوية' || type.contains('صرف')) {
        apply(
          afterDeliveryMode: afterDeliveryMode,
          currencyId: transaction.currencyId,
          value: -transaction.amount,
          source: 'تسوية مخرج (-)',
        );
        if (transaction.targetCurrencyId != null &&
            transaction.targetAmount != null) {
          apply(
            afterDeliveryMode: afterDeliveryMode,
            currencyId: transaction.targetCurrencyId,
            value: transaction.targetAmount!,
            source: 'تسوية مدخل (+)',
          );
        }
      }
      // 5. حركة يوزر
      else if (type == 'حركة يوزر' || type.contains('يوزر')) {
        apply(
          afterDeliveryMode: afterDeliveryMode,
          currencyId: transaction.currencyId,
          value: -transaction.amount,
          source: 'حركة يوزر (-)',
        );
        if (transaction.targetCurrencyId != null &&
            transaction.targetAmount != null) {
          apply(
            afterDeliveryMode: afterDeliveryMode,
            currencyId: transaction.targetCurrencyId,
            value: -transaction.targetAmount!,
            source: 'يوزر فرعي (-)',
          );
        }
      }
    }

    for (final tx in transactions) {
      processTx(tx, afterDeliveryMode: false);
      processTx(tx, afterDeliveryMode: true);
    }

    return summaries;
  }

  static Future<List<Transaction>> pendingDeliveriesForCurrency(
    AppDatabase db,
    int currencyId,
  ) async {
    final all = await db.getAllTransactions();
    return all.where((t) {
      final isDelivery = t.type == 'حركة تسليم' || t.type.contains('تسليم');
      final pending = t.status == 'مضافة' && t.movementState == 'مفعلة';
      if (!isDelivery || !pending) return false;
      return t.currencyId == currencyId || t.targetCurrencyId == currencyId;
    }).toList();
  }

  /// إحصائيات يومية + معلقة لعملة واحدة.
  static Future<CurrencyDayStats> dayStatsForCurrency(
    AppDatabase db,
    int currencyId, {
    DateTime? day,
  }) async {
    final all = await db.getAllTransactions();
    final target = day ?? DateTime.now();
    final stats = CurrencyDayStats();

    double amountOnCurrency(Transaction t) {
      if (t.currencyId == currencyId) return t.amount;
      if (t.targetCurrencyId == currencyId) return t.targetAmount ?? 0;
      if (t.feesCurrencyId == currencyId) return t.fees ?? 0;
      return 0;
    }

    bool touchesCurrency(Transaction t) {
      return t.currencyId == currencyId ||
          t.targetCurrencyId == currencyId ||
          t.feesCurrencyId == currencyId;
    }

    bool isSameDay(DateTime d) {
      final local = d.toLocal();
      return local.year == target.year &&
          local.month == target.month &&
          local.day == target.day;
    }

    bool isCancelled(Transaction t) {
      return t.movementState == 'ملغية' ||
          t.status == 'الغاء' ||
          t.status == 'ملغية';
    }

    bool isDeliveryType(String type) =>
        type == 'حركة تسليم' ||
        (type.contains('تسليم') && !type.contains('يوزر'));

    bool isUserType(String type) =>
        type == 'حركة يوزر' || type.contains('يوزر');

    bool isReceiveType(String type) =>
        type == 'حركة استلام' || type.contains('استلام');

    bool isSentType(String type) =>
        type == 'حركة مرسلة' || type.contains('مرسلة');

    bool isExchangeType(String type) =>
        type == 'حركة تسوية' || type.contains('صرف') || type.contains('تسوية');

    for (final t in all) {
      if (!touchesCurrency(t)) continue;
      final amount = amountOnCurrency(t).abs();
      final type = t.type;

      // المعلقة (كل الأوقات) — تسليم مضاف ومفعّل
      if (isDeliveryType(type) &&
          t.status == 'مضافة' &&
          t.movementState == 'مفعلة') {
        stats.pendingCount += 1;
        stats.pendingAmount += amount;
      }

      // إحصائيات اليوم فقط
      if (!isSameDay(t.createdAt)) continue;

      stats.addedTodayCount += 1;
      stats.addedTodayAmount += amount;

      if (isCancelled(t)) {
        stats.cancelledCount += 1;
        stats.cancelledAmount += amount;
        continue;
      }

      if (isDeliveryType(type)) {
        stats.deliveryCount += 1;
        stats.deliveryAmount += amount;
        if (t.status == 'تم التسليم') {
          stats.deliveredDoneCount += 1;
          stats.deliveredDoneAmount += amount;
        }
      } else if (isUserType(type)) {
        // حركة يوزر = تسليم مكتمل فوراً
        stats.deliveryCount += 1;
        stats.deliveryAmount += amount;
        stats.deliveredDoneCount += 1;
        stats.deliveredDoneAmount += amount;
      } else if (isReceiveType(type)) {
        stats.receiveCount += 1;
        stats.receiveAmount += amount;
      } else if (isSentType(type)) {
        stats.sentCount += 1;
        stats.sentAmount += amount;
      } else if (isExchangeType(type)) {
        stats.exchangeCount += 1;
        stats.exchangeAmount += amount;
      }
    }

    return stats;
  }
}

/// إحصائيات يوم واحد + المعلقة لعملة.
class CurrencyDayStats {
  int addedTodayCount = 0;
  double addedTodayAmount = 0;

  int deliveryCount = 0;
  double deliveryAmount = 0;

  int receiveCount = 0;
  double receiveAmount = 0;

  int sentCount = 0;
  double sentAmount = 0;

  int exchangeCount = 0;
  double exchangeAmount = 0;

  int deliveredDoneCount = 0;
  double deliveredDoneAmount = 0;

  int cancelledCount = 0;
  double cancelledAmount = 0;

  int pendingCount = 0;
  double pendingAmount = 0;
}
