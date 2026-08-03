# Verify: __NAME__

- Date: __DATE__
- Verdict: <PASS | BLOCK | NEEDS_MORE_INFO>

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

## Review

- lane: <full | fast | self>
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
  > fast = 主+1,中等风险;self = 主自审(闸③ + 截图 + 全量回归),
  > 限纯前端/纯观感、后端一字未动、只新增已过审针孔的调用方。
- 派给: <主 agent 直接干 | codex/gpt-5.5 | Sonnet 腿 | submimo fix> —— <为什么;
  开工前就填,判卷要不要起服务是主要考量>
- 规格自查(读任何 panel 输出之前先答):<如果规格本身就是错的,会错成什么样、我怎么发现?
  panel 只验"实现合不合规格",验不了"规格对不对" —— 四腿齐 PASS 不等于题是对的。>
- findings:
  - <...>
  > 腿死了/降级了不用在这里再抄一遍:08-03 起每份评审日志**自带身份牌**
  > (降级横幅 + 视野边界),查日志不查自述。这里只写发现,别搞第二份手填拷贝。
- arbitrated verdict (主裁): <...>
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
