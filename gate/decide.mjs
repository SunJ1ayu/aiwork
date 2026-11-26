import { builderFamilies } from "./builders.mjs";
import { isMergeRequester } from "./merge-request.mjs";

import { matchAny } from "./paths.mjs";
export { matchAny, globToRegExp } from "./paths.mjs";
import { reviewPlan } from "./review-plan.mjs";
// aiwork 放行关卡的判定部分:只吃收集好的事实(collect.mjs)和策略(.aiwork/policy.json),不碰网络。
// 规则编号的来历在 git 历史里。对抗用例见 tests/test_aiwork_gate.mjs。
//
//   G1 CI:当前 head 上、来自 ci.yml 的那次运行成功,且是在最后一次改目标分支之后触发的 —— 业主批准也豁免不了
//   G2 判卷面:改了 CI / 测试入口 / 关卡自己 → 要业主批准
//   G3 评审:当前 head 或 synchronize.mjs 核实的沿用来源上至少一条合格 PASS(aiwork-review 发的、完整、家族不是本次作者的家族)—— 豁免不了；
//      汇总降级的当前 head BLOCK 里，结论可信（结论块完整、正文没被改写、结论与正文一致）且范围合格的按家族计入
//      （同一家族只算一家），但仍要业主批准；不可信的降级只移走 G5，不计家数
//   G4 作者:扣除已核实关卡同步后，这个分支上的每次推送都来自已知 Builder 账号,否则 UNKNOWN → 要业主批准
//   G5 当前 head 及沿用来源上任何一条 BLOCK → 要业主在最后一条 BLOCK 之后批准。BLOCK = aiwork-review 在当前 head 上发的、
//      除"格式完整且结论不是 BLOCK"以外的一切(BLOCK 结论、Request changes、正文结论行写 BLOCK、结论块看不懂),
//      或任何其他评审人最后一次表态是 Request changes / 被撤销(撤销只要写权限,Builder 就有,
//      撤销抹不掉反对;被撤销的评审看不出原来是什么,一律按反对算,反对的时刻是撤销那一刻)。
//      同一个人取最后一次表态(含沿用来源);但如果最后一次是旧提交上的 Approve,它不能盖掉
//      这个人在当前 head 上的反对 —— 对旧提交补一个批准不能绕过当前内容上的反对。
//   G6 high 路径:至少 high_min_families 个不同的非作者家族 PASS 或可计家数的汇总降级(豁免不了)+ 业主批准
//   G7 业主批准 = 业主在当前 head 上最后一次表态是 Approve;最后一次是 Request changes 或被撤销则一律不放行。
//      批准不从沿用的旧提交搬移;但业主在沿用来源上更新的反对/撤销会挡住放行,须在当前 head 上重新批准。
//   G8 数据不全 → 由 collect.mjs 抛错,run.mjs 判 failure
//
// 放不放行只由 decide() 说了算;合不合并 = 放行 且（合并请求算数，或普通 PR 满足直接合并白名单条件；mergeRequester / direct_merge，run.mjs 第 4 步）。

// 通用默认上限；项目策略只在需要覆盖时提供 limit。
export const DEFAULT_MODIFICATION_ROUND_LIMIT = 3;

const SHA_RE = /^[0-9a-f]{40}$/;
const VERDICTS = new Set(["PASS", "BLOCK", "NEEDS_MORE_INFO", "UNKNOWN"]);
const COMPLETENESS = new Set(["complete", "partial", "none"]);
const FAMILY_RE = /^[a-z][a-z0-9-]*$/;
// 和 bin/_review_result.py 的 VERDICT_LINE_RE 是同一条规则:独占一行的 Conclusion / Verdict / 结论,
// 后面只跟一个结论词。切行和 Python str.splitlines() 同一组换行(\r\n 算一次,结尾的换行不另起空行)。
// 用例表在 tests/fixtures/verdict-lines.json,改一边另一边的测试会红。
const VERDICT_WORDS = { "通过": "PASS", "不通过": "BLOCK", "阻断": "BLOCK", "需要更多信息": "NEEDS_MORE_INFO" };
const VERDICT_LINE_RE = /^[\t ]*[*_`]*[\t ]*(?:Conclusion|Verdict|结论)[\t ]*[：:][\t ]*(PASS|BLOCK|NEEDS_MORE_INFO|NMI|通过|不通过|阻断|需要更多信息)(?:[\t ]*[(（][\t ]*(PASS|BLOCK|NEEDS_MORE_INFO|NMI)[\t ]*[)）])?[\t ]*[*_`]*[\t ]*$/iu;
const LINE_BREAK = /\r\n|[\n\v\f\r\x1c\x1d\x1e\x85\u2028\u2029]/;

function splitLines(text) {
  if (text === "") return [];
  const parts = text.split(LINE_BREAK);
  if (parts.length > 0 && parts[parts.length - 1] === "") parts.pop();
  return parts;
}

function canonicalVerdict(word) {
  const value = VERDICT_WORDS[word] || String(word).toUpperCase();
  return value === "NMI" ? "NEEDS_MORE_INFO" : value;
}

export function conclusionLines(body) {
  const found = [];
  for (const line of splitLines(String(body ?? ""))) {
    const match = line.match(VERDICT_LINE_RE);
    if (!match) continue;
    const value = canonicalVerdict(match[1]);
    if (match[2] != null && canonicalVerdict(match[2]) !== value) continue;
    found.push(value);
  }
  return found;
}

// 评审正文里恰好一个 ```json 块;字段不全或类型不对就不算这条评审的结论。
export function parseReviewBlock(body) {
  const blocks = [...String(body ?? "").matchAll(/```json[ \t]*\r?\n([\s\S]*?)\r?\n```/g)];
  if (blocks.length !== 1) return { ok: false, why: `结论块应恰好 1 个,实为 ${blocks.length} 个` };
  let v;
  try {
    v = JSON.parse(blocks[0][1]);
  } catch {
    return { ok: false, why: "结论块不是合法 JSON" };
  }
  if (!v || typeof v !== "object" || Array.isArray(v)) return { ok: false, why: "结论块不是对象" };
  if (!VERDICTS.has(v.verdict)) return { ok: false, why: `verdict 不认识:${JSON.stringify(v.verdict)}` };
  if (typeof v.head_sha !== "string" || !SHA_RE.test(v.head_sha)) return { ok: false, why: "head_sha 不是 40 位提交号" };
  if (typeof v.model !== "string" || !v.model.trim()) return { ok: false, why: "缺 model" };
  if (typeof v.family !== "string" || !FAMILY_RE.test(v.family)) return { ok: false, why: "family 不合格" };
  if (!COMPLETENESS.has(v.completeness)) return { ok: false, why: `completeness 不认识:${JSON.stringify(v.completeness)}` };
  return { ok: true, value: v };
}

// 作者:只看推送者(仓库活动记录里的 actor),commit 里写的作者名不作数。
export function authorOf(pushes, policy) {
  if (!pushes || !pushes.covers_head) {
    return { known: false, why: "活动记录里找不到把分支推到当前 head 的那次推送" };
  }
  const builders = builderFamilies(policy);
  const actors = [...new Set(pushes.actors)];
  if (actors.length === 0) return { known: false, why: "这个分支没有推送记录" };
  const strangers = actors.filter((a) => !Object.hasOwn(builders, a));
  if (strangers.length) return { known: false, why: `有非 Builder 账号推送过:${strangers.join("、")}` };
  const families = [...new Set(actors.map((a) => builders[a]))];
  if (families.length !== 1) return { known: false, why: `推送者分属多个家族:${families.join("、")}` };
  return { known: true, family: families[0], actors };
}

// aiwork-review 的一条评审算不算 BLOCK:算就返回原因(可为空串),不算返回 null。
// BLOCK 从宽认、PASS 从严认:Request changes、结论块写 BLOCK、正文结论行写 BLOCK、结论块看不懂(缺字段、
// 不止一个、不是 JSON、没有)、发出后正文被改写过(不再是它当时写下的结论)都算 —— 看不出它想说什么,
// 或说不准是不是它说的,就当它反对(哪怕已被撤销)。review-pr 从不改写评审,要改结论就发一条新的。
// 空串表示结论块可读、正文没被改写且结论行一致；结论行与结论块不一致的评审（不论结论块是 PASS 还是
// BLOCK）仍算 BLOCK，但返回原因，不能计家族数。
function blockReason(r, p) {
  if (r.edited_at) return "发出后正文被改写过";
  if (!p.ok) return `看不懂:${p.why}`;
  const off = conclusionLines(r.body).find((c) => c !== p.value.verdict);
  if (off) return `正文结论行写的是 ${off},结论块是 ${p.value.verdict}`;
  if (r.state === "CHANGES_REQUESTED") return "";
  if (p.value.verdict === "BLOCK") return "";
  return null;
}

const isReviewerBot = (r, policy) => r.login === policy.reviewer_bot && r.type === "Bot";

// 交卷与合格 PASS 共用范围检查；BLOCK 的拦截仍先按 blockReason 处理。
function reviewScopeReason(r, v, head, author, authorFamilies) {
  if (v.head_sha !== head) return `结论写的是 ${v.head_sha.slice(0, 7)},不是这条评审对应的提交`;
  if (r.state === "DISMISSED") return "已被撤销";
  if (v.completeness !== "complete") return `不完整(${v.completeness})`;
  if (authorFamilies.has(v.family)) return `${v.family} ${author.known ? "是本次作者家族" : "是可能的 Builder 家族"},不能提供独立评审`;
  return null;
}

// 「这条评审的结论能不能拿来计家族数」的唯一判断：结论块完整可读、正文发出后没被改写
// （正文结论行与结论块一致）、范围合格（当前 head、完整、非作者家族）、结论不是 UNKNOWN。
// 正常评审家数（reviewed / passes）和汇总降级计数都只调用这里；各自只再要求结论是
// PASS / BLOCK。返回 {family} 或 {reason}；reason 只用于摘要说明「已降级但不计家数」的原因。
function countableFamily(p, why, scopeReason) {
  if (!p.ok) return { reason: `看不懂:${p.why}` };
  if (why !== null && why !== "") return { reason: why };
  if (scopeReason !== null) return { reason: `评审范围不合格:${scopeReason}` };
  if (p.value.verdict === "UNKNOWN") return { reason: "结论是 UNKNOWN" };
  return { family: p.value.family };
}

// 一条评审只有一个生效时刻 = 它现在的立场为我们所知的那一刻。选"最后一次表态"、定 BLOCK 时刻、比"批准是否晚于
// BLOCK"都只用它。评审机器人的立场写在正文里:撤销了也读得到,正文被改写就是改写那一刻;人的立场是评审状态:
// 被撤销后原立场就丢了 ⇒ 撤销那一刻(缺撤销时间就当它在最后,之前的批准豁免不了);其余 ⇒ 提交那一刻。
function effectiveAt(r, policy) {
  if (isReviewerBot(r, policy)) return r.edited_at || r.submitted_at;
  if (r.state === "DISMISSED") return r.dismissed_at || "9999-12-31T23:59:59Z";
  return r.submitted_at;
}

// 除评审机器人以外,每个评审人的表态。总体仍取最后一次(含沿用来源);
// 唯一的例外:最后一次是旧提交上的 Approve 时,不能抹掉这个人当前 head 上的反对。
// 返回 all(用于 G5/G7)和 current(只含当前 head,用来认定业主批准)。
function stancesOnHeads(reviews, policy, head, heads) {
  const current = new Map();
  const latest = new Map();
  const remember = (map, r) => {
    const prev = map.get(r.login);
    const later = !prev || effectiveAt(r, policy) > effectiveAt(prev, policy) || (effectiveAt(r, policy) === effectiveAt(prev, policy) && r.id > prev.id);
    if (later) map.set(r.login, r);
  };
  for (const r of reviews) {
    if (!heads.has(r.commit_id) || isReviewerBot(r, policy)) continue;
    if (!["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(r.state)) continue;
    remember(latest, r);
    if (r.commit_id === head) remember(current, r);
  }
  const all = new Map(latest);
  for (const [login, r] of latest) {
    const onHead = current.get(login);
    if (r.commit_id !== head && r.state === "APPROVED" && onHead && onHead.state !== "APPROVED") {
      all.set(login, onHead);
    }
  }
  return { all, current };
}

// 合并授权同时要求版本绑定和可信申请人；Builder 的同名记录或标签不算。
export function mergeRequester(facts, policy) {
  const by = facts.merge_request?.by ?? null;
  return facts.merge_request?.bound === true && isMergeRequester(by, policy) ? by : null;
}

// 围栏和引用的格式源在 summary skill；测试直接读取其中的引用示例对照。
// 汇总记录和降级记录共用这套围栏识别，不各写一份。
function fencedBlocks(body, title) {
  const blocks = [];
  let fence = null, offset = 0;
  for (const raw of body.split("\n")) {
    const line = raw.replace(/\r$/, "");
    const m = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
    if (fence) {
      if (m && m[1][0] === fence.marker && m[1].length >= fence.length && /^[ \t]*$/.test(m[2])) {
        if (fence.record) {
          fence.record.valid &&= /^```[ \t]*$/.test(line);
          fence.record.json = body.slice(fence.start, offset);
          fence.record.task = body.slice(offset + raw.length + 1).trim();
        }
        fence = null;
      }
    } else if (m) {
      const record = m[2].trim() === title
        ? { valid: line.replace(/[ \t]+$/, "") === "```" + title } : null;
      if (record) blocks.push(record);
      fence = { marker: m[1][0], length: m[1].length, start: offset + raw.length + 1, record };
    }
    offset += raw.length + 1;
  }
  return blocks;
}
const summaryBlocks = (body) => fencedBlocks(body, "aiwork-summary");
const downgradeBlocks = (body) => fencedBlocks(body, "aiwork-downgrade");

// 汇总降级的机器记录：只认登记账号在判定采用的头（当前 head 或已核实的干净同步沿用来源）
// 上发出、未被改写、恰好一个记录围栏、字段恰好三个、核实过程非空，且记录里的 head_sha
// 就是它自己所在的提交。列出的编号是否属于同一提交，由调用方按 BLOCK 所在提交核对。
// 格式定义在 summary skill；tests/test_aiwork_gate.mjs 从 schema 生成对照用例，只改一处会先红。
const DOWNGRADE_FIELDS = "evidence,head_sha,reviews";
export function parseDowngradeRecord(r, head) {
  if (r.state !== "COMMENTED" || r.edited_at) return null;
  const blocks = downgradeBlocks(r.body);
  if (blocks.length !== 1) return null;
  const [block] = blocks;
  if (block.json === undefined || !block.valid) return null;
  let v;
  try { v = JSON.parse(block.json); } catch { return null; }
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  if (Object.keys(v).sort().join(",") !== DOWNGRADE_FIELDS) return null;
  // head_sha 的格式由 summary skill 的 schema 定义；这里先按同一形状校验，再要求就是当前 head。
  if (typeof v.head_sha !== "string" || !SHA_RE.test(v.head_sha)) return null;
  if (v.head_sha !== head) return null;
  if (!Array.isArray(v.reviews) || v.reviews.length === 0) return null;
  if (!v.reviews.every((id) => Number.isSafeInteger(id) && id > 0)) return null;
  if (new Set(v.reviews).size !== v.reviews.length) return null;
  if (typeof v.evidence !== "string" || !v.evidence.trim()) return null;
  return v;
}

// 汇总记录的唯一读取：轮数显示只调用这里，白名单不再把任何汇总记录当作放行依据。
// 返回每个 head 最早的一条可信记录（byHead）、全部可信记录、上限，以及读不清的原因。
// 别人写的、旧 head 的记录留在 byHead 的各 head 下，由调用方只看当前 head；改写过、格式错误、
// 字段冲突的记录不进 byHead，只让轮数显示读不清，不提供合并结论。
const reviewRecordOrder = (a, b) => Date.parse(a.at) - Date.parse(b.at) || a.id - b.id;
function readSummaryRecords(reviews, config) {
  const limit = config.limit ?? DEFAULT_MODIFICATION_ROUND_LIMIT;
  const byHead = new Map();
  const conflicted = new Set();
  let unclear = null;
  const markUnclear = (r, why) => { if (!unclear) unclear = { id: r.id, why }; };
  for (const r of reviews) {
    if (r.login?.toLowerCase() !== config.summary_account.toLowerCase()) continue;
    // 只处理记录围栏；旧式汇总和普通评审的改写不污染轮数。
    const blocks = summaryBlocks(r.body);
    if (!blocks.length) continue;
    if (r.edited_at) { markUnclear(r, "发出后被改写过"); continue; }
    if (blocks.length !== 1) { markUnclear(r, "记录块应恰好一个"); continue; }
    const [block] = blocks;
    if (block.json === undefined) { markUnclear(r, "记录围栏没有结束"); continue; }
    if (!block.valid) { markUnclear(r, "记录围栏格式不合法"); continue; }
    let v;
    try { v = JSON.parse(block.json); } catch { markUnclear(r, "记录不是合法 JSON"); continue; }
    const task = block.task;
    if (!v || typeof v !== "object" || Array.isArray(v) ||
        Object.keys(v).sort().join(",") !== "has_p1,head_sha,next_step" ||
        typeof v.head_sha !== "string" || !SHA_RE.test(v.head_sha) ||
        !["交业主", "照单修", "合并"].includes(v.next_step) || typeof v.has_p1 !== "boolean" ||
        (v.next_step === "照单修" && (!v.has_p1 || !task)) ||
        (v.next_step === "合并" && v.has_p1)) { markUnclear(r, "记录字段或字段组合不合法"); continue; }
    if (r.state !== "COMMENTED" || r.commit_id !== v.head_sha || !Number.isFinite(Date.parse(r.submitted_at))) {
      markUnclear(r, "不是 COMMENT 评审、head 对不上或缺发出时间");
      continue;
    }
    const key = JSON.stringify([v.next_step, v.has_p1, task]);
    const previous = byHead.get(v.head_sha);
    if (previous && previous.key !== key) {
      markUnclear(r, "同一个 head 的记录互相冲突");
      conflicted.add(v.head_sha);
      byHead.delete(v.head_sha);
      continue;
    }
    if (conflicted.has(v.head_sha)) continue;
    const record = { key, value: v, at: r.submitted_at, id: r.id };
    if (!previous || reviewRecordOrder(record, previous) < 0) byHead.set(v.head_sha, record);
  }
  return { limit, byHead, records: [...byHead.values()], unclear };
}

// 只在直接合并的白名单里用：给挡住合并的记录一个可读名字。记录类型只影响摘要，
// 是否允许由调用方的白名单判断（合格 PASS、业主当前批准）。
function directRecordName(r, policy) {
  const who = r.login ?? "(未知账号)";
  if (summaryBlocks(r.body ?? "").length) return `汇总记录 #${r.id}（${who}）`;
  if (downgradeBlocks(r.body ?? "").length) return `降级记录 #${r.id}（${who}）`;
  const summaryAccount = policy.modification_rounds?.summary_account;
  if (summaryAccount && r.login?.toLowerCase() === summaryAccount.toLowerCase()) {
    return `汇总账号记录 #${r.id}（${who}）`;
  }
  if (r.login === policy.owner) return `业主记录 #${r.id}（${who}）`;
  return `评审记录 #${r.id}（${who}，${r.state ?? "状态未知"}）`;
}

// 只追加派单提示，不改变 G1–G8；直接合并另读同一份结果的当前 head 记录。
function modificationRoundLine(summary) {
  const { limit, records, unclear } = summary;
  if (unclear) return `轮数：读不清（汇总 #${unclear.id}：${unclear.why}）`;
  if (!records.length) return "轮数：未知（没有新格式的汇总记录）";
  const count = records.filter((r) => r.value.next_step === "照单修").length;
  const latest = [...records].sort(reviewRecordOrder).at(-1).value;
  // 停的定义见 REVIEW-RULES 第三节第 1 条。
  const stop = latest.has_p1 && (count > limit || (count === limit && latest.next_step !== "照单修"));
  return `轮数：第 ${count} 轮 / 上限 ${limit}${stop ? "；停：交业主" : ""}`;
}

export function decide(facts, policy) {
  const head = facts.pr.head_sha;
  const lines = [];
  const add = (ok, rule, text) => lines.push(`${ok ? "✅" : "❌"} ${rule} ${text}`);
  // 汇总记录读一次，只用于轮数显示；白名单不使用汇总记录。
  const summaryRead = policy.modification_rounds ? readSummaryRecords(facts.reviews, policy.modification_rounds) : null;

  // G1
  const ci = facts.ci;
  const pending = ci.state === "pending" || ci.state === "missing";
  // 目标分支在这次 CI 之后改过:它测的是旧目标的合并结果。缺创建时间就当作旧的
  const baseMoved = ci.state === "success" && Boolean(facts.base_changed_at) && !(Date.parse(ci.created_at) > Date.parse(facts.base_changed_at));
  const ciOk = ci.state === "success" && !baseMoved;
  if (pending) {
    add(false, "G1", ci.state === "pending" ? "CI 还在跑,等它跑完再判" : "当前 head 上还没有 CI 运行");
  } else if (baseMoved) {
    add(false, "G1", `目标分支在这次 CI 之后改过(${facts.base_changed_at}),CI 测的是旧目标:推一个新提交,或关掉再重开 PR,让 CI 在新目标上重跑`);
  } else {
    add(ciOk, "G1", ciOk ? "CI(ci.yml)在当前 head 上通过" : `CI 没通过:${ci.detail}`);
  }

  // G4
  const author = authorOf(facts.pushes, policy);
  add(author.known, "G4", author.known ? `作者:${author.actors.join("、")}(${author.family})` : `作者 UNKNOWN:${author.why}`);

  // 评审
  const botReviews = facts.reviews.filter((r) => isReviewerBot(r, policy));
  const reviewHeads = new Set([head, ...(facts.synchronization?.review_heads ?? [])]);
  const onHead = botReviews.filter((r) => reviewHeads.has(r.commit_id));
  // 已知作者只排除本次实现家族:登记为 Builder 不代表写过所有 PR。
  // UNKNOWN 沿用保守边界,不能猜测共享账号这次实际调用的模型。
  const authorFamilies = new Set(author.known ? [author.family]
    : [...Object.values(builderFamilies(policy)), ...(policy.unknown_author_extra_families ?? [])]);
  const passes = [];
  const reviewed = new Set();
  const blocks = [];
  const rejected = [];
  for (const r of onHead) {
    const p = parseReviewBlock(r.body);
    const why = blockReason(r, p);
    const scopeReason = p.ok ? reviewScopeReason(r, p.value, r.commit_id, author, authorFamilies) : null;
    const count = countableFamily(p, why, scopeReason);
    if (count.family) reviewed.add(count.family);
    if (why !== null) {
      blocks.push({
        id: r.id, bot: true, commit_id: r.commit_id, complete: p.ok,
        verdict: p.ok ? p.value.verdict : null, scopeReason, count,
        at: effectiveAt(r, policy), family: p.ok ? p.value.family : "?",
        model: `${p.ok ? p.value.model : `评审 #${r.id}`}${why ? `,${why}` : ""}`,
      });
      continue;
    }
    const v = p.value;
    // 「需要更多信息」不直接合并，不管它是否因范围问题不能算合格评审。
    // 放在范围检查之前，避免 partial / 作者家族等被跳过时漏掉这种表态。
    if (scopeReason !== null) {
      rejected.push(`评审 #${r.id}:${scopeReason}`);
      continue;
    }
    if (v.verdict !== "PASS") {
      rejected.push(`评审 #${r.id}:结论是 ${v.verdict}`);
      continue;
    }
    passes.push({ id: r.id, family: count.family, model: v.model });
  }
  const stale = botReviews.length - onHead.length;

  // 人的表态:业主单独看(G7);其他人最后一次表态不是 Approve 的,都算 BLOCK(G5)
  const { all: stances, current: currentStances } = stancesOnHeads(facts.reviews, policy, head, reviewHeads);
  const ownerLast = [...stances.values()].find((r) => r.login === policy.owner && r.type === "User") ?? null;
  const ownerCurrent = [...currentStances.values()].find((r) => r.login === policy.owner && r.type === "User") ?? null;
  // 直接合并的白名单：当前 head 和同步沿用来源上，只允许计过家数的合格 PASS，
  // 外加业主在当前 head 上的批准。汇总账号的记录只能挡、不能授权：写过任何记录都不直接合并。
  // 其余可信账号记录、任何看不懂的记录都算「别的记录」。
  const trustedDirectAccounts = new Set([
    policy.owner,
    policy.modification_rounds?.summary_account,
    policy.reviewer_bot,
    ...Object.keys(builderFamilies(policy)),
  ].filter(Boolean).map((login) => login.toLowerCase()));
  const allowedDirectReviewIds = new Set(passes.map((p) => p.id));
  // 同一 head 上可有多条业主批准（重复批准、先撤销再批准等）。每一条都在白名单里；
  // 更晚的要求修改 / 撤销由 ownerObjection 挡，不靠把较早的批准算成未允许记录。
  for (const r of facts.reviews) {
    if (r.commit_id === head && r.login === policy.owner && r.type === "User" && r.state === "APPROVED") {
      allowedDirectReviewIds.add(r.id);
    }
  }
  const unexpectedDirectRecords = [];
  for (const r of facts.reviews) {
    if (!reviewHeads.has(r.commit_id) || allowedDirectReviewIds.has(r.id)) continue;
    // 非可信账号的普通评审意见（COMMENT）不挡直接合并；其「要求修改」仍由 G5 拦。
    if (r.state === "COMMENTED" && !trustedDirectAccounts.has((r.login ?? "").toLowerCase())) continue;
    unexpectedDirectRecords.push(directRecordName(r, policy));
  }
  for (const [login, r] of stances) {
    if (login === policy.owner || r.state === "APPROVED") continue;
    blocks.push({ id: r.id, bot: false, at: effectiveAt(r, policy), family: "评审人", model: `${login}${r.state === "DISMISSED" ? "(被撤销的评审)" : " 要求修改"}` });
  }

  // 汇总降级只降评审机器人的 BLOCK:登记账号、未改写、格式完整、核实过程非空，
  // 且列出的每条都是同一提交上的 BLOCK。干净同步沿用来的来源提交上的降级记录
  // 跟那些评审一样继续算数；记录只能降它自己那条提交上的 BLOCK，不能降别的提交的。
  // 人的反对不能这样降级。
  const botBlocksById = new Map(blocks.filter((b) => b.bot).map((b) => [b.id, b]));
  const downgraded = new Set();
  const summaryAccount = policy.modification_rounds?.summary_account;
  if (summaryAccount) {
    for (const r of facts.reviews) {
      if (r.login?.toLowerCase() !== summaryAccount.toLowerCase() || !reviewHeads.has(r.commit_id)) continue;
      const record = parseDowngradeRecord(r, r.commit_id);
      if (!record || !record.reviews.every((id) => botBlocksById.get(id)?.commit_id === r.commit_id)) continue;
      for (const id of record.reviews) downgraded.add(id);
    }
  }
  const downgradedFamilies = new Set();
  const uncountedDowngrades = [];
  for (const id of downgraded) {
    const b = botBlocksById.get(id);
    // 只降 G5 还不够补评审家数：调用正常计数同一个「能不能计家数」判断。
    // 改写过、看不懂、范围不合格的评审仍按 P2 降级，但不能拿正文里的家族补 G3/G6。
    if (!b) continue;
    if (!b.count.family) {
      uncountedDowngrades.push(`评审 #${id}:${b.count.reason}`);
      continue;
    }
    if (b.verdict !== "BLOCK") {
      uncountedDowngrades.push(`评审 #${id}:结论是 ${b.verdict},不是 BLOCK`);
      continue;
    }
    downgradedFamilies.add(b.count.family);
  }
  const activeBlocks = blocks.filter((b) => !downgraded.has(b.id));

  // G3
  const plan = reviewPlan(facts.files, policy);
  const passFamilies = [...new Set(passes.map((p) => p.family))];
  const releaseFamilies = new Set([...passFamilies, ...downgradedFamilies]);
  const reviewOk = releaseFamilies.size >= plan.g3_minimum;
  const passText = passes.map((p) => `${p.model}(${p.family})`);
  const downgradedText = [...downgradedFamilies];
  const reviewText = reviewOk
    ? [
        passText.length ? `合格 PASS:${passText.join("、")}` : "",
        downgradedText.length ? `汇总降级按家族计入:${downgradedText.join("、")}` : "",
      ].filter(Boolean).join("；")
    : passes.length ? `合格 PASS 家族数不足(要 ${plan.g3_minimum} 家)${downgradedText.length ? `；汇总降级按家族计入:${downgradedText.join("、")}` : ""}`
    : downgradedText.length ? `合格 PASS 和汇总降级的家族数不足(要 ${plan.g3_minimum} 家；汇总降级计入:${downgradedText.join("、")})`
    : `当前 head 上没有合格 PASS${stale ? `(另有 ${stale} 条评审针对旧提交,不算)` : ""}`;
  add(reviewOk, "G3", reviewText);
  for (const r of rejected) lines.push(`   · ${r}`);

  // G5
  const blocked = activeBlocks.length > 0;
  if (downgraded.size) {
    const uncounted = uncountedDowngrades.length
      ? `；已降级但不计家数：${uncountedDowngrades.join("、")}` : "";
    lines.push(`   · 汇总降级：${[...downgraded].map((id) => `评审 #${id}`).join("、")} 按 P2 记（仍要业主批准，不能直接合并）${uncounted}`);
  }
  if (blocked) add(false, "G5", `有 BLOCK:${activeBlocks.map((b) => `${b.model}(${b.family})`).join("、")}`);

  // G2 / G6
  const judging = facts.files.filter((f) => matchAny(policy.judging_surface, f));
  const high = facts.files.filter((f) => matchAny(policy.high, f));
  if (judging.length) add(false, "G2", `改了判卷面:${judging.slice(0, 5).join("、")}${judging.length > 5 ? " 等" : ""}`);
  if (policy.review_dispatch) lines.push(`评审目标 ${plan.target} 家；底线 ${plan.minimum} 家；档位 ${plan.tier}（目标不足不豁免底线，也不另挡合并）`);
  const highOk = !high.length || releaseFamilies.size >= plan.minimum;
  if (high.length) {
    const familyText = downgradedFamilies.size
      ? `不同家族 PASS 或汇总降级计入 ${releaseFamilies.size} 家`
      : `不同家族 PASS ${releaseFamilies.size} 家`;
    add(highOk, "G6", `high 路径:${high.slice(0, 5).join("、")}${high.length > 5 ? " 等" : ""};${familyText}(要 ${plan.minimum} 家)`);
  }

  // G7
  // 批准只认当前 head 上的表态;ownerLast 可能是更晚的旧提交反对/撤销,照样挡住。
  const approved = ownerCurrent?.state === "APPROVED";
  const ownerObjection = ownerLast === null || ownerLast.state === "APPROVED" ? null : ownerLast.state === "DISMISSED" ? "业主的评审被撤销了,要业主重新表态" : "业主要求修改(Request changes)";
  // 批准要晚于最后一条 BLOCK（含被降级的）:业主批准时还没看到的 BLOCK,不能被那次批准豁免。
  const lastBlockAt = blocks.map((b) => b.at).sort().at(-1) ?? "";
  const blockWaived = approved && effectiveAt(ownerCurrent, policy) > lastBlockAt;
  const needOwner = [];
  if (!author.known) needOwner.push("作者 UNKNOWN");
  if (judging.length) needOwner.push("改了判卷面");
  if (blocked) needOwner.push("有 BLOCK");
  if (downgraded.size) needOwner.push("汇总降级");
  if (high.length) needOwner.push("high 路径");
  // 被白名单挡下的普通 PR：业主在当前 head 批准后才放行，贴合并标签不能单独成立。
  if (policy.review_dispatch && unexpectedDirectRecords.length && !needOwner.length) {
    needOwner.push("当前 head 上有不允许直接合并的记录");
  }
  const ownerOk = !ownerObjection && (!needOwner.length || (approved && (!blocks.length || blockWaived)));
  if (ownerObjection) {
    // 反对可能来自当前 head，也可能来自沿用来源提交；位置要写对，不能一律说成当前 head。
    const at = ownerLast.commit_id === head ? "当前 head 上" : `沿用来源提交 ${ownerLast.commit_id.slice(0, 7)} 上`;
    add(false, "G7", `${at}${ownerObjection}`);
  } else if (needOwner.length) {
    const why = !approved ? "还没有" : !blockWaived ? "批准早于最后一条 BLOCK,要在看过 BLOCK 之后再批准" : "已批准";
    add(ownerOk, "G7", `需要业主在当前 head 上批准(${needOwner.join("、")}):${why}`);
  }

  // 直接合并是白名单：当前 head（及同步沿用来源）上只允许计过家数的合格 PASS。
  // 其余记录（汇总/降级、BLOCK、需要更多信息、业主和其他账号的表态、读不清的围栏）
  // 都从 `unexpectedDirectRecords` 进来；以后出现新记录类型也默认不放行。
  // 判卷面 / high / 作者 UNKNOWN 仍走业主批准 + 合并标签；未配置 review_dispatch 保持原行为。
  const targetOk = passFamilies.length >= plan.target;
  const directReasons = [];
  if (policy.review_dispatch) {
    if (unexpectedDirectRecords.length) {
      const shown = unexpectedDirectRecords.slice(0, 5);
      directReasons.push(`当前 head 上只允许目标家数内的合格 PASS；另有 ${unexpectedDirectRecords.length} 条未允许的记录：${shown.join("、")}${unexpectedDirectRecords.length > 5 ? " 等" : ""}`);
    }
    if (judging.length || high.length) directReasons.push("改了判卷面或走 high 路径，仍要业主批准并贴合并标签");
    if (!author.known) directReasons.push("作者 UNKNOWN，要业主批准");
    if (facts.pr.draft) directReasons.push("草稿 PR 不能直接合并");
    if (!ciOk) directReasons.push(pending ? "CI 还在跑" : "CI 没通过");
    if (!reviewOk) directReasons.push(`合格 PASS 不足底线 ${plan.g3_minimum} 家`);
    if (!targetOk) directReasons.push(`合格 PASS ${passFamilies.length} 家，目标 ${plan.target} 家`);
    const directOk = directReasons.length === 0;
    add(directOk, "直接合并", directOk
      ? `可直接合并：目标 ${plan.target} 家合格 PASS 已凑齐，当前 head 上没有其他记录，CI 绿。`
      : `不直接合并：${directReasons.join("；")}。`);
  }
  const directMerge = { enabled: Boolean(policy.review_dispatch), ok: Boolean(policy.review_dispatch) && directReasons.length === 0, reasons: directReasons };

  const minimumMet = reviewOk && highOk;
  const missingTarget = Math.max(0, plan.target - reviewed.size);
  const verdictLine = (() => {
    if (!ciOk) return pending ? "等 CI" : baseMoved ? "不放行:目标分支改过,CI 要在新目标上重跑" : "不放行:CI 没通过";
    if (!reviewOk) return "不放行:缺合格评审";
    if (!highOk) return `不放行:high 路径要 ${plan.minimum} 家不同家族都 PASS`;
    if (ownerObjection) return `不放行:${ownerObjection}`;
    if (!ownerOk) return `等业主批准:${needOwner.join("、")}`;
    return "放行";
  })();
  const pass = verdictLine === "放行";
  const roundLine = summaryRead ? modificationRoundLine(summaryRead) : null;
  return {
    status: pending ? "in_progress" : "completed",
    conclusion: pending ? null : pass ? "success" : "failure",
    title: verdictLine,
    summary: [`head \`${head}\``, "", ...(roundLine ? [roundLine, ""] : []), ...(facts.synchronization?.note ? [facts.synchronization.note, ""] : []), ...lines].join("\n"),
    ...(roundLine ? { round_line: roundLine } : {}),
    review_state: {
      plan,
      excluded: [...authorFamilies],
      reviewed_families: [...reviewed],
      pass_families: passFamilies,
      downgraded_families: [...downgradedFamilies],
      minimum_met: minimumMet,
      target_met: missingTarget === 0,
      missing_target: missingTarget,
      next_step: minimumMet ? '等汇总' : '交业主',
    },
    author,
    passes,
    blocks: activeBlocks,
    direct_merge: directMerge,
  };
}
