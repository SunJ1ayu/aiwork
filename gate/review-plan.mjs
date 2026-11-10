// 分档、目标和派腿顺序只从项目 main 策略读取；旧项目保持已有关卡底线。
import { matchAny } from './paths.mjs';

export function validateReviewPolicy(policy) {
  if (!policy || !Object.hasOwn(policy, 'review_dispatch')) return;
  const config = policy.review_dispatch;
  const strings = value => Array.isArray(value) && value.length > 0 &&
    value.every(item => typeof item === 'string' && item.length > 0);
  const minimum = config?.minimum_families;
  const minima = { documentation: minimum, code: minimum, high: policy.high_min_families };
  if (!config || !Number.isSafeInteger(minimum) || minimum < 1 || minimum > policy.high_min_families ||
      !strings(config.documentation_paths) || !strings(config.order) ||
      new Set(config.order).size !== config.order.length ||
      !config.order.every(leg => /^sub[a-z][a-z0-9-]*$/.test(leg)) ||
      !Array.isArray(config.high_only) || !config.high_only.every(leg => config.order.includes(leg)) ||
      !Object.entries(minima).every(([tier, count]) =>
        Number.isSafeInteger(config.targets?.[tier]) && config.targets[tier] >= count)) {
    throw new Error('.aiwork/policy.json review_dispatch 不合法');
  }
}

export function reviewPlan(files, policy) {
  validateReviewPolicy(policy);
  const config = policy.review_dispatch;
  const high = files.some(file => matchAny(policy.high, file));
  const documentation = Boolean(config && files.length && files.every(file =>
    matchAny(config.documentation_paths, file) && !matchAny(policy.judging_surface, file)));
  const tier = high ? 'high' : documentation ? 'documentation' : 'code';
  const g3_minimum = config?.minimum_families ?? 1;
  const minimum = high ? policy.high_min_families : g3_minimum;
  return {
    tier, minimum, g3_minimum, target: config ? config.targets[tier] : minimum,
    order: config ? config.order.filter(leg => high || !config.high_only.includes(leg)) : [],
  };
}
