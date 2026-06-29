# Model Configuration

如何让 Pi 使用和 Claude Code 相同的模型和代理。

## 背景

Pi 内置了 15+ provider 的模型列表，但 Anthropic provider 的 base URL 是硬编码的 `https://api.anthropic.com`，不支持 `ANTHROPIC_BASE_URL` 环境变量。

Claude Code 走的是 `cc-switch`，这是 DeepSeek 的一个本地代理，监听在 `127.0.0.1:15721`。它完整实现了 Anthropic Messages API，对签名、thinking、tool use 等特性的代理都很到位。

让 Pi 也走这个代理，只需要用 Pi 的 `models.json` 覆盖 Anthropic 的 base URL。

## models.json

```json
{
  "providers": {
    "anthropic": {
      "baseUrl": "http://host.docker.internal:15721"
    }
  }
}
```

就这一行。不需要 `compat`、不需要 `api`、不需要 `apiKey`。因为 cc-switch 对 Anthropic API 的代理做得很完整，Pi 可以直接按原生 Anthropic 的方式跟它对话，不需要关掉任何特性。

- `baseUrl` 只覆盖 API 地址，内置的 50+ Anthropic 模型全部保留
- `host.docker.internal` 是 Docker 自动解析的特殊域名，指向 Colima VM 的网关，最终转发到 macOS 宿主机
- `apiKey` 和 `api` 字段不需要写，Pi 沿用内置的 anthropic-messages API 类型

## API Key

cc-switch 不验证 `x-api-key` 头，任意值都行：

```bash
-e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-any}"
```

真正的 API key 由 cc-switch 持有，容器内的 Pi 不知道真实密钥。这是个安全优势：即使容器被攻破，也无法泄露 API key。

## 代理的抽象价值

Pi 只认 `http://host.docker.internal:15721`，完全不知道也不关心 cc-switch 背后是什么。cc-switch 负责把 Anthropic Messages API 的请求转发到实际的模型后端——当前是 DeepSeek。

**切换后端只需改 cc-switch 的配置，Pi 这边零改动。** 比如将来 cc-switch 把后端从 DeepSeek 切到另一个模型，Pi 还是照常发请求到同一个地址，一切透明。这也是为什么 `models.json` 里只需要一行 `baseUrl`——所有复杂性都在代理那一层处理掉了。

同样的逻辑也适用于 Claude Code：它和 Pi 共享同一个代理，所以两者始终用同一个后端模型，不会出现一边是 DeepSeek 另一边是别的模型的情况。

## settings.json

```json
{
  "model": "claude-opus-4-8",
  "provider": "anthropic",
  "thinkingLevel": "xhigh"
}
```

`claude-opus-4-8` 是 cc-switch 路由的内部名称，Claude Code 的 settings.json 里也是这个名字。

## 网络链路

```
Pi 容器                     Colima VM                macOS 宿主机
───────                    ─────────                ───────────
models.json →              Docker 网络              cc-switch (PID 873)
host.docker.internal       共享模式                  127.0.0.1:15721
:15721                     → 网关 192.168.5.2       → DeepSeek API
```

`--cap-drop ALL` 不影响 HTTP 连接——TCP socket 不需要任何 Linux capability。

## 换模型

临时换：`pi --model "claude-sonnet-4-6"`

永久换：改 `settings.json` 里的 `model` 字段，或通过 Pi 的交互式 `/model` 命令。

Pi 对模型名做模糊匹配，`claude-sonnet-4-6` 会匹配到内置模型列表里的对应模型。

## 关于其他 Provider

cc-switch 做的是 Anthropic Messages API 的代理。如果要给 Pi 加 OpenAI、DeepSeek 等其他 provider，需要提供真实的 API key（通过 `auth.json` 或环境变量），走对应 provider 的官方 API 地址，不走这个代理。

## 升级后的注意事项

每次 `docker build --no-cache` 重建镜像后，`models.json` 和 `settings.json` 都在 `pi-data` 卷里不受影响，无需重新配置。
