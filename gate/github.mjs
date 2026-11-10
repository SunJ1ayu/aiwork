// GitHub 的请求、分页和 GraphQL 接线共用一处；令牌由各入口按角色传入。
export function githubClient(env = process.env) {
  const API = env.GITHUB_API_URL || "https://api.github.com";
  const TIMEOUT_MS = Number(env.AIWORK_GATE_TIMEOUT_MS) || 30_000;
  async function request(method, url, token, body) {
    const res = await fetch(url.startsWith("http") ? url : `${API}${url}`, {
      method,
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "aiwork-gate",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${url} → HTTP ${res.status}:${text.slice(0, 300)}`);
    return { data: text ? JSON.parse(text) : null, link: res.headers.get("link") };
  }

  const reader = token => ({
    async get(path) {
      return (await request("GET", path, token)).data;
    },
    async getPage(path) {
      const { data, link } = await request("GET", path, token);
      const m = /<([^>]+)>;\s*rel="next"/.exec(link ?? "");
      return { data, next: m ? m[1] : null };
    },
    // REST 不给的(评审改写时间)才走 GraphQL;有 errors 就当读失败
    async graphql(query, variables) {
      const { data } = await request("POST", env.GITHUB_GRAPHQL_URL || `${API}/graphql`, token, { query, variables });
      if (data?.errors?.length) throw new Error(`GraphQL:${data.errors.map((e) => e.message).join(";").slice(0, 300)}`);
      return data?.data;
    },
  });

  return { request, reader };
}
