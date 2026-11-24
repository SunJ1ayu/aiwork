import { readFileSync } from 'node:fs';

function validateSchema(value, schema) {
  const keywords = new Set(['type', 'pattern', 'properties', 'required',
    'additionalProperties', 'propertyNames', 'x-caseInsensitiveKeys', 'x-uniqueValues']);
  const fail = () => { throw new Error('policy builders: invalid or ambiguous registration'); };
  if (!schema || typeof schema !== 'object' || Array.isArray(schema) || Object.keys(schema).some(k => !keywords.has(k))) fail();
  if (schema.type === 'string') {
    if (typeof value !== 'string') fail();
    if (Object.hasOwn(schema, 'pattern') && value.match(new RegExp(schema.pattern))?.[0] !== value) fail();
    return;
  }
  if (schema.type !== 'object' || !value || typeof value !== 'object' || Array.isArray(value)) fail();
  const keys = Object.keys(value);
  if ((schema.required ?? []).some(k => !Object.hasOwn(value, k))) fail();
  const properties = schema.properties ?? {};
  for (const [key,item] of Object.entries(value)) {
    if (schema.propertyNames) validateSchema(key, schema.propertyNames);
    const rule = Object.hasOwn(properties, key) ? properties[key] : (schema.additionalProperties ?? true);
    if (rule === false) fail();
    if (typeof rule === 'object') validateSchema(item, rule);
  }
  if (schema['x-caseInsensitiveKeys'] && new Set(keys.map(k => k.toLowerCase())).size !== keys.length) fail();
  for (const field of schema['x-uniqueValues'] ?? []) {
    if (new Set(Object.values(value).map(item => item[field])).size !== keys.length) fail();
  }
}

export function builderFamilies(policy) {
  const builders = policy?.builders;
  if (!builders || typeof builders !== 'object' || Array.isArray(builders) || !Object.keys(builders).length) {
    throw new Error('policy builders: nonempty object required');
  }
  // Old projects retain opaque string values and their existing author results.
  if (Object.values(builders).every(v => typeof v === 'string')) return {...builders};
  const schema = JSON.parse(readFileSync(new URL('../.aiwork/builder-schema.json', import.meta.url), 'utf8'));
  validateSchema(builders, schema);
  return Object.fromEntries(Object.entries(builders).map(([login, entry]) => [login, entry.family]));
}
