import {
  type ExecutionContext,
  type Fetcher,
  type WorkerVersionMetadata
} from "@cloudflare/workers-types/experimental"

interface Env {
  readonly ASSETS: Fetcher;
  readonly CF_VERSION_METADATA: WorkerVersionMetadata;
}

const CACHE_CONTROL = 'public, max-age=3600'
const SCRIPT_PATH = 'cursor-reset.ps1'

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)
    const cacheKey = this.createCacheKey(url.host, env.CF_VERSION_METADATA.id)
    const cache = caches.default

    const cachedResponse = await cache.match(cacheKey)
    if (cachedResponse) return cachedResponse

    const scriptResponse = await env.ASSETS.fetch(`https://${url.host}/${SCRIPT_PATH}?version=${env.CF_VERSION_METADATA.id}`)
    if (!scriptResponse.ok) {
      return new Response('Not Found', { status: 404 })
    }

    const scriptContent = await scriptResponse.text()
    const response = this.createResponse(scriptContent)

    ctx.waitUntil(cache.put(cacheKey, response.clone()))
    return response
  },

  createCacheKey(host: string, versionId: string): Request {
    return new Request(
      `https://${host}/${SCRIPT_PATH}?version=${versionId}`
    )
  },

  createResponse(content: string): Response {
    return new Response(content, {
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': CACHE_CONTROL,
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff'
      }
    })
  }
}
