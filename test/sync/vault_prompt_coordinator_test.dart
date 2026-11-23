import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/sync/vault_prompt_coordinator.dart';

/// 冷启动重装恢复口令框回归：
/// 云端存在已配置但锁定的 vault 时，探测失败不能被当成「无 vault」，
/// 后续触发点必须仍能弹出；重复触发只能弹一次。
void main() {
  test('冷启动首探失败后重试成功：立即弹框且只弹一次', () async {
    var probeCalls = 0;
    var promptCalls = 0;
    final coordinator = VaultPromptCoordinator(
      retryDelays: const [Duration.zero, Duration.zero],
      probe: () async {
        probeCalls++;
        if (probeCalls <= 2) {
          // 家庭上下文未就绪 / 网络异常：不可判定
          throw StateError('family not ready');
        }
        return (configured: true, unlocked: false);
      },
      prompt: () async => promptCalls++,
    );

    await coordinator.ensurePrompt();

    expect(probeCalls, 3);
    expect(promptCalls, 1);
    expect(coordinator.hasPrompted, isTrue);
  });

  test('全部探测失败不标记已弹：下一个触发点仍会尝试（不依赖切页面）', () async {
    var fail = true;
    var promptCalls = 0;
    final coordinator = VaultPromptCoordinator(
      retryDelays: const [Duration.zero],
      probe: () async {
        if (fail) throw StateError('network');
        return (configured: true, unlocked: false);
      },
      prompt: () async => promptCalls++,
    );

    await coordinator.ensurePrompt();
    expect(promptCalls, 0);
    expect(coordinator.hasPrompted, isFalse);

    // 模拟同步轮/回前台再次触发
    fail = false;
    await coordinator.ensurePrompt();
    expect(promptCalls, 1);
  });

  test('并发重复触发合并为一次，会话内不弹第二次', () async {
    var promptCalls = 0;
    final coordinator = VaultPromptCoordinator(
      probe: () async => (configured: true, unlocked: false),
      prompt: () async {
        promptCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );

    await Future.wait([
      coordinator.ensurePrompt(),
      coordinator.ensurePrompt(),
      coordinator.ensurePrompt(),
    ]);
    await coordinator.ensurePrompt();

    expect(promptCalls, 1);
  });

  test('未配置口令或已解锁：不弹框', () async {
    var promptCalls = 0;
    Future<void> build(bool configured, bool unlocked) {
      promptCalls = 0;
      final coordinator = VaultPromptCoordinator(
        probe: () async =>
            (configured: configured, unlocked: unlocked),
        prompt: () async => promptCalls++,
      );
      return coordinator.ensurePrompt();
    }

    await build(false, false);
    expect(promptCalls, 0);
    await build(true, true);
    expect(promptCalls, 0);
  });
}
