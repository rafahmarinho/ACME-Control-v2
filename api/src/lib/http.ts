import { ZodError, type ZodType } from 'zod';

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public code = 'error',
  ) {
    super(message);
  }
}

function corsHeaders(req?: Request): Record<string, string> {
  const allowed = (process.env.ALLOWED_ORIGINS ?? '*')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const origin = req?.headers.get('origin') ?? '';
  const allowOrigin = allowed.includes('*') ? '*' : allowed.includes(origin) ? origin : allowed[0] ?? '';
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

export function json(data: unknown, status = 200, req?: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...corsHeaders(req) },
  });
}

export function preflight(req: Request): Response {
  return new Response(null, { status: 204, headers: corsHeaders(req) });
}

export async function readBody<T>(req: Request, schema: ZodType<T>): Promise<T> {
  let raw: unknown = {};
  try {
    const text = await req.text();
    raw = text ? JSON.parse(text) : {};
  } catch {
    throw new ApiError(400, 'Request body must be valid JSON.', 'invalid_json');
  }
  return schema.parse(raw);
}

/** Wraps a handler with CORS, JSON errors and validation error mapping. */
export function handler(fn: (req: Request) => Promise<Response | unknown>) {
  return async (req: Request): Promise<Response> => {
    try {
      const result = await fn(req);
      return result instanceof Response ? result : json(result, 200, req);
    } catch (err) {
      if (err instanceof ApiError) {
        return json({ error: { code: err.code, message: err.message } }, err.status, req);
      }
      if (err instanceof ZodError) {
        const message = err.issues.map((i) => `${i.path.join('.') || 'body'}: ${i.message}`).join('; ');
        return json({ error: { code: 'validation_error', message } }, 422, req);
      }
      console.error('[api] unexpected error', err);
      const message = err instanceof Error ? err.message : 'Unexpected server error';
      return json({ error: { code: 'internal_error', message } }, 500, req);
    }
  };
}
