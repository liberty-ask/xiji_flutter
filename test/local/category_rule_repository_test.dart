import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';

void main() {
  late AppDatabase db;
  late CategoryRuleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CategoryRuleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('任务 3.2：学习表写入/查询/命中计数/指认回写', () {
    test('指认回写：新文本插入条目，可按文本精确查询', () async {
      await repo.assign(
        matchText: '瑞幸咖啡（杭州）有限公司',
        categoryId: '01a15d13-bded-710c-a3bd-aba94a5aeb36', // 餐饮
        source: 0,
      );

      final entry = await repo.findByMatchText('瑞幸咖啡（杭州）有限公司');
      expect(entry, isNotNull);
      expect(entry!.categoryId, '01a15d13-bded-710c-a3bd-aba94a5aeb36');
      expect(entry.source, 0, reason: '0-账单导入');
      expect(entry.hitCount, 0, reason: '新指认从 0 起计');
    });

    test('指认回写：同一文本改指认覆盖旧分类并 version+1', () async {
      await repo.assign(
          matchText: '商户甲', categoryId: 'cat-a', source: 0);
      final first = await repo.findByMatchText('商户甲');

      await repo.assign(
          matchText: '商户甲', categoryId: 'cat-b', source: 1);
      final second = await repo.findByMatchText('商户甲');

      expect(second!.categoryId, 'cat-b');
      expect(second.id, first!.id, reason: 'match_text 唯一收敛为同一条');
      expect(second.version, first.version + 1);
      expect(second.syncPending, true);
    });

    test('指认回写：分类未变的重复指认是幂等 no-op', () async {
      await repo.assign(matchText: '商户乙', categoryId: 'cat-x', source: 0);
      final first = await repo.findByMatchText('商户乙');
      await repo.assign(matchText: '商户乙', categoryId: 'cat-x', source: 0);
      final second = await repo.findByMatchText('商户乙');

      expect(second!.version, first!.version, reason: '幂等指认不产生变更');
    });

    test('命中计数：recordHit 递增 hitCount 并 version+1', () async {
      await repo.assign(matchText: '商户丙', categoryId: 'cat-c', source: 0);
      final entry = await repo.findByMatchText('商户丙');

      await repo.recordHit(entry!.id);
      await repo.recordHit(entry.id);
      final after = await repo.findByMatchText('商户丙');

      expect(after!.hitCount, 2);
      expect(after.version, entry.version + 2);
    });

    test('未指认文本查询为空', () async {
      final entry = await repo.findByMatchText('不存在的商户');
      expect(entry, isNull);
    });
  });
}
