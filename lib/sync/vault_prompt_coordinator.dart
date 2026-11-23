/// vault 口令框触发协调器（冷启动重装恢复）。
///
/// 解决「探测只在家庭列表加载回调里执行一次、首次失败后要等页面重建
/// 才重试」的问题：
/// - [ensurePrompt] 可被多个时机重复调用（启动、同步轮、回前台），
///   并发调用合并为一次，会话内只弹一次；
/// - [probe] 抛错（网络/家庭上下文未就绪/存储未就绪）视为「本次不可
///   判定」，按 [retryDelays] 退避重试；全部失败则保持未弹状态，留给
///   下一个触发点，而不是永久跳过；
/// - [probe] 明确返回「未配置」或「已解锁」时立即结束，不重复探测。
class VaultPromptCoordinator {
  VaultPromptCoordinator({
    required this.probe,
    required this.prompt,
    this.retryDelays = const [
      Duration(milliseconds: 300),
      Duration(milliseconds: 700),
    ],
  });

  /// 返回 vault 当前状态；无法判定时抛异常
  final Future<({bool configured, bool unlocked})> Function() probe;

  /// 实际弹框（由调用方负责具体 UI）
  final Future<void> Function() prompt;

  /// 探测失败后的退避间隔，长度即额外重试次数
  final List<Duration> retryDelays;

  bool _prompted = false;
  Future<void>? _inFlight;

  /// 本次会话是否已弹过口令框
  bool get hasPrompted => _prompted;

  /// 幂等触发：重复/并发调用共享同一次执行；已弹过直接返回
  Future<void> ensurePrompt() {
    if (_prompted) return Future<void>.value();
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<void> _run() async {
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (_prompted) return;
      try {
        final state = await probe();
        if (!state.configured || state.unlocked) return;
        _prompted = true;
        await prompt();
        return;
      } catch (_) {
        if (attempt >= retryDelays.length) return;
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }
}
