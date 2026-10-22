import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/db_provider.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';

/// 账号分库（tasks 7.0 / design.md D12）：双账号库文件隔离、
/// 回登复用、旧单库认领过户。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('xiji_db_account_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  AppDatabase openDb(String userId) => AppDatabase(NativeDatabase(
      File('${tempDir.path}/${dbFileNameFor(userId)}')));

  group('dbFileNameFor', () {
    test('账号库文件按 userId 命名', () {
      expect(dbFileNameFor('2009264986806337537'),
          'xiji_2009264986806337537.sqlite');
    });
  });

  group('claimLegacyDb 旧库认领', () {
    test('目标库不存在且旧库存在时 rename 过户', () async {
      final legacy = File('${tempDir.path}/xiji.sqlite')
        ..writeAsStringSync('legacy-data');
      await claimLegacyDb(dir: tempDir, userId: 'u1');
      expect(await legacy.exists(), isFalse);
      expect(
          await File('${tempDir.path}/${dbFileNameFor('u1')}').exists(), isTrue);
    });

    test('目标库已存在时不动旧库（该账号已用过）', () async {
      final legacy = File('${tempDir.path}/xiji.sqlite')
        ..writeAsStringSync('legacy-data');
      File('${tempDir.path}/${dbFileNameFor('u1')}').writeAsStringSync('u1-data');
      await claimLegacyDb(dir: tempDir, userId: 'u1');
      expect(await legacy.exists(), isTrue, reason: '目标已存在不得覆盖');
    });

    test('无旧库时 no-op（全新账号）', () async {
      await claimLegacyDb(dir: tempDir, userId: 'u2');
      expect(
          await File('${tempDir.path}/${dbFileNameFor('u2')}').exists(), isFalse);
    });

    test('userId 为空时 no-op', () async {
      File('${tempDir.path}/xiji.sqlite').writeAsStringSync('legacy-data');
      await claimLegacyDb(dir: tempDir, userId: '');
      expect(await File('${tempDir.path}/xiji.sqlite').exists(), isTrue);
    });

    test('认领对第二个账号不重复过户', () async {
      File('${tempDir.path}/xiji.sqlite').writeAsStringSync('legacy-data');
      await claimLegacyDb(dir: tempDir, userId: 'u1');
      await claimLegacyDb(dir: tempDir, userId: 'u2');
      expect(
          await File('${tempDir.path}/${dbFileNameFor('u1')}').exists(), isTrue);
      expect(await File('${tempDir.path}/${dbFileNameFor('u2')}').exists(),
          isFalse,
          reason: '旧库已被 u1 认领，u2 不得再拿到任何文件');
    });
  });

  group('双账号库隔离与回登复用（真文件库）', () {
    test('A 账号数据对 B 账号不可见，A 回登数据仍在', () async {
      // A 账号写入一笔交易（走 Repository 正常入库路径，含 FTS 双写）
      final dbA = openDb('uA');
      await TransactionRepository(dbA).insert(TransactionsCompanion.insert(
        id: const Value('tx-a1'),
        type: 1,
        categoryId: 'cat',
        amountCents: 4620,
        date: DateTime.now(),
        userId: 'uA',
      ));
      await dbA.close();

      // B 账号开自己的库：看不到 A 的交易
      final dbB = openDb('uB');
      final bAll = await dbB.select(dbB.transactions).get();
      expect(bAll.where((t) => t.id == 'tx-a1').isEmpty, isTrue,
          reason: 'B 库为空，A 的交易不可见');
      await dbB.close();

      // A 回登：数据原样保留（关库不删文件）
      final dbA2 = openDb('uA');
      final aAll = await dbA2.select(dbA2.transactions).get();
      expect(aAll.where((t) => t.id == 'tx-a1').length, 1,
          reason: '回登复用：关闭不删数据');
      expect(aAll.first.amountCents, 4620);
      await dbA2.close();
    });
  });
}
