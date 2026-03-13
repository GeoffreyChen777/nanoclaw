---
name: support-alibaba-code-plan
description: Configure NanoClaw to work with Alibaba DashScope Coding Plan and other Anthropic-compatible upstream URLs behind the host-side credential proxy. Use when ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY, and ANTHROPIC_MODEL must work through NanoClaw's proxy, especially when the upstream URL includes a base path like /apps/anthropic.
---

# Support Alibaba Code Plan

Use this skill when NanoClaw should work with Alibaba DashScope Coding Plan or another Anthropic-compatible upstream URL while keeping the host-side credential proxy design.

## Required Configuration

Set `.env` with the provider values:

```bash
ANTHROPIC_BASE_URL=https://coding.dashscope.aliyuncs.com/apps/anthropic
ANTHROPIC_AUTH_TOKEN=...
ANTHROPIC_MODEL=...
```

Optional:

```bash
ANTHROPIC_DEFAULT_HAIKU_MODEL=...
```

If `ANTHROPIC_DEFAULT_HAIKU_MODEL` is omitted, NanoClaw may fall back to `ANTHROPIC_MODEL`.

## Required Code Behavior

Keep the current proxy architecture:

- `src/container-runner.ts` should point the container to `http://host.docker.internal:<port>`
- the container should receive placeholder auth, not the real secret
- `src/credential-proxy.ts` should read the real host credential from `.env`
- the proxy should inject the real auth when forwarding upstream

For upstream URLs with a base path such as `/apps/anthropic`, the proxy must preserve that path prefix.

Example:

- configured upstream:
  - `https://coding.dashscope.aliyuncs.com/apps/anthropic`
- incoming request from Claude Code:
  - `/v1/messages?beta=true`
- forwarded upstream request:
  - `/apps/anthropic/v1/messages?beta=true`

Implement this in `src/credential-proxy.ts` by building the upstream path as:

```text
upstream base path + request path + request query
```

Do not forward `req.url` directly when the configured upstream URL contains a pathname.

## Relevant Files

- `src/credential-proxy.ts`
- `src/credential-proxy.test.ts`
- `src/container-runner.ts`
- `container/agent-runner/src/index.ts`

## Validation Workflow

### 1. Check env values

Verify `.env` contains:

- `ANTHROPIC_BASE_URL`
- one credential:
  - `ANTHROPIC_AUTH_TOKEN`, or
  - `CLAUDE_CODE_OAUTH_TOKEN`, or
  - `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL`

### 2. Validate direct Claude Code in the container

Run Claude Code directly in `nanoclaw-agent:latest` with the real upstream values and a short prompt:

```text
Reply with exactly: PROXY_OK
```

Expected output:

```text
PROXY_OK
```

### 3. Validate NanoClaw through the host-side proxy

Run a live NanoClaw container-agent probe with the same prompt through the normal host-side credential proxy.

Expected output:

```text
PROXY_OK
```

### 4. Validate the proxy path rule

If the upstream URL includes a base path, add or keep a regression test in `src/credential-proxy.test.ts` that verifies:

- upstream base path is preserved
- auth injection still works

For example, a proxy request to:

```text
/v1/messages?beta=true
```

should arrive upstream as:

```text
/apps/anthropic/v1/messages?beta=true
```

## Success Criteria

The setup is complete when all of the following are true:

- direct Claude Code in the container returns `PROXY_OK`
- NanoClaw through the host-side proxy also returns `PROXY_OK`
- real credentials remain on the host side
- the proxy preserves any upstream base path

## Escalation

Escalate only if:

- direct Claude Code with the real upstream fails
- proxied requests still fail after base-path preservation is implemented
- Claude Code is using additional endpoints that the proxy does not forward correctly
