import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/voice_transaction_parser.dart';

void main() {
  // 固定基准时间：2026-10-21（周三）
  final now = DateTime(2026, 10, 21, 15, 0);

  VoiceTextFacts parse(String text) => VoiceTextFacts.parse(text, now: now);

  group('任务 4.1：金额提取', () {
    test('典型句式：阿拉伯数字 + 元/块', () {
      expect(parse('打车花了25.5元').amount, 25.5);
      expect(parse('午饭吃面30块').amount, 30);
      expect(parse('买咖啡30块钱').amount, 30);
    });

    test('口语补角：30块5 / 30块5毛 / 15块5', () {
      expect(parse('打车30块5').amount, 30.5);
      expect(parse('打车30块5毛').amount, 30.5);
      expect(parse('奶茶十五块五').amount, 15.5);
    });

    test('货币符号：¥88 / ￥12.5', () {
      expect(parse('超市¥88').amount, 88);
      expect(parse('￥12.5').amount, 12.5);
    });

    test('中文数字标准式', () {
      expect(parse('坐公交花了三元').amount, 3);
      expect(parse('买水果十五块').amount, 15);
      expect(parse('吃饭三十元').amount, 30);
      expect(parse('交房租两千五百元').amount, 2500);
      expect(parse('发工资一万五千块').amount, 15000);
      expect(parse('充话费一百二十元').amount, 120);
    });

    test('中文数字含零：三百零五=305 五百零二=502', () {
      expect(parse('充值三百零五元').amount, 305);
      expect(parse('收红包五百零二元').amount, 502);
    });

    test('口语无单位缩写（一百二/三千五）无货币线索，不猜测', () {
      expect(parse('打车花了一百二').amount, isNull);
      expect(parse('买电脑三千五').amount, isNull);
    });

    test('无金额：无线索文本返回 null，不猜测', () {
      expect(parse('买了一杯奶茶').amount, isNull);
      expect(parse('买编号30的东西').amount, isNull, reason: '裸数字不当作金额');
      expect(parse('花了0元').amount, isNull, reason: '金额须大于 0');
    });

    test('多金额冲突：互不相同的金额标记冲突，取首个', () {
      final facts = parse('打车花了30块，午饭吃面15元');
      expect(facts.amount, 30);
      expect(facts.amountConflict, isTrue);
    });

    test('同一金额重复出现不算冲突', () {
      final facts = parse('30元就30块钱');
      expect(facts.amount, 30);
      expect(facts.amountConflict, isFalse);
    });
  });

  group('任务 4.1：类型提取', () {
    test('支出词：花了/买了/消费/付了', () {
      expect(parse('午饭花了30元').type, 1);
      expect(parse('买了杯咖啡15元').type, 1);
      expect(parse('消费三十元').type, 1);
    });

    test('收入词：收到/工资/红包/到账', () {
      expect(parse('收到红包200元').type, 0);
      expect(parse('发工资了五千块').type, 0);
      expect(parse('工资到账八千块').type, 0);
    });

    test('类型词未明示返回 null（不默认猜测）', () {
      expect(parse('今天午饭三十元').type, isNull);
    });

    test('收支出现在同句时以最早出现的词为准', () {
      expect(parse('买了东西又收到退款5元').type, 1);
      expect(parse('收到退款又买了东西5元').type, 0);
    });
  });

  group('任务 4.1：日期提取', () {
    test('相对词：今天/昨天/前天/大前天', () {
      expect(parse('今天午饭30元').date, DateTime(2026, 10, 21));
      expect(parse('昨天打车30元').date, DateTime(2026, 10, 20));
      expect(parse('前天买书30元').date, DateTime(2026, 10, 19));
      expect(parse('大前天聚餐30元').date, DateTime(2026, 10, 18));
    });

    test('N号：本月过去日直接取本月', () {
      expect(parse('5号交房租2500元').date, DateTime(2026, 10, 5));
    });

    test('N号晚于今天视为上月', () {
      expect(parse('25号聚餐30元').date, DateTime(2026, 9, 25));
    });

    test('未提及日期返回 null（调用方默认今天）', () {
      expect(parse('打车花了30元').date, isNull);
    });

    test('N号是日期不是金额：与金额提取互不干扰', () {
      final facts = parse('30号交房租2500元');
      expect(facts.amount, 2500);
      expect(facts.date, DateTime(2026, 9, 30));
    });
  });
}
