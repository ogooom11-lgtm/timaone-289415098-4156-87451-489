import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// جدول المستخدمين
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 3, max: 32)();
  TextColumn get password => text()();
  TextColumn get role =>
      text().withDefault(const Constant("user"))(); // admin/user
  TextColumn get branch => text().withLength(min: 2, max: 50)(); // الفرع
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// جدول العملات
class Currencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 2, max: 10)(); // USD, SYP...
  TextColumn get name => text().nullable()();
  RealColumn get rate => real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// جدول الحركات
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().customConstraint('REFERENCES users(id)')();
  IntColumn get currencyId =>
      integer().customConstraint('REFERENCES currencies(id)')();
  IntColumn get targetCurrencyId =>
      integer().nullable().customConstraint('NULL REFERENCES currencies(id)')();
  IntColumn get feesCurrencyId =>
      integer().nullable().customConstraint('NULL REFERENCES currencies(id)')();

  TextColumn get createdByName =>
      text().withDefault(const Constant("غير معروف"))();
  TextColumn get type => text()(); // إضافة حركة تسليم / استلام / مرسلة / صرف
  TextColumn get beneficiary => text().nullable()();
  RealColumn get amount => real()();
  RealColumn get targetAmount => real().nullable()();
  RealColumn get exchangeRate => real().nullable()();
  RealColumn get fees => real().nullable()();
  TextColumn get operation => text().nullable()(); // قص / ضرب
  TextColumn get note => text().nullable()();

  TextColumn get movementState => text().withDefault(const Constant("مفعلة"))();
  TextColumn get status => text().withDefault(const Constant("قيد التسليم"))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// جدول التعديلات
class Edits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId =>
      integer().customConstraint('REFERENCES transactions(id)')();

  TextColumn get field => text()();
  TextColumn get oldValue => text()();
  TextColumn get newValue => text()();
  DateTimeColumn get editedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get editedBy => text().withDefault(const Constant("system"))();
}

@DriftDatabase(tables: [Users, Currencies, Transactions, Edits])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  static Future<File> databaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'app_database.sqlite'));
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 3) {
        await m.addColumn(users, users.branch);
      }
      if (from < 4) {
        await m.addColumn(transactions, transactions.status);
      }
      if (from < 5) {
        await m.addColumn(transactions, transactions.targetCurrencyId);
        await m.addColumn(transactions, transactions.feesCurrencyId);
        await m.addColumn(transactions, transactions.createdByName);
        await m.addColumn(transactions, transactions.targetAmount);
        await m.addColumn(transactions, transactions.movementState);
      }
    },
  );

  // ---------- Users ----------
  Future<int> insertUser(UsersCompanion entry) => into(users).insert(entry);
  Future<List<User>> getAllUsers() => select(users).get();
  Future<User?> getUserById(int id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  Future<User?> getUserByUsername(String username) => (select(
    users,
  )..where((u) => u.username.equals(username))).getSingleOrNull();
  Future<User?> authenticateUser(String username, String password) =>
      (select(users)
            ..where((u) => u.username.equals(username.trim()))
            ..where((u) => u.password.equals(password)))
          .getSingleOrNull();

  // ---------- Currencies ----------
  Future<int> insertCurrency(CurrenciesCompanion entry) =>
      into(currencies).insert(entry);
  Future<List<Currency>> getAllCurrencies() => select(currencies).get();
  Future<int> updateCurrency(int id, CurrenciesCompanion entry) =>
      (update(currencies)..where((c) => c.id.equals(id))).write(entry);
  Future<int> deleteCurrency(int id) =>
      (delete(currencies)..where((c) => c.id.equals(id))).go();

  // ---------- Transactions ----------
  Future<int> insertTransaction(TransactionsCompanion entry) =>
      into(transactions).insert(entry);
  Future<List<Transaction>> getAllTransactions() => (select(
    transactions,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  Future<int> updateTransaction(int id, TransactionsCompanion entry) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(entry);
  Future<int> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  // ---------- Edits ----------
  Future<int> insertEdit(EditsCompanion entry) => into(edits).insert(entry);
  Future<List<Edit>> getEditsForTransaction(int transactionId) => (select(
    edits,
  )..where((e) => e.transactionId.equals(transactionId))).get();

  // ---------- Dynamic Syrian Offices Management ----------
  Future<List<String>> getOfficeNames() async {
    try {
      final rows = await customSelect(
        'SELECT name FROM offices ORDER BY id ASC',
      ).get();
      return rows.map((row) => row.read<String>('name')).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addOffice(String name) async {
    await customStatement('INSERT INTO offices (name) VALUES (?)', [name]);
  }

  Future<void> deleteOffice(String name) async {
    await customStatement('DELETE FROM offices WHERE name = ?', [name]);
  }

  Future<void> ensureInitialData() async {
    // نحتفظ بالجدول لتوافق قواعد البيانات القديمة فقط؛ لا توجد إدارة فروع.
    await customStatement(
      'CREATE TABLE IF NOT EXISTS offices (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)',
    );
    // لا توجد صلاحيات مسؤول؛ الحسابات كلها موظفون.
    await customStatement(
      "UPDATE users SET role = 'user' WHERE role <> 'user'",
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await AppDatabase.databaseFile();

    return NativeDatabase(file, logStatements: true);
  });
}
