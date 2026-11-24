// Policy schema; bin/_aiwork_config.py consumes the same fixture cases.
export function builderFamilies(policy) {
  const builders = policy?.builders;
  const fail = () => { throw new Error('policy builders: invalid or ambiguous registration'); };
  if (!builders || typeof builders !== 'object' || Array.isArray(builders) || !Object.keys(builders).length) fail();
  const values = Object.values(builders);
  const structured = values.every(v => v && typeof v === 'object' && !Array.isArray(v));
  const legacy = values.every(v => typeof v === 'string');
  if (!structured && !legacy) fail();
  const logins = new Set(), families = new Set(), roles = new Set();
  return Object.fromEntries(Object.entries(builders).map(([login, entry]) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9-]*(?:\[bot\])?$/.test(login) || logins.has(login.toLowerCase())) fail();
    logins.add(login.toLowerCase());
    const family = structured ? entry.family : entry;
    if (typeof family !== 'string' || !/^[a-z][a-z0-9-]*$/.test(family)) fail();
    if (structured) {
      if (Object.keys(entry).sort().join(',') !== 'family,role' || !login.endsWith('[bot]') ||
          typeof entry.role !== 'string' || !/^build-[a-z0-9][a-z0-9-]*$/.test(entry.role) ||
          families.has(family) || roles.has(entry.role)) fail();
      families.add(family); roles.add(entry.role);
    }
    return [login, family];
  }));
}
