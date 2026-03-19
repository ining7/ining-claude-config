# Chrome MCP 完整指南：从原理到多会话修复

## 1. MCP 是什么

MCP（Model Context Protocol）是 Anthropic 提出的开放协议，用于让 LLM（如 Claude）与外部工具/数据源进行标准化通信。

核心概念：
- **MCP Server**：提供工具能力的服务端（如浏览器控制、数据库查询等）
- **MCP Client**：调用工具的客户端（即 Claude Code）
- **传输层（Transport）**：Client 与 Server 之间的通信方式

类比理解：MCP 之于 LLM，类似于 USB 协议之于电脑 — 定义了一套标准接口，任何符合协议的设备（工具）都能即插即用。

## 2. 传输模式

MCP 支持两种传输模式：

| 模式 | 原理 | 生命周期 | 多会话支持 |
|------|------|----------|-----------|
| **stdio** | Claude Code 启动一个子进程，通过 stdin/stdout 通信 | 每个会话独立启动/销毁进程 | 天然支持，互不干扰 |
| **HTTP (SSE)** | Claude Code 连接到一个已运行的 HTTP 服务 | 需要外部预先启动服务 | 取决于 Server 实现，可能不支持多客户端 |

**选择建议**：优先使用 stdio 模式，因为它不需要手动管理服务进程，且天然支持多会话并发。

## 3. Chrome MCP 是什么

Chrome MCP 让 Claude Code 能控制和读取用户的 Chrome 浏览器，核心能力：
- 列出所有窗口和标签页
- 读取任意标签页的网页内容（包含已登录的认证页面）
- 模拟键盘/鼠标操作（导航、点击、输入等）
- 截图

典型场景：访问需要登录的内部系统（Confluence、GitLab、Jira 等），无需提供 cookie 或 token。

### 与 WebFetch 的对比

| 场景 | Chrome MCP | WebFetch |
|------|-----------|----------|
| 公开网页 | 可用 | 可用 |
| 需要登录的页面 | 可用（复用浏览器 session） | 不可用（被重定向到登录页） |
| 是否需要 Chrome 运行 | 是 | 否 |
| 是否产生本地临时文件 | 否 | 否 |
| 上下文占用 | 较少（直接提取文本） | 可能较多（HTML → markdown 转换） |

## 4. 组件架构

```
Claude Code (MCP Client)
    ↕ stdio (stdin/stdout)
mcp-chrome-stdio (Node.js, 每个会话一个进程)
    ↕ StreamableHTTP (HTTP POST to 127.0.0.1:12306/mcp)
mcp-chrome-bridge (Node.js HTTP Server, Chrome 扩展通过 Native Messaging 启动)
    ↕ Chrome Native Messaging
Chrome Extension (浏览器内运行)
    ↕ Chrome DevTools Protocol
Chrome Browser (标签页内容)
```

关键细节：
- **mcp-chrome-bridge** 由 Chrome 扩展通过 Native Messaging 自动启动，监听 `127.0.0.1:12306`
- **mcp-chrome-stdio** 是每个 Claude Code 会话的 stdio 子进程，它内部通过 StreamableHTTP 协议连接到 bridge
- 即使配置为 stdio 模式，底层仍然依赖 bridge 的 HTTP 服务
- Bridge 进程的父进程是 Chrome，不是 Claude Code

涉及的组件：
- **Chrome 扩展**：安装在 Chrome 中，提供浏览器端能力（项目：[hangwin/mcp-chrome](https://github.com/hangwin/mcp-chrome)）
- **mcp-chrome-bridge**：npm 全局包，作为 Node.js MCP Server，桥接 Claude Code 与 Chrome 扩展

## 5. 安装步骤

### 5.1 安装 Chrome 扩展

从 [GitHub Release](https://github.com/hangwin/mcp-chrome/releases) 安装 Chrome MCP Server 扩展。安装后 Chrome 扩展栏会出现图标，点击可打开 welcome 页面确认状态。

### 5.2 安装 Node.js 桥接

```bash
npm i -g mcp-chrome-bridge
```

安装后自动注册 Chrome Native Messaging Host：
- **macOS**：`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- **Linux**：`~/.config/google-chrome/NativeMessagingHosts/`
- **Windows**：`%APPDATA%\Google\Chrome\NativeMessagingHosts\`

前置要求：Node.js >= 20。

### 5.3 在 Claude Code 中配置 MCP

```bash
# 全局生效（所有项目目录下的 Claude Code 会话都能使用）
claude mcp add chrome-mcp-server -s user -- mcp-chrome-stdio
```

生成的配置位于 `~/.claude.json` 顶层：
```json
{
  "mcpServers": {
    "chrome-mcp-server": {
      "type": "stdio",
      "command": "mcp-chrome-stdio",
      "args": [],
      "env": {}
    }
  }
}
```

## 6. 多会话并发 Bug 与修复

### 6.1 问题现象

当同时打开多个 Claude Code 会话时，只有第一个会话能正常使用 Chrome MCP，其余会话全部报错：

```
Error calling tool: Failed to connect to MCP server
```

Bridge 端返回 500：

```
Already connected to a transport. Call close() before connecting to a new transport,
or use a separate Protocol instance per connection.
```

### 6.2 根因分析

`mcp-chrome-bridge` 的 `mcp-server.js` 中 `getMcpServer()` 使用**单例模式**：

```javascript
// mcp-server.js（原始代码）
exports.mcpServer = null;
const getMcpServer = () => {
    if (exports.mcpServer) {
        return exports.mcpServer;  // 始终返回同一个实例
    }
    exports.mcpServer = new Server({ name: 'ChromeMcpServer', version: '1.0.0' }, ...);
    setupTools(exports.mcpServer);
    return exports.mcpServer;
};
```

而 MCP SDK 的 `Server` 类继承自 `Protocol`，其 `connect()` 方法**不允许对同一实例绑定多个 transport**：

```javascript
// @modelcontextprotocol/sdk - protocol.js
async connect(transport) {
    if (this._transport) {
        throw new Error('Already connected to a transport...');
    }
    this._transport = transport;
    // ...
}
```

在 `server/index.js` 中，每个新的 StreamableHTTP 连接和 SSE 连接都会调用 `getMcpServer().connect(transport)`，第二次调用就会触发上述错误。

**影响范围**：无论使用 stdio 还是 HTTP 模式都会触发，因为 stdio 模式底层也通过 HTTP 连接到同一个 bridge。

### 6.3 修复方案

核心思路：新增 `createMcpServer()` 函数，为每个连接创建独立的 Server 实例。

**修改文件 1：`mcp-server.js`**

新增 `createMcpServer` 导出函数：

```javascript
// 新增：每个连接创建独立 Server 实例
const createMcpServer = () => {
    const server = new Server({
        name: 'ChromeMcpServer',
        version: '1.0.0',
    }, {
        capabilities: { tools: {} },
    });
    setupTools(server);
    return server;
};
exports.createMcpServer = createMcpServer;
```

**修改文件 2：`server/index.js`**

新增引用：
```javascript
const mcp_server_multi_1 = { createMcpServer: mcp_server_1.createMcpServer };
```

将两处 `getMcpServer().connect(transport)` 改为 `createMcpServer()`：

- SSE 端点（`/sse`）：
  ```javascript
  // 原：const server = (0, mcp_server_1.getMcpServer)();
  const server = (0, mcp_server_multi_1.createMcpServer)();
  ```

- StreamableHTTP 端点（`/mcp`）：
  ```javascript
  // 原：await (0, mcp_server_1.getMcpServer)().connect(transport);
  await (0, mcp_server_multi_1.createMcpServer)().connect(transport);
  ```

### 6.4 安全性与资源审查

| 维度 | 评估 |
|------|------|
| **资源泄漏** | 无。StreamableHTTP transport 有完善的 `onclose` 清理链（transport close → Protocol `_onclose()` 清理 handlers/controllers → `_transport = undefined` → GC 回收 Server 实例） |
| **安全性** | 无新增风险。未改变 CORS 策略、端口暴露范围、认证逻辑。`createMcpServer()` 注册的 tools 与原单例完全一致 |
| **并发上限** | 理论无限制。每个连接的 Server 实例内存开销极小（几个 Map 和 handler 函数），日常 < 10 个会话完全没有问题 |
| **`setupTools` 共享状态** | 安全。所有 handler 调用的是全局单例 `native_messaging_host`（Native Messaging Host），无 per-server 状态 |

### 6.5 注意事项

- 这是对 npm 全局包的本地 patch，`npm update -g mcp-chrome-bridge` 会覆盖修改
- 建议向上游提 issue/PR：https://github.com/hangwin/mcp-chrome
- 可使用下一节的自动 patch 脚本在更新后重新应用

## 7. 自动 Patch 脚本

为了让修复可复用（自己升级后重新应用、分享给他人），提供自动化脚本：

```bash
# 使用方法：
bash /Users/yining/mcp_chrome/patch-multi-session.sh
```

脚本功能：
1. 自动定位 `mcp-chrome-bridge` 的安装路径
2. 检查是否已经 patch 过
3. 备份原始文件
4. 应用多会话修复
5. 重启 bridge 进程使修改生效

## 8. 配置层级与优先级

Claude Code 的 MCP 配置有三个层级（优先级从高到低）：

1. **project 级别**：`~/.claude.json` 中 `projects["/path/to/dir"].mcpServers`，仅在对应目录下生效
2. **user 级别**：`~/.claude.json` 顶层 `mcpServers`，全局生效
3. **`.mcp.json` 文件**：项目根目录下的 `.mcp.json`

**关键：** 如果同名 MCP server 同时存在于 project 和 user 级别，project 级别会覆盖 user 级别。排查问题时务必检查是否有残留的旧配置。

查看当前实际生效的配置：
```bash
claude mcp list
```

## 9. 使用前提

Chrome MCP 无需手动启动任何服务（stdio 模式下）。只需满足：
1. Chrome 浏览器打开，且 MCP 扩展处于启用状态
2. Claude Code 中已配置 `chrome-mcp-server`

启动 Claude Code 后会自动连接。访问网页时：
- **不需要**提前在浏览器打开目标页面
- 可通过 `chrome_computer` 在已有标签页中导航到目标 URL
- 用 `chrome_get_web_content` 提取页面文本内容

## 10. 常见问题排查

| 现象 | 原因 | 解决方法 |
|------|------|----------|
| `/mcp` 显示 `failed` | Chrome 未打开 / 扩展未启用 | 打开 Chrome，确认扩展启用 |
| `/mcp` 显示 `No MCP servers configured` | 配置未生效 | 运行 `claude mcp list`，确认配置层级正确 |
| `Error calling tool: Failed to connect to MCP server` | bridge 重启后 stdio 进程未重连 | 重启 Claude Code 会话 |
| 多会话只有第一个能用，其余报 500 | bridge 单例 bug（未 patch） | 运行 `bash ~/mcp_chrome/patch-multi-session.sh` |
| project 配置覆盖了 user 配置 | 同名 server 在 project 层级有旧配置 | `claude mcp remove chrome-mcp-server -s project` |
| `mcp-chrome-stdio` 命令找不到 | npm 全局包未安装或 PATH 不对 | `npm i -g mcp-chrome-bridge`，确认 `which mcp-chrome-stdio` |
| `/mcp` 显示 Connected 但工具调用失败 | stdio 管道正常但 HTTP 到 bridge 断了 | 这是误导性状态，需重启会话 |

### 诊断命令

```bash
# 检查 bridge 是否在监听
lsof -i :12306

# 检查所有 mcp-chrome 进程
ps aux | grep mcp-chrome | grep -v grep

# 测试 bridge 健康
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:12306/ping
# 应返回 200

# 测试 MCP 协议是否支持多连接
curl -s -X POST http://127.0.0.1:12306/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
# 应返回 JSON-RPC result，而非 500 错误
```

## 11. 管理命令速查

```bash
# 查看已配置的 MCP server 及健康状态
claude mcp list

# 添加 stdio 模式（全局）
claude mcp add chrome-mcp-server -s user -- mcp-chrome-stdio

# 删除 user 级别配置
claude mcp remove chrome-mcp-server -s user

# 删除 project 级别配置
claude mcp remove chrome-mcp-server -s project

# 检查 MCP bridge 进程
lsof -i :12306
ps aux | grep mcp-chrome
```
