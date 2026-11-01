// aiwork 放行关卡的流程。网络与 App 令牌由 main.mjs 注入;判定在 decide.mjs,读数据在 collect.mjs。
//
// 只守三件事:
//   · **关卡的结论只取决于 GitHub 上的现状,与是哪个事件叫醒它无关**:每次运行把所有开着的 PR 全重算一遍,
//     事件只是门铃。不从事件推"该算哪个 PR、写到哪个提交"—— 那条路上漏过好几次(没带 PR 的事件、旧提交、合并提交)。
//   · **同一时间只有一次运行**(workflow 的并发组是一个固定名字、不取消正在跑的;排队的只留最新一个,它开始时读到的
//     一定不比被它顶掉的旧一些)。所以同一提交上后写的结论一定出自后读的数据,不会有慢一步的旧运行盖掉新结论,
//     也用不着猜 GitHub 在同名检查里按什么取"最新"(后发的一定后写完)。
//   · **一个提交上的结论 = 以它为 head 的所有开着的 PR 的结论合在一起;读不全就不放行(G8)。**
//     检查挂在提交上;同一提交可以是几个 PR 的 head,目标分支不同 ⇒ 改动、要求都不同。
//
// 一次运行:
//   1. 列出所有开着的 PR(连读两遍一致才算数),按 head 提交分组;
//   2. 先给每个 head 发 App 的 in_progress 占位,之后才读 PR 的数据 ——
//      半路卡住或死掉,已创建且未完成的检查停在 in_progress,压住上一次的结论;
//   3. 每个 head:把以它为 head 的 PR 全判一遍,合成一个结论写一次;
//   4. 结论写上且是放行,就当场合并这个 head 上有合并请求的 PR(见 decide.mjs 的 mergeRequester),
//      带上判过的 head —— 合并用的就是这次刚读到的数据,判完之后又推了新提交,合并接口会拒。
//      没放行的请求留着,等哪次运行判为放行再合。这就是"合并那一刻再判一次":不另起一套判定。
//
// App 发不出占位、写不回结论或策略不合法时,本次运行不会合并该 head。
// main 只许关卡合并,因此网页上的旧 success 不能被借来手动合并;规则依据见 README「合并」。
// 运行被取消或超时:已创建且未完成的 App 检查停在 in_progress;下一次运行全部重算。
// 这种"事件来了再重算"的做法本身补不死的窗口,见 README「已知限制」。

import { collect, paginate } from "./collect.mjs";
import { decide, mergeRequester } from "./decide.mjs";

export function validatePolicy(p) {
  const bad = [];
  if (typeof p?.check_name !== "string" || !p.check_name) bad.push("check_name");
  if (!Number.isInteger(p?.gate_app_id) || p.gate_app_id <= 0) bad.push("gate_app_id");
  if (typeof p?.owner !== "string" || !p.owner) bad.push("owner");
  if (!p?.builders || typeof p.builders !== "object" ||
      Array.isArray(p.builders) || !Object.keys(p.builders).length) bad.push("builders");
  if (typeof p?.reviewer_bot !== "string" || !p.reviewer_bot.endsWith("[bot]")) bad.push("reviewer_bot");
  if (typeof p?.ci?.workflow_path !== "string" || typeof p?.ci?.event !== "string") bad.push("ci");
  if (!Array.isArray(p?.judging_surface) || !Array.isArray(p?.high)) bad.push("judging_surface/high");
  if (!Number.isInteger(p?.high_min_families) || p.high_min_families < 2) bad.push("high_min_families");
  if (typeof p?.merge_label !== "string" || !p.merge_label) bad.push("merge_label");
  // Builder 不能在名单里:不然它能自己把自己的 PR 合进去
  const requesters = p?.merge_requesters;
  if (!Array.isArray(requesters) || !requesters.every((m) => typeof m === "string" && m && !Object.hasOwn(p?.builders ?? {}, m))) {
    bad.push("merge_requesters");
  }
  if (p && Object.hasOwn(p, "modification_rounds")) {
    const c = p.modification_rounds;
    const account = c?.summary_account;
    const otherRoles = [p.reviewer_bot, p.owner, ...(Array.isArray(requesters) ? requesters : [])];
    if ((Object.hasOwn(c ?? {}, "limit") && (!Number.isSafeInteger(c.limit) || c.limit <= 0)) || typeof account !== "string" ||
        !/^[A-Za-z0-9][A-Za-z0-9-]*(?:\[bot\])?$/.test(account) ||
        otherRoles.some((r) => typeof r === "string" && r.toLowerCase() === account.toLowerCase())) {
      bad.push("modification_rounds");
    }
  }
  if (bad.length) throw new Error(`.aiwork/policy.json 不完整或不合法:${bad.join("、")}`);
}

const SHA_RE = /^[0-9a-f]{40}$/;

const g8 = (message) => ({ status: "completed", conclusion: "failure", title: "不放行:数据不全(G8)", summary: `读 GitHub 数据出错,按失败处理:\n\n${message}` });
const moved = { status: "completed", conclusion: "failure", title: "这个提交已不是开着的 PR 的 head", summary: "列出 PR 之后它又推进或关闭了;新的 head 由它的事件叫醒的下一次运行来算。" };

// 几个 PR 的结论合成一个:有一个不放行就不放行,有一个在等就等,全都放行才放行。
function combine(verdicts) {
  if (verdicts.length === 1) return verdicts[0].r;
  const pick =
    verdicts.find((v) => v.r.status === "completed" && v.r.conclusion !== "success") ??
    verdicts.find((v) => v.r.status !== "completed") ??
    verdicts[0];
  const list = verdicts.map((v) => `- PR #${v.number}:${v.r.title}${v.r.round_line ? `；${v.r.round_line}` : ""}`).join("\n");
  const overview = `这个提交是 ${verdicts.length} 个开着的 PR 的 head(检查挂在提交上,全都放行才放行):\n${list}`;
  return {
    ...pick.r,
    title: `PR #${pick.number}:${pick.r.title}`,
    // GitHub 会截断长摘要；逐 PR 的轮数/停信号先写，不能被某个 PR 的长详情挤掉。
    summary: verdicts.some((v) => v.r.round_line)
      ? `${overview}\n\n---\n${pick.r.summary}`
      : `${pick.r.summary}\n\n---\n${overview}`,
  };
}

// 开着的 PR 的快照。列表不是一次拍下的:翻页期间有 PR 关掉,后面的会往前挪、漏掉一个 —— 连读两遍一致才算数
async function openPrs(api, repo) {
  let seen = null;
  for (let round = 0; round < 4; round++) {
    const prs = (await paginate(api, `/repos/${repo}/pulls?state=open&per_page=100`)).map((p) => ({ number: p.number, sha: p.head?.sha }));
    const key = JSON.stringify(prs.map((p) => [p.number, p.sha]).sort((x, y) => x[0] - y[0]));
    if (key === seen) return prs;
    seen = key;
  }
  throw new Error("开着的 PR 连读四遍都对不上(一直有 PR 在开关或推送)");
}

export async function gate({ repo, policy, api, poster, merger = null, log = () => {} }) {
  const errors = [];
  // 1. 所有开着的 PR,按 head 提交分组
  const heads = new Map();
  for (const { number, sha } of await openPrs(api, repo)) {
    if (typeof sha !== "string" || !SHA_RE.test(sha)) throw new Error(`PR #${number} 的 head 不是提交号`);
    if (!heads.has(sha)) heads.set(sha, []);
    heads.get(sha).push(number);
  }
  validatePolicy(policy);

  // 2. 先给每个 head 发 App 占位,之后才读 PR 的数据
  const ids = new Map();
  for (const sha of heads.keys()) {
    try {
      ids.set(sha, await poster.start(sha));
    } catch (e) {
      errors.push(e);
    }
  }

  // 3. 每个 head:以它为 head 的 PR 全判一遍,合成一个结论写一次
  const results = [];
  for (const [sha, numbers] of heads) {
    if (!ids.has(sha)) continue;
    let result;
    const verdicts = [];
    try {
      for (const n of numbers) {
        const facts = await collect(api, repo, n, policy);
        if (facts.pr.state !== "open" || facts.pr.head_sha !== sha) continue; // 列出之后又推进 / 关了
        let r;
        try {
          r = decide(facts, policy);
        } catch (e) {
          r = g8(`判定出错:${e.message}`);
        }
        verdicts.push({ number: n, r, request: facts.merge_request, mergeBy: mergeRequester(facts, policy) });
      }
      result = verdicts.length ? combine(verdicts) : moved;
    } catch (e) {
      result = g8(e.message);
    }
    try {
      await poster.finish(sha, result, ids.get(sha));
    } catch (e) {
      errors.push(e);
      continue;
    }
    log(`${sha.slice(0, 7)}:${result.title}\n${result.summary}`);
    results.push({ sha, title: result.title, summary: result.summary });
    // 4. 合并:只在这个提交上的 App 放行结论写上了的时候;
    //    合并出错(判完又推了新提交、有冲突)只记下,请求留着
    for (const v of verdicts) {
      if (v.request && !v.mergeBy) {
        const who = v.request.by ? `是 ${v.request.by} 提的` : "在 PR 事件里找不到是谁提的";
        log(`PR #${v.number}:贴着合并标签,但合并请求${who},不算数(只认业主和 merge_requesters)`);
      }
      if (!v.mergeBy || result.status !== "completed" || result.conclusion !== "success") continue;
      try {
        if (!merger) throw new Error("没有合并接口");
        await merger.merge(v.number, sha);
        log(`PR #${v.number}:按 ${v.mergeBy} 的请求合并了 ${sha.slice(0, 7)}`);
      } catch (e) {
        log(`PR #${v.number}:按 ${v.mergeBy} 的请求合并 ${sha.slice(0, 7)} 没成:${e.message}`);
      }
    }
  }
  if (errors.length) throw errors[0];
  return results;
}
