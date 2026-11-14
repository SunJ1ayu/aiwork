// 标签载荷没有标签事件 ID；以版本冻结的载荷时间、申请人和 PR 对应历史。
// 同一秒摘贴会有歧义，读取时拒绝整秒，不能把旧载荷套到新的一次申请上。
export const MERGE_BINDING_CHECK = "aiwork-merge-request";
export const isMergeRequester = (by, policy) => typeof by === "string" &&
  (by === policy.owner || policy.merge_requesters.includes(by));
export const mergeBindingKey = (number, label, at, by) => JSON.stringify([number, label, at, by]);

export function bindingFromEvent(eventName, event, repo, policy) {
  const pr = event?.pull_request;
  const by = event?.sender?.login;
  if (eventName !== "pull_request_target" || event?.action !== "labeled" ||
      event?.repository?.full_name !== repo || pr?.base?.repo?.full_name !== repo ||
      event?.label?.name !== policy.merge_label ||
      !Number.isSafeInteger(pr?.number) || pr.number <= 0 ||
      !/^[0-9a-f]{40}$/.test(pr?.head?.sha ?? "") ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(pr?.updated_at ?? "") ||
      !isMergeRequester(by, policy)) return null;
  return {
    name: MERGE_BINDING_CHECK, head_sha: pr.head.sha,
    external_id: mergeBindingKey(pr.number, policy.merge_label, pr.updated_at, by),
    status: "completed", conclusion: "neutral",
    output: { title: "合并申请对应的提交", summary: `PR #${pr.number}：仅授权贴标签事件中的提交 ${pr.head.sha}。` },
  };
}
