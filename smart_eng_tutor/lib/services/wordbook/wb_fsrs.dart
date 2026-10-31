import 'package:fsrs/fsrs.dart' as fsrs;

/// 一次复习的计算结果
class FsrsOutcome {
  final double stability;    // S（天）
  final double difficulty;   // D（1~10）
  final double intervalDays; // 建议间隔（天，可为小数）
  const FsrsOutcome(this.stability, this.difficulty, this.intervalDays);
}

/// FSRS-6 引擎（官方纯 Dart 实现 dart-fsrs 2.x）。
/// 全 app 只有本文件接触 fsrs 包。
class FsrsEngine {
  final fsrs.Scheduler _s;
  FsrsEngine._(this._s);

  static Future<FsrsEngine> create({double desiredRetention = 0.9}) async {
    final s = fsrs.Scheduler(
      desiredRetention: desiredRetention,
      enableFuzzing: true, // 间隔轻微抖动，避免同批卡片同日到期
      // 短期步骤设为空：答错 → 10 分钟的兜底由 wb_database 的 dueAt 逻辑统一管理，
      // 避免包内 short-term 调度和我们自己的调度打架
      learningSteps: const [],
      relearningSteps: const [],
    );
    return FsrsEngine._(s);
  }

  /// 复习一次。
  /// rating: 0=答错 1=不熟练 2=答对（映射 FSRS 的 Again/Hard/Good）
  /// isNew: 该词条从未复习过（stability==0）
  Future<FsrsOutcome> review({
    required bool isNew,
    double stability = 0,
    double difficulty = 0,
    required int rating,
    required double daysElapsed, // 保留参数以稳定调用方签名（包内部自行按 lastReview 计算）
  }) async {
    final rt = switch (rating) {
      0 => fsrs.Rating.again,
      1 => fsrs.Rating.hard,
      _ => fsrs.Rating.good,
    };

    // 从我们持久化的 S/D 重建卡片状态（cardId 仅占位，持久化不依赖它）
    final card = isNew
        ? fsrs.Card(cardId: 0)
        : fsrs.Card(
            cardId: 0,
            state: fsrs.State.review,
            stability: stability,
            difficulty: difficulty,
          );

    final result = _s.reviewCard(card, rt);
    final next = result.card;
    final reviewLog = result.reviewLog;

    // 建议间隔 = 新到期时间 - 复习时刻
    final intervalDays =
        next.due.difference(reviewLog.reviewDateTime).inMinutes / 1440.0;

    return FsrsOutcome(
      next.stability ?? stability,
      next.difficulty ?? difficulty,
      intervalDays > 0 ? intervalDays : (next.stability ?? stability),
    );

  }
}
