import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/fts_tokenizer.dart';

void main() {
  group('任务 1.1 附带结论：FTS5 中文拆字分词器', () {
    test('中文逐字成 token', () {
      expect(FtsTokenizer.tokenize('瑞幸咖啡'), '瑞 幸 咖 啡');
      expect(FtsTokenizer.tokenize('拿铁'), '拿 铁');
    });

    test('英文数字保留整词', () {
      expect(FtsTokenizer.tokenize('latte'), 'latte');
      expect(FtsTokenizer.tokenize('15.9'), '15 9', reason: '小数点是断词符');
    });

    test('混合文本', () {
      expect(FtsTokenizer.tokenize('星巴克 latte 15.9'), '星 巴 克 latte 15 9');
      expect(FtsTokenizer.tokenize('瑞幸,咖啡'), '瑞 幸 咖 啡');
      expect(FtsTokenizer.tokenize('A/B'), 'A B');
    });

    test('短语查询串格式', () {
      expect(FtsTokenizer.phrase('拿铁'), '"拿 铁"');
      expect(FtsTokenizer.phrase('星巴克'), '"星 巴 克"');
    });
  });
}
