# shellcheck shell=bash
# 「判卷防线」这份名单的**唯一一份**(2026-08-06)。
#
# 谁用它:
#   - `track-guard` 规矩4:动了名单里的文件 ⇒ 必须挂 track;
#   - `rust-check-review-tooling`:每次总跑报一次「bin/ 里哪些工具**不在**名单内」。
#
# 为什么只准有一份:名单写在两个地方,迟早只更新其中一个 —— 本机反复记账的那条债
# (底座腿曾因此合并躯干;08-06 当天我自己也刚把规矩1/4 的逃生口从两份合成一份)。
#
# ⚠️ 名单是**手列**的,强度只等于这份清单 —— 这是它最可能失效的地方,
# 所以配了上面那条「漏网报告」:不拦(硬堵会把运维脚本也拖进来 ⇒ 误报),
# 只保证它腐烂的时候有人吭一声。

is_judging_surface() {  # is_judging_surface <仓内相对路径>
  case "$1" in
    bin/panel-*|bin/sub*|bin/delegate-*|bin/redcheck|bin/runlog|bin/ro-repo-exec|bin/track|bin/track-*|bin/rust-check-*|bin/sync-workflow-docs|bin/review-pr|bin/gh-app-token|bin/_*) return 0 ;;
    tests/test-*|tests/test_*)                                                                          return 0 ;;
    track/templates/*|track/CONVENTION.md)                                                              return 0 ;;
    workflow/*)                                                                                          return 0 ;;
  esac
  return 1
}
