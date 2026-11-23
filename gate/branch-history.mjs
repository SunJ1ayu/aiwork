// 作者、同步证明和授权连续性共用分支活动的分类、排序及生命周期边界。
const CREATION = "branch_creation";
const DELETION = "branch_deletion";
const PUSH_TYPES = new Set(["push", "force_push", CREATION]);

export function branchHistory(activities) {
  const all = [...activities].sort((a, b) =>
    a.timestamp === b.timestamp ? b.id - a.id : a.timestamp < b.timestamp ? 1 : -1,
  );
  const life = [];
  let complete = false;
  for (const activity of all) {
    if (activity.activity_type === DELETION) break;
    life.push(activity);
    if (activity.activity_type === CREATION) { complete = true; break; }
  }
  return {
    all, life,
    pushes: life.filter(activity => PUSH_TYPES.has(activity.activity_type)),
    complete,
  };
}
