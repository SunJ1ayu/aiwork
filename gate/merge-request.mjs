export const MERGE_BINDING_CHECK = "aiwork-merge-request";
export const isMergeRequester = (by, policy) => typeof by === "string" &&
  (by === policy.owner || policy.merge_requesters.includes(by));
export const mergeBindingKey = (number, label, head, by) => JSON.stringify([2, number, label, head, by]);

export function bindingFromEvent(eventName, event, repo, policy) {
  const pr = event?.pull_request;
  const by = event?.sender?.login;
  if (eventName !== "pull_request_target" || event?.action !== "labeled" ||
      event?.repository?.full_name !== repo || pr?.base?.repo?.full_name !== repo ||
      event?.label?.name !== policy.merge_label ||
      !Number.isSafeInteger(pr?.number) || pr.number <= 0 ||
      !/^[0-9a-f]{40}$/.test(pr?.head?.sha ?? "") ||
      !isMergeRequester(by, policy)) return null;
  return {
    name: MERGE_BINDING_CHECK, head_sha: pr.head.sha,
    external_id: mergeBindingKey(pr.number, policy.merge_label, pr.head.sha, by),
    status: "completed", conclusion: "neutral",
    output: { title: "合并申请对应的提交", summary: `PR #${pr.number}：仅授权贴标签事件中的提交 ${pr.head.sha}。` },
  };
}

// 授权来自通知中的提交，历史仅用来确认标签仍在、最后是谁贴的。
export function bindingIdentity(key, number, label, policy) {
  let v; try { v = JSON.parse(key); } catch { return null; }
  return Array.isArray(v) && v.length === 5 && v[0] === 2 && v[1] === number && v[2] === label &&
    /^[0-9a-f]{40}$/.test(v[3] ?? '') && isMergeRequester(v[4], policy) ? v[3] : null;
}

// 活动必须覆盖本次分支创建，推送链连续；返回曾授权的提交是否一直留到现在。
export function retainsAuthorization(history, current, source, synchronizations) {
  if (!Array.isArray(history) || !history.length) return false;
  const creation = history.findIndex(a => a.activity_type === 'branch_creation');
  if (creation < 0 || history[0].after !== current) return false;
  const life = history.slice(0, creation + 1);
  if (life.some(a => !['push','force_push','branch_creation'].includes(a.activity_type) ||
      !/^[0-9a-f]{40}$/.test(a.after ?? '') || !Number.isSafeInteger(a.id))) return false;
  if (new Set(life.map(a => a.id)).size !== life.length) return false;
  for (let i = 0; i < life.length - 1; i++) if (life[i].before !== life[i + 1].after) return false;
  // 连分支重建之前的同 SHA 也计入：旧检查不会随删分支而消失。
  if (history.filter(a => a.after === current).length !== 1 ||
      history.filter(a => a.after === source).length !== 1) return false;
  const arrival = life.findIndex(a => a.after === source);
  return arrival >= 0 && life.slice(0, arrival).every(a => synchronizations.get(a.id)?.unchanged === true);
}
