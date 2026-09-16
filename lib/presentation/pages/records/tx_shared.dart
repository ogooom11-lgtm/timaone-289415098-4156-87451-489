import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/printing/delivery_receipt.dart';
import '../../../core/services/app_sound.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/denom_validator_dialog.dart';
import '../../widgets/receipt_print_dialog.dart';
import '../transactions/add_delivery_page.dart';
import '../transactions/add_exchange_page.dart';
import '../transactions/add_receive_page.dart';
import '../transactions/add_sent_page.dart';

/// أنواع الحركات المعتمدة في السجل.
enum TxKind { delivery, user, receive, sent, exchange }

TxKind kindOfTx(String type) {
  if (type == 'حركة يوزر') return TxKind.user;
  if (type.contains('تسليم')) return TxKind.delivery;
  if (type.contains('استلام')) return TxKind.receive;
  if (type.contains('مرسلة')) return TxKind.sent;
  return TxKind.exchange;
}

/// هل الحركة ملغية؟
bool txCanceled(Transaction tx) =>
    tx.movementState == 'ملغية' || tx.status == 'الغاء';

IconData iconOfTx(TxKind kind) => switch (kind) {
  TxKind.delivery => Icons.outbox_rounded,
  TxKind.user => Icons.person_rounded,
  TxKind.receive => Icons.move_to_inbox_rounded,
  TxKind.sent => Icons.send_rounded,
  TxKind.exchange => Icons.currency_exchange_rounded,
};

Color colorOfTx(TxKind kind) => switch (kind) {
  TxKind.delivery => AppColors.warning,
  TxKind.user => AppColors.violet,
  TxKind.receive => AppColors.success,
  TxKind.sent => AppColors.ocean,
  TxKind.exchange => AppColors.brandGoldDark,
};

/// سياسة الإجراءات المسموحة لكل حركة.
///
/// - تسليم: إلغاء / تعديل / تسليم (إن كانت معلقة)
/// - يوزر: إلغاء / تعديل / تسليم (إن كانت الحالة ملغية)
/// - استلام ومرسلة: تعديل / إلغاء
/// - ومع كل نوع: تراجع عن الإلغاء، وطباعة إيصال في أي وقت.
class TxPolicy {
  final bool canDeliver;
  final bool canEdit;
  final bool canCancel;
  final bool canRevertCancel;
  final bool canRevertDelivery;
  final bool canPrint;
  final String hint;

  const TxPolicy({
    required this.canDeliver,
    required this.canEdit,
    required this.canCancel,
    required this.canRevertCancel,
    required this.canRevertDelivery,
    required this.canPrint,
    required this.hint,
  });
}

TxPolicy policyOfTx(Transaction tx) {
  final canceled = txCanceled(tx);
  final pending = !canceled && tx.status == 'مضافة';
  final delivered = !canceled && tx.status == 'تم التسليم';

  return switch (kindOfTx(tx.type)) {
    TxKind.delivery => TxPolicy(
      canDeliver: pending,
      canEdit: true,
      // الحركة المُسلَّمة لا تُلغى مباشرة — يجب «تراجع عن التسليم» أولاً
      // (لتعود فئاتها للصندوق) ثم إلغاؤها وهي معلقة.
      canCancel: pending,
      canRevertCancel: canceled,
      canRevertDelivery: delivered,
      canPrint: true,
      hint: delivered
          ? 'حركة تسليم مُسلَّمة: تراجع عن التسليم أولاً ثم ألغِها'
          : 'حركة تسليم: تُسلَّم أو تُعدَّل أو تُلغى، والتراجع متاح دائماً',
    ),
    TxKind.user => TxPolicy(
      canDeliver: canceled,
      canEdit: true,
      canCancel: !canceled,
      canRevertCancel: canceled,
      canRevertDelivery: false,
      canPrint: true,
      hint: canceled
          ? 'حركة يوزر ملغية: يمكن تسليمها أو تعديلها أو التراجع عن الإلغاء'
          : 'حركة يوزر: تُلغى أو تُعدَّل، وتُسلَّم بعد الإلغاء',
    ),
    TxKind.receive => TxPolicy(
      canDeliver: false,
      canEdit: true,
      canCancel: !canceled,
      canRevertCancel: canceled,
      canRevertDelivery: false,
      canPrint: true,
      hint: 'حركة استلام: تُعدَّل أو تُلغى، مع إمكانية التراجع',
    ),
    TxKind.sent => TxPolicy(
      canDeliver: false,
      canEdit: true,
      canCancel: !canceled,
      canRevertCancel: canceled,
      canRevertDelivery: false,
      canPrint: true,
      hint: 'حركة مرسلة: تُعدَّل أو تُلغى، مع إمكانية التراجع',
    ),
    TxKind.exchange => TxPolicy(
      canDeliver: false,
      canEdit: true,
      canCancel: !canceled,
      canRevertCancel: canceled,
      canRevertDelivery: false,
      canPrint: true,
      hint: 'حركة تسوية/صرف: تُعدَّل أو تُلغى',
    ),
  };
}

/// منطق إجراءات الحركات (تسليم/إلغاء/تراجع/تعديل/طباعة) مشترك بين
/// صفحة سجل الحركات ونتائج البحث في الصفحة الرئيسية — نفس المنطق حرفياً
/// في مكان واحد حتى لا يتفرّع.
mixin TxActions on State<StatefulWidget> {
  AppDatabase get txDb;
  User get txUser;
  Map<int, Currency> get txCurrencies;
  Future<void> refreshTxData();

  int? _busyTxId;
  int? get busyTxId => _busyTxId;

  // -------------------------------------------------------------------
  // تنسيقات مساعدة
  // -------------------------------------------------------------------

  String formatTxDate(DateTime date) =>
      DateFormat('yyyy-MM-dd  HH:mm').format(date.toLocal());

  String txCurrencyCode(int? id) {
    if (id == null) return '-';
    return txCurrencies[id]?.code ?? id.toString();
  }

  String txCurrencyName(int? id) {
    if (id == null) return '-';
    final currency = txCurrencies[id];
    return currency == null
        ? id.toString()
        : CurrencyDenoms.displayName(currency);
  }

  String formatTxAmount(double value) =>
      NumberFormat('#,##0.##', 'en').format(value);

  void txToast(String message, Color color, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          action: action,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // -------------------------------------------------------------------
  // الإجراءات
  // -------------------------------------------------------------------

  Future<bool> _confirmCancel(Transaction transaction) async {
    final amount =
        '${formatTxAmount(transaction.amount)} ${txCurrencyCode(transaction.currencyId)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDims.radiusLg),
            side: BorderSide(color: AppUi.border(ctx)),
          ),
          title: Row(
            children: [
              Icon(
                Icons.report_gmailerrorred_rounded,
                color: AppUi.tone(ctx, AppColors.error),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('إلغاء الحركة؟')),
            ],
          ),
          content: Text(
            'ستتحول حركة «${transaction.beneficiary?.isNotEmpty == true ? transaction.beneficiary : transaction.type}» '
            'بمبلغ $amount إلى حالة ملغية. يمكن التراجع عن الإلغاء في أي وقت.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('عودة'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.cancel_rounded, size: 18),
              label: const Text('نعم، إلغاء الحركة'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _withBusy(int id, Future<void> Function() action) async {
    setState(() => _busyTxId = id);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyTxId = null);
    }
  }

  /// يلخّص الفئات المتأثّرة لكل عملة (الأولى والثانية) لرسائل التأكيد.
  String _denomsSummary(Map<int, OldStockEffect> effects) {
    final parts = <String>[
      for (final e in effects.entries)
        if (txCurrencies[e.key] != null && e.value.counts.isNotEmpty)
          '${txCurrencies[e.key]!.code}: ${CurrencyDenoms.formatCounts(e.value.counts)}',
    ];
    return parts.isEmpty ? '' : ' — الفئات: ${parts.join(' | ')}';
  }

  Future<void> cancelTx(Transaction transaction) async {
    if (!await _confirmCancel(transaction)) return;
    final reversed = CurrencyDenoms.oldStockEffects(
      transaction,
      txCurrencies,
    );
    await _withBusy(transaction.id, () async {
      // عكس أثر فئات الحركة على الصندوق: يحذف ما أُضيف / يُرجع ما خُصم.
      // الحركة المعلقة (تسليم غير مُسلَّم) لا فئات لها فأثرها معدوم.
      await CurrencyDenoms.reverseOldStock(transaction, txCurrencies);
      await txDb.updateTransaction(
        transaction.id,
        const TransactionsCompanion(
          movementState: drift.Value('ملغية'),
          // تبقى الحالة الأصلية دون تجاوز لتُستعاد كما كانت عند التراجع.
        ),
      );
      await txDb.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'وضع الحركة',
          oldValue: transaction.movementState,
          newValue: 'ملغية',
          editedBy: drift.Value(txUser.username),
        ),
      );
      await refreshTxData();
    });
    AppSound.play(TimaSound.error);
    txToast(
      'تم إلغاء الحركة${_denomsSummary(reversed)} — يمكنك التراجع الآن',
      AppColors.error,
      action: SnackBarAction(
        label: 'تراجع',
        textColor: Colors.white,
        onPressed: () => revertCancellation(transaction),
      ),
    );
  }

  /// يُرجع الحالة المناسبة بعد التراجع عن الإلغاء: يبقيها إن كانت محفوظة
  /// (إلغاء جديد)، أو يستعيدها حسب نوع الحركة إن كانت «الغاء» (إلغاء قديم).
  String _statusAfterRevert(Transaction tx) {
    final s = tx.status;
    if (s != 'الغاء' && s != 'ملغية') return s;
    final kind = kindOfTx(tx.type);
    if (kind == TxKind.user) return 'تم التسليم';
    if (kind == TxKind.delivery) {
      final wasDelivered =
          CurrencyDenoms.extractDeliveredDenomsNote(tx.note) != null;
      return wasDelivered ? 'تم التسليم' : 'مضافة';
    }
    return 'مضافة';
  }

  /// يزيل كل طوابع الفئات/التسليم من ملاحظة، ويبقي نص المستخدم فقط.
  String _stripDenomStamps(String note) {
    return note
        .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[الفئات المسلمة لـ [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[الفئات المستلمة للحوالة لـ [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[الفئات المستلمة لـ [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات الأجور لـ [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم لـ [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المستلم لـ [^\]]+\]'), '')
        .trim();
  }

  /// هل فئات الحركة المحفوظة في الملاحظة لم تعد تطابق مبلغها الحالي؟
  /// (يحدث حين تُعدَّل الحركة وهي ملغية فيتغيّر المبلغ وتبقى الفئات القديمة.)
  bool _denomsStale(Transaction tx, Map<int, OldStockEffect> effects) {
    final main = effects[tx.currencyId];
    if (main != null &&
        (CurrencyDenoms.sumCounts(main.counts) - tx.amount).abs() > 0.01) {
      return true;
    }
    if (tx.targetAmount != null && tx.targetCurrencyId != null) {
      final t = effects[tx.targetCurrencyId!];
      if (t != null &&
          (CurrencyDenoms.sumCounts(t.counts) - tx.targetAmount!).abs() >
              0.01) {
        return true;
      }
    }
    return false;
  }

  /// يطلب فئات جديدة مطابقة للمبلغ الحالي عند التراجع عن إلغاء حركة عُدِّلت
  /// وهي ملغية، ويطبّقها على الصندوق، ويعيد الملاحظة الجديدة. `null` = تراجع.
  Future<String?> _askFreshDenomsForRevert(Transaction transaction) async {
    final kind = kindOfTx(transaction.type);
    final currency1 = txCurrencies[transaction.currencyId];
    if (currency1 == null) return null;
    final old = CurrencyDenoms.oldStockEffects(transaction, txCurrencies);
    final mainInflow = old[transaction.currencyId]?.isInflow ?? true;

    final stock1 = mainInflow
        ? null
        : await CurrencyDenoms.loadStock(currency1);
    if (!mounted) return null;
    final counts1 = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: transaction.amount,
        currency: currency1,
        title: 'إدخال الفئات من جديد (${currency1.code})',
        mode: mainInflow ? DenomDialogMode.inflow : DenomDialogMode.outflow,
        availableStock: stock1,
      ),
    );
    if (counts1 == null) return null;

    Map<double, int>? counts2;
    Currency? currency2;
    var secondInflow = true;
    if (transaction.targetAmount != null &&
        transaction.targetAmount! > 0 &&
        transaction.targetCurrencyId != null) {
      currency2 = txCurrencies[transaction.targetCurrencyId!];
      if (currency2 != null) {
        secondInflow = old[currency2.id]?.isInflow ?? true;
        final stock2 = secondInflow
            ? null
            : await CurrencyDenoms.loadStock(currency2);
        if (!mounted) return null;
        counts2 = await showDialog<Map<double, int>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => DenomValidatorDialog(
            targetAmount: transaction.targetAmount!,
            currency: currency2!,
            title: 'إدخال فئات المبلغ الثاني من جديد (${currency2.code})',
            mode: secondInflow
                ? DenomDialogMode.inflow
                : DenomDialogMode.outflow,
            availableStock: stock2,
          ),
        );
        if (counts2 == null) return null;
      }
    }

    // تطبيق الفئات الجديدة على الصندوق.
    Future<void> apply(Currency c, Map<double, int> counts, bool inflow) async {
      if (counts.isEmpty) return;
      if (inflow) {
        await CurrencyDenoms.addStock(c, counts);
      } else {
        await CurrencyDenoms.deductStock(c, counts);
      }
    }

    await apply(currency1, counts1, mainInflow);
    if (counts2 != null && currency2 != null) {
      await apply(currency2, counts2, secondInflow);
    }

    // بناء الملاحظة الجديدة وفق صيغة كل نوع.
    final userNote = _stripDenomStamps(transaction.note ?? '');
    final base = userNote.isEmpty ? '' : '$userNote\n';
    String fmt(Map<double, int> c) => CurrencyDenoms.formatCounts(c);
    final has2 = counts2 != null && currency2 != null;
    String note;
    switch (kind) {
      case TxKind.receive:
        note = '$base[الفئات المستلمة لـ ${currency1.code}: ${fmt(counts1)}]';
        if (has2) {
          note += '\n[الفئات المستلمة لـ ${currency2.code}: ${fmt(counts2)}]';
        }
      case TxKind.sent:
        note =
            '$base[الفئات المستلمة للحوالة لـ ${currency1.code}: ${fmt(counts1)}]';
      case TxKind.user:
        note = '$base[الفئات المسلمة لـ ${currency1.code}: ${fmt(counts1)}]';
        if (has2) {
          note += '\n[الفئات المسلمة لـ ${currency2.code}: ${fmt(counts2)}]';
        }
      case TxKind.delivery:
        final nowStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        note = '$base[تم التسليم في $nowStr]\n[فئات المسلم: ${fmt(counts1)}]';
        if (has2) {
          note +=
              '\n[فئات المسلم 2: ${fmt(counts2)} (${currency2.code})]';
        }
      case TxKind.exchange:
        note = '$base[فئات المسلم لـ ${currency1.code}: ${fmt(counts1)}]';
        if (has2) {
          note += '\n[فئات المستلم لـ ${currency2.code}: ${fmt(counts2)}]';
        }
    }
    return note;
  }

  Future<void> revertCancellation(Transaction transaction) async {
    final restoredStatus = _statusAfterRevert(transaction);
    final effects = CurrencyDenoms.oldStockEffects(
      transaction,
      txCurrencies,
    );

    // إن عُدِّلت الحركة وهي ملغية (فئاتها لم تعد تطابق مبلغها) نطلب فئات
    // جديدة بدل إعادة القديمة. حركة مرسلة تُترك كما هي (لأجورِها صيغة خاصة).
    final stale =
        kindOfTx(transaction.type) != TxKind.sent &&
        _denomsStale(transaction, effects);
    String? freshNote;
    if (stale) {
      freshNote = await _askFreshDenomsForRevert(transaction);
      if (freshNote == null) return; // تراجع المستخدم
    }

    await _withBusy(transaction.id, () async {
      if (!stale) {
        // إعادة تطبيق أثر فئات الحركة على الصندوق (عكس ما فعله الإلغاء).
        await CurrencyDenoms.reapplyOldStock(transaction, txCurrencies);
      }
      // (إن كانت stale فـ _askFreshDenomsForRevert حدّث مخزون الصندوق مسبقاً.)
      await txDb.updateTransaction(
        transaction.id,
        TransactionsCompanion(
          status: drift.Value(restoredStatus),
          movementState: const drift.Value('مفعلة'),
          note: freshNote != null
              ? drift.Value(freshNote)
              : const drift.Value.absent(),
        ),
      );
      await txDb.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'تراجع عن الإلغاء',
          oldValue: 'الغاء',
          newValue: restoredStatus,
          editedBy: drift.Value(txUser.username),
        ),
      );
      await refreshTxData();
    });
    AppSound.play(TimaSound.success);
    txToast(
      stale
          ? 'تم التراجع عن الإلغاء — أُدخلت فئات الحركة من جديد'
          : 'تم التراجع عن الإلغاء — عادت الحركة${_denomsSummary(effects)}',
      AppColors.ocean,
    );
  }

  Future<void> deliverTx(Transaction transaction) async {
    final currency1 = txCurrencies[transaction.currencyId];
    if (currency1 == null) {
      txToast('عملة الحركة غير معرّفة', AppColors.error);
      return;
    }

    final stock1 = await CurrencyDenoms.loadStock(currency1);
    if (!mounted) return;
    final counts1 = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: transaction.amount,
        currency: currency1,
        title: 'تفصيل فئات المبلغ 1 (${currency1.code})',
        mode: DenomDialogMode.outflow,
        availableStock: stock1,
      ),
    );
    if (counts1 == null) return;

    Map<double, int>? counts2;
    Currency? currency2;
    if (transaction.targetAmount != null &&
        transaction.targetAmount! > 0 &&
        transaction.targetCurrencyId != null) {
      currency2 = txCurrencies[transaction.targetCurrencyId!];
      if (currency2 == null) {
        txToast('عملة المبلغ الثاني غير معرّفة — أضفها من الإعدادات', AppColors.error);
        return;
      }
      final stock2 = await CurrencyDenoms.loadStock(currency2);
      if (!mounted) return;
      counts2 = await showDialog<Map<double, int>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DenomValidatorDialog(
          targetAmount: transaction.targetAmount!,
          currency: currency2!,
          title: 'تفصيل فئات المبلغ 2 (${currency2.code})',
          mode: DenomDialogMode.outflow,
          availableStock: stock2,
        ),
      );
      if (counts2 == null) return;
    }

    final nowStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final denomLines = <String>[
      '[تم التسليم في $nowStr]',
      '[فئات المسلم: ${CurrencyDenoms.formatCounts(counts1)}]',
    ];
    if (counts2 != null && currency2 != null) {
      denomLines.add(
        '[فئات المسلم 2: ${CurrencyDenoms.formatCounts(counts2)} (${currency2.code})]',
      );
    }

    final cleanBase = transaction.note == null
        ? ''
        : transaction.note!
              .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
              .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
              .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
              .trim();
    final newNote = cleanBase.isEmpty
        ? denomLines.join('\n')
        : '$cleanBase\n${denomLines.join('\n')}';

    await _withBusy(transaction.id, () async {
      await txDb.updateTransaction(
        transaction.id,
        TransactionsCompanion(
          status: const drift.Value('تم التسليم'),
          movementState: const drift.Value('مفعلة'),
          note: drift.Value(newNote),
        ),
      );
      await CurrencyDenoms.deductStock(currency1, counts1);
      if (counts2 != null && currency2 != null) {
        await CurrencyDenoms.deductStock(currency2, counts2);
      }
      await txDb.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'تغيير الحالة والتسليم',
          oldValue: transaction.status,
          newValue: 'تم التسليم',
          editedBy: drift.Value(txUser.username),
        ),
      );
      await refreshTxData();
    });

    AppSound.play(TimaSound.success);
    txToast('تم تسليم الحركة وتحديث مخزون الصندوق', AppColors.success);
    if (!mounted) return;

    final receipt = DeliveryReceiptData.fromTransaction(
      tx: transaction.copyWith(
        status: 'تم التسليم',
        note: drift.Value(newNote),
      ),
      currency1: currency1,
      currency2: currency2,
      denoms1: counts1,
      denoms2: counts2,
      createdBy: txUser.username,
      branch: txUser.branch,
      statusOverride: 'تم التسليم',
    );
    await offerReceiptPrintAfterDelivery(context, receipt);
  }

  Future<void> revertDelivery(Transaction transaction) async {
    final currency1 = txCurrencies[transaction.currencyId];
    final restored1 = CurrencyDenoms.parseCounts(
      CurrencyDenoms.extractDeliveredDenomsNote(transaction.note),
    );
    if (currency1 != null && restored1.isNotEmpty) {
      await CurrencyDenoms.addStock(currency1, restored1);
    }

    final restored2 = <double, int>{};
    if (transaction.targetCurrencyId != null) {
      final currency2 = txCurrencies[transaction.targetCurrencyId!];
      restored2.addAll(
        CurrencyDenoms.parseCounts(
          CurrencyDenoms.extractDeliveredDenomsNote2(transaction.note),
        ),
      );
      if (currency2 != null && restored2.isNotEmpty) {
        await CurrencyDenoms.addStock(currency2, restored2);
      }
    }

    final cleanNote = (transaction.note ?? '')
        .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
        .trim();

    await _withBusy(transaction.id, () async {
      await txDb.updateTransaction(
        transaction.id,
        TransactionsCompanion(
          status: const drift.Value('مضافة'),
          movementState: const drift.Value('مفعلة'),
          note: drift.Value(cleanNote),
        ),
      );
      await txDb.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'تراجع عن التسليم',
          oldValue: 'تم التسليم',
          newValue: 'مضافة',
          editedBy: drift.Value(txUser.username),
        ),
      );
      await refreshTxData();
    });

    final parts = <String>[
      if (restored1.isNotEmpty) CurrencyDenoms.formatCounts(restored1),
      if (restored2.isNotEmpty) '2: ${CurrencyDenoms.formatCounts(restored2)}',
    ];
    AppSound.play(TimaSound.alert);
    txToast(
      'تم التراجع عن التسليم${parts.isEmpty ? '' : ' وأُعيدت الفئات: ${parts.join(' | ')}'}',
      AppColors.warning,
    );
  }

  Future<void> editTx(Transaction transaction) async {
    final page = switch (kindOfTx(transaction.type)) {
      TxKind.delivery || TxKind.user => AddDeliveryPage(
        db: txDb,
        user: txUser,
        transaction: transaction,
      ),
      TxKind.receive => AddReceivePage(
        db: txDb,
        user: txUser,
        transaction: transaction,
      ),
      TxKind.sent => AddSentPage(
        db: txDb,
        user: txUser,
        transaction: transaction,
      ),
      TxKind.exchange => AddExchangePage(
        db: txDb,
        user: txUser,
        transaction: transaction,
      ),
    };

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    await refreshTxData();
  }

  /// طباعة إيصال لأي حركة وفي أي وقت.
  Future<void> printTxReceipt(Transaction transaction) async {
    final currency1 = txCurrencies[transaction.currencyId];
    if (currency1 == null) {
      txToast('عملة الحركة غير معرّفة — لا يمكن طباعة الإيصال', AppColors.error);
      return;
    }
    final currency2 = transaction.targetCurrencyId == null
        ? null
        : txCurrencies[transaction.targetCurrencyId];

    final receipt = DeliveryReceiptData.fromStoredTransaction(
      tx: transaction,
      currency1: currency1,
      currency2: currency2,
      createdBy: txUser.username,
      branch: txUser.branch,
    );
    await printDeliveryReceipt(context, receipt);
  }
}
