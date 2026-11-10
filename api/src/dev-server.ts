// Local development server that serves the Vercel function files in /api
// with the same Web-standard (Request → Response) signature Vercel uses.
// Usage: pnpm dev   (listens on http://localhost:3001)

import 'dotenv/config';
import { createServer } from 'node:http';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.PORT ?? 3001);

type Handler = (req: Request) => Promise<Response> | Response;

createServer(async (nodeReq, nodeRes) => {
  const url = new URL(nodeReq.url ?? '/', `http://${nodeReq.headers.host ?? 'localhost'}`);
  const started = Date.now();
  try {
    if (!url.pathname.startsWith('/api/')) {
      nodeRes.writeHead(404, { 'Content-Type': 'application/json' }).end('{"error":{"message":"Not found"}}');
      return;
    }
    const file = join(root, `${url.pathname.replace(/\/$/, '')}.ts`);
    if (!existsSync(file)) {
      nodeRes.writeHead(404, { 'Content-Type': 'application/json' }).end('{"error":{"message":"Route not found"}}');
      return;
    }
    const mod = (await import(pathToFileURL(file).href)) as Record<string, Handler>;
    const fn = mod[nodeReq.method ?? 'GET'];
    if (!fn) {
      nodeRes.writeHead(405, { 'Content-Type': 'application/json' }).end('{"error":{"message":"Method not allowed"}}');
      return;
    }

    const chunks: Buffer[] = [];
    for await (const c of nodeReq) chunks.push(c as Buffer);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const headers = new Headers();
    for (const [k, v] of Object.entries(nodeReq.headers)) if (typeof v === 'string') headers.set(k, v);

    const res = await fn(
      new Request(url, { method: nodeReq.method, headers, body: ['GET', 'HEAD'].includes(nodeReq.method ?? '') ? undefined : body }),
    );
    nodeRes.writeHead(res.status, Object.fromEntries(res.headers.entries()));
    nodeRes.end(Buffer.from(await res.arrayBuffer()));
    console.log(`${nodeReq.method} ${url.pathname} → ${res.status} (${Date.now() - started} ms)`);
  } catch (err) {
    console.error(err);
    nodeRes.writeHead(500, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: { message: String(err) } }));
  }
}).listen(port, () => console.log(`ACME Control API (dev) listening on http://localhost:${port}`));
