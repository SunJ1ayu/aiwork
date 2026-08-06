# Proposal: gate-backdoor-coverage

- Date: 2026-08-06
- Status: open

## Goal

把上一单(guard-triggers)自己留下的两处"我知道但没动"清掉:
① 反锚定闸的**环境变量后门**改成命令行标记(env 会被 shell 继承 = 随手可按);
② 规矩4 的手列名单**腐烂时要有人吭一声**(只报不拦)。

## Motivation

用户原话:「那你先把能处理的都处理了先」。
上一轮我把三个苗头分成三类:已处理 / 能处理但停在半路 / 建议不处理。
这一单做的就是"能处理但我停在半路"的那一条,外加"中间路"那条。
第三类(7 天逃生口常开)仍然不动,理由写在 guard-triggers 的已接受偏差里。

## 真问题(第一性)

- 真正要解决的是:**别给自己留随手可按的开关**。四审两条腿都点名 `PANEL_DISPATCH`:
  它是给 panel-review 内部协调用的,但形式是环境变量 —— 在 shell 里 export 一次,
  之后每条命令都自动带着、而且不留痕。那不是机制,是后门。
- 以及:**手列的名单一定会腐烂**,硬堵会误报(把运维脚本也拖进来),
  所以让它腐烂时可见,而不是假装它不会腐烂。

## Scope

- in: `bin/_my-review-gate.sh` 加 `gate_strip_flags`;四条躯干在解析位置参数前摘标记;
  `panel-review` 改用命令行传;`bin/_tooling-paths.sh`(名单唯一一份)+
  `rust-check-review-tooling` 的漏网报告与 `--coverage-only`。

## Non-goals

- 不收窄 7 天逃生口(收紧 = 天天误报 = 报警器被拆)。
- 不给 `explore` 模式加闸(既有状态,不在本单)。
