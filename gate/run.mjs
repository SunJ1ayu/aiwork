import { builderFamilies } from "./builders.mjs";
import { TransientPrState } from './synchronize.mjs';
// aiwork 放行关卡的流程。网络与 App 令牌由 main.mjs 注入;判定在 decide.mjs,读数据在 collect.mjs。
//
// 只守三件事:
//   · **关卡的结论只取决于 GitHub 上的现状,与是哪个事件叫醒它无关**:每次运行把所有开着的 PR 全重算一遍,
//     事件只是门铃。不从事件推"该算哪个 PR、写到哪个提交"—— 那条路上漏过好几次(没带 PR 的事件、旧提交、合并提交)。
//   · **同一时间只有一次重算**(workflow 的 gate 任务并发组是一个固定名字、不取消正在跑的;排队的只留最新一个,它开始时读到的
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
//   4. 结论写上且是放行,就当场合并这个 head 上该合的 PR:有可信合并请求的(见 decide.mjs 的
//      mergeRequester),或普通 PR 当前 head 干净、只有够数合格 PASS 时由关卡直接合并(见 decide.mjs 的 direct_merge)。
//      带上判过的 head —— 合并用的就是这次刚读到的数据,判完之后又推了新提交,合并接口会拒。
//      没放行的请求留着,等哪次运行判为放行再合。这就是"合并那一刻再判一次":不另起一套判定。
//
// App 发不出占位、写不回结论或策略不合法时,本次运行不会合并该 head。
// main 只许关卡合并,因此网页上的旧 success 不能被借来手动合并;规则依据见 README「合并」。
// 运行被取消或超时:已创建且未完成的 App 检查停在 in_progress;下一次运行全部重算。
// 这种"事件来了再重算"的做法本身补不死的窗口,见 README「已知限制」。

import { validateReviewPolicy } from "./review-plan.mjs";
import { collect, paginate } from "./collect.mjs";
import { decide, mergeRequester } from "./decide.mjs";

export function validatePolicy(p) {
  const bad = [];
  if (typeof p?.check_name !== "string" || !p.check_name) bad.push("check_name");
  if (!Number.isInteger(p?.gate_app_id) || p.gate_app_id <= 0) bad.push("gate_app_id");
  if (typeof p?.owner !== "string" || !p.owner) bad.push("owner");
  try { builderFamilies(p); } catch { bad.push("builders"); }
  const extraFamilies = p?.unknown_author_extra_families;
  if (p && Object.hasOwn(p, "unknown_author_extra_families") &&
      (!Array.isArray(extraFamilies) || !extraFamilies.every((family) =>
        typeof family === "string" && /^[a-z][a-z0-9-]*$/.test(family)))) {
    bad.push("unknown_author_extra_families");
  }
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
    const otherRoles = [p.reviewer_bot, p.owner, ...(Array.isArray(requesters) ? requesters : []),
      ...Object.keys(p.builders ?? {})];
    if ((Object.hasOwn(c ?? {}, "limit") && (!Number.isSafeInteger(c.limit) || c.limit <= 0)) || typeof account !== "string" ||
        !/^[A-Za-z0-9][A-Za-z0-9-]*(?:\[bot\])?$/.test(account) ||
        otherRoles.some((r) => typeof r === "string" && r.toLowerCase() === account.toLowerCase())) {
      bad.push("modification_rounds");
    }
  }
  if (p && Object.hasOwn(p, "post_merge_check")) {
    const c = p.post_merge_check;
    const modes = ["all", "sample", "off"];
    const valid = Boolean(c) && typeof c === "object" && !Array.isArray(c) &&
      modes.includes(c.mode) &&
      Object.keys(c).every((k) => k === "mode" || k === "sample_every") &&
      (c.mode === "sample"
        ? Number.isSafeInteger(c.sample_every) && c.sample_every >= 1
        : !Object.hasOwn(c, "sample_every"));
    if (!valid) bad.push("post_merge_check");
  }
  validateReviewPolicy(p);
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
  const list = verdicts.map((v) => `- PR #${v.number}:${v.r.title}${v.r.round_line ? `；${v.r.round_line}` : ""}${v.r.merge_note ? `；${v.r.merge_note}` : ""}`).join("\n");
  const overview = `这个提交是 ${verdicts.length} 个开着的 PR 的 head(检查挂在提交上,全都放行才放行):\n${list}`;
  return {
    ...pick.r,
    title: `PR #${pick.number}:${pick.r.title}`,
    // GitHub 会截断长摘要；逐 PR 的轮数/停信号先写，不能被某个 PR 的长详情挤掉。
    summary: verdicts.some((v) => v.r.round_line || v.r.merge_note)
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

// 同一运行重读整份事实，不能只重试最后一次写操作或沿用旧授权。
export const MAX_STATE_READS = 8;
// 单次 1 秒等 8 次常常赶不上 GitHub 后台计算；指数退避，总等待约一分半。
export const retryDelay = (attempt) => Math.min(30000, 1000 * 2 ** attempt);
export async function gate(options) {
  const wait = options.waitForState ?? ((attempt) => new Promise(resolve => setTimeout(resolve, retryDelay(attempt))));
  const syncing = new Set();
  // 占位检查在整次运行内复用：重读不重复新建，还没有最终结论的占位在下一轮收集前收尾。
  // done 表示这条检查当前已写成 completed；finalized 表示本次运行曾写成 completed，
  // 即使合并遇到瞬时状态把当前结论改成进行中，也不能在收尾时改写成失败。
  const placeholders = new Map();
  for (let attempt = 0; attempt < MAX_STATE_READS; attempt++) {
    const {results, retry} = await gateAttempt(options, syncing, placeholders);
    if (!retry || attempt === MAX_STATE_READS - 1) return results;
    await wait(attempt);
  }
}
// 只收尾本次运行从未写出最终结论、又已经不在开放列表里的占位，不留 in_progress。
// 曾经写成 completed 的检查（例如本轮已放行并合并的提交）不能被收尾改写成失败。
async function finishLeftovers(poster, placeholders, keep = new Set()) {
  for (const [sha, holder] of [...placeholders]) {
    if (keep.has(sha) || holder.finalized) continue;
    try { await poster.finish(sha, moved, holder.id); placeholders.delete(sha); } catch {}
  }
}
const pendingState = e => ({status:'in_progress',conclusion:null,title:'状态正在变化，重读后继续',
  summary:`${e.message}；当前快照不再用于授权写入，不是数据读取失败。本次运行会重读事实；若持续变化超过重读预算，保留进行中，后续门铃继续核实。`});

async function gateAttempt({ repo, policy, api, poster, bindingApi = api, merger = null, synchronizer = null, log = () => {} }, syncing, placeholders = new Map()) {
  const errors = [];
  let retry = false;
  // 1. 所有开着的 PR,按 head 提交分组
  const heads = new Map();
  for (const { number, sha } of await openPrs(api, repo)) {
    if (typeof sha !== "string" || !SHA_RE.test(sha)) throw new Error(`PR #${number} 的 head 不是提交号`);
    if (!heads.has(sha)) heads.set(sha, []);
    heads.get(sha).push(number);
  }
  validatePolicy(policy);

  // 2. 先给每个 head 发 App 占位,之后才读 PR 的数据；同一次运行的重读复用已有占位。
  const ids = new Map();
  for (const sha of heads.keys()) {
    try {
      if (!placeholders.has(sha)) placeholders.set(sha, { id: await poster.start(sha), done: false, finalized: false });
      ids.set(sha, placeholders.get(sha).id);
    } catch (e) {
      errors.push(e);
    }
  }
  // 重读后已经不在开放列表里的 head(推进/关闭)先收尾，不能留 in_progress，也不盖住本轮新 head 的结论。
  await finishLeftovers(poster, placeholders, new Set(heads.keys()));

  // 3. 每个 head:以它为 head 的 PR 全判一遍,合成一个结论写一次
  const results = [];
  for (const [sha, numbers] of heads) {
    const holder = placeholders.get(sha);
    if (!ids.has(sha) || holder?.done) continue;
    let result;
    let syncReady = false;
    const verdicts = [];
    try {
      for (const n of numbers) {
        const facts = await collect(api, repo, n, policy, bindingApi);
        if (facts.pr.state !== "open") continue;
        if (facts.pr.head_sha !== sha) throw new TransientPrState('列出 PR 后 head 已推进');
        let r;
        try {
          r = decide(facts, policy);
        } catch (e) {
          r = g8(`判定出错:${e.message}`);
        }
        if (facts.merge_request && !facts.merge_request.bound) {
          const merge_note = facts.merge_request.reason;
          r = { ...r, merge_note, summary: `${merge_note}\n\n${r.summary}` };
        }
        verdicts.push({ number: n, r, facts, request: facts.merge_request, mergeBy: mergeRequester(facts, policy) });
      }
      result = verdicts.length ? combine(verdicts) : moved;
      if (synchronizer && result.status === 'completed' && result.conclusion === 'success') {
        for (const v of verdicts) {
          if (!v.mergeBy && !v.r.direct_merge?.ok) continue;
          v.sync = syncing.has(`${v.number}:${sha}`)
            ? {note:'同步请求已接受，等待实际 head 变化后重算。'}
            : await synchronizer.prepare(v.number, v.facts);
        }
        const plans = verdicts.filter(v=>v.sync);
        if (plans.length) {
          const conflict=plans.some(v=>v.sync.conflict);
          syncReady = !conflict;
          result={...result,status:conflict?'completed':'in_progress',conclusion:conflict?'failure':null,
            title:conflict?'不同步：main 有冲突':'自动同步 main，等新 head CI',
            summary:plans.map(v=>`PR #${v.number}：${v.sync.note}`).join('\n')+'\n\n'+result.summary};
        }
      }
    } catch (e) {
      syncReady = false;
      if (e instanceof TransientPrState) { retry = true; result = pendingState(e); }
      else result = g8(e.message);
    }
    try {
      await poster.finish(sha, result, ids.get(sha));
      holder.done = result.status === 'completed';
      holder.finalized ||= holder.done;
    } catch (e) {
      errors.push(e);
      continue;
    }
    log(`${sha.slice(0, 7)}:${result.title}\n${result.summary}`);
    // 意向和同步都在本轮结论成功写回后执行；同步 head 留给下一轮重新收集。
    // 同步失败只影响对应 PR：不改共享放行的 G1–G8 结论，也不挡同 head 其他 PR 的合并。
    const syncNotes = [];
    const syncFailed = new Set();
    for (const v of (syncReady ? verdicts.filter(v=>v.sync?.intent) : [])) {
      try {
        await synchronizer.apply(v.sync.intent);
        syncing.add(`${v.number}:${sha}`);
      }
      catch (e) {
        syncFailed.add(v.number);
        if (e instanceof TransientPrState) {
          retry = true;
          result = pendingState(e);
          syncNotes.push(`PR #${v.number} 自动同步遇到瞬时状态，本轮回读：${e.message}`);
        } else {
          syncNotes.push(`PR #${v.number} 自动同步未完成，这一轮不合并它：${e.message}`);
        }
        log(`PR #${v.number}:自动同步没成:${e.message}`);
      }
    }
    if (syncNotes.length) result={...result,
      title:`${result.title}；自动同步未完成`,summary:syncNotes.join('\n')+'\n\n'+result.summary};
    // 4. 合并:只在这个提交上的 App 放行结论写上了的时候;
    //    合并拒绝是逐 PR 的执行结果，不改变共享 head 的放行判定。
    const mergeResult = result;
    const mergeNotes = [];
    for (const v of verdicts) {
      if (v.request && !v.mergeBy) {
        log(`PR #${v.number}:${v.request.reason}`);
      }
      // 两条合并路径:可信的合并标签请求,或普通 PR 当前 head 干净、只有够数合格 PASS 时由关卡直接合并。
      // 后者不进 merge_request,也不产生合并授权;放行与直接合并条件都由 decide() 判。
      const direct = !v.mergeBy && v.r.direct_merge?.ok === true;
      if ((!v.mergeBy && !direct) || syncFailed.has(v.number) || result.status !== "completed" || result.conclusion !== "success") continue;
      const how = v.mergeBy ? `按 ${v.mergeBy} 的请求` : "按目标家数直接";
      try {
        if (!merger) throw new Error("没有合并接口");
        await merger.merge(v.number, sha, v.facts.pr);
        log(`PR #${v.number}:${how}合并了 ${sha.slice(0, 7)}`);
      } catch (e) {
        if (e instanceof TransientPrState) {
          retry = true;
          result = pendingState(e);
        } else {
          mergeNotes.push(v.mergeBy
            ? `PR #${v.number} 合并被拒，合并请求保留：${e.message}`
            : `PR #${v.number} 直接合并未完成：${e.message}`);
        }
        log(`PR #${v.number}:${how}合并 ${sha.slice(0, 7)} 没成:${e.message}`);
      }
    }
    // 先尝试完该 head 上的合并，再补拒绝摘要，不能提前写坏共享必需检查。
    if (syncNotes.length || mergeNotes.length || result !== mergeResult) {
      if (mergeNotes.length) result={...result,
        title:`${result.title}；合并未完成`,summary:mergeNotes.join('\n')+'\n\n'+result.summary};
      try {
        await poster.finish(sha, result, ids.get(sha));
        holder.done = result.status === 'completed';
        holder.finalized ||= holder.done;
      } catch (e) { errors.push(e); }
    }
    results.push({ sha, title: result.title, summary: result.summary });
  }
  if (errors.length) throw errors[0];
  return {results, retry};
}
