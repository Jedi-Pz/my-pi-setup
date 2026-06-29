# Model Configuration

如何让 Pi 使用和 Claude Code 相同的模型和代理。

## 背景

Pi 内置了 15+ provider 的模型列表，但 Anthropic provider 的 base URL 是硬编码的 `https://api.anthropic.com`，不支持 `ANTHROPIC_BASE_URL` 环境变量。而 Claude Code 走的是本地代理 `cc-switch`，监听在 `127.0.0.1:15721`。

要让 Pi 也走这个代理，需要用 Pi 的 `models.json` 覆盖内置 provider 配置。

## models.json

Pi 支持通过 `~/.pi/agent/models.json` 覆盖内置 provider 的 base URL，**同时保留内置模型列表**：

```json
{
  "providers": {
    "anthropic": {
      "baseUrl": "http://host.docker.internal:15721",
      "compat": {
        "supportsEagerToolInputStreaming": false,
        "supportsLongCacheRetention": false,
        "supportsCacheControlOnTools": false,
        "allowEmptySignature": true
      }
    }
  }
}
```

- `baseUrl` 只覆盖 API 地址，内置的 50+ Anthropic 模型（Opus、Sonnet、Haiku 各版本）全部保留
- `host.docker.internal` 是 Docker 自动解析的特殊域名，指向 Colima VM 的网关，最终转发到 macOS 宿主机
- 不需要写 `apiKey` 和 `api` 字段，Pi 会沿用内置的 anthropic-messages API 类型

## API Key

代理 `cc-switch` 不验证 `x-api-key` 头，所以任意值都行。脚本里用了 `"any"`：

```bash
-e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-any}"
```

真正的 API key 由 cc-switch 持有，容器内的 Pi 根本不知道真实密钥。这是一个安全优势——即使容器被攻破，也无法泄露 API key。

## settings.json

默认模型和思考级别存在 `~/.pi/agent/settings.json`：

```json
{
  "model": "claude-opus-4-8",
  "provider": "anthropic",
  "thinkingLevel": "xhigh"
}
```

这里 `claude-opus-4-8` 是代理路由的内部名称，不是 Anthropic 的官方 model ID。Claude Code 的 settings.json 里也是这个名字。

## Compat 设置说明

代理不一定实现完整的 Anthropic Messages API，所以需要关掉一些特性：

| 字段 | 作用 | 为什么关 |
|------|------|---------|
| `supportsEagerToolInputStreaming` | 按工具启用流式输入 | 代理可能拒绝这个参数 |
| `supportsLongCacheRetention` | 长缓存 TTL (1h) | 代理可能不支持 |
| `supportsCacheControlOnTools` | 工具定义上的 cache_control | 代理可能不支持 |
| `allowEmptySignature` | 允许空的 thinking signature | 代理可能返回空签名，真 Anthropic 会拒绝 |

这些设置不影响模型能力，只影响 Pi 发出的 HTTP 请求格式。

## 网络链路

Pi 发送 API 请求经过三跳：

```
Pi 容器                     Colima VM                macOS 宿主机
───────                    ─────────                ───────────
models.json →              Docker 网络              cc-switch (PID 873)
host.docker.internal       共享模式                  127.0.0.1:15721
:15721                     → 网关 192.168.5.2       → 真实 Anthropic API
```

`--cap-drop ALL` 不影响 HTTP 连接——TCP socket 不需要任何 Linux capability。

## 换模型

临时换：`pi --model "claude-sonnet-4-6"`

永久换：改 `settings.json` 里的 `model` 字段，或通过 Pi 的交互式 `/model` 命令。

Pi 对模型名做模糊匹配，`claude-sonnet-4-6` 会匹配到内置模型列表里的对应模型。

## 关于其他 Provider

`cc-switch` 是 **Anthropic 专用代理**，不能转发 OpenAI/DeepSeek 等请求。如果要给 Pi 加其他 provider，需要提供真实的 API key（通过 `auth.json` 或环境变量），并且走那个 provider 的官方 API 地址，不走代理。

## 升级后的注意事项

每次 `docker build --no-cache` 重建镜像后，`models.json` 和 `settings.json` 都在 `pi-data` 卷里不受影响，无需重新配置。但如果 Pi 新版改了内置 provider 的配置格式，可能需要同步调整。
