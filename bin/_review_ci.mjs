// 只桥接共享选择器；不联网、不读令牌、不重新定义选择或判定规则。
import { readFileSync } from "node:fs";
import { orderedCiRuns, selectCiRun } from "../gate/collect.mjs";
const { runs, head, policy, number } = JSON.parse(readFileSync(0, "utf8"));
const run = number === null ? orderedCiRuns(runs, head, policy)[0] ?? null
                           : selectCiRun(runs, head, policy, number).run;
process.stdout.write(JSON.stringify({ run }));
