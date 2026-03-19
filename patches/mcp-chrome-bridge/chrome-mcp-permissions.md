# Chrome MCP 权限控制方案

## 1. 为什么需要权限控制

Chrome MCP 让 Claude Code 拥有完整的浏览器控制能力，包括：
- 读取任意页面内容（含已登录的敏感系统）
- 执行任意 JavaScript
- 模拟点击、输入、导航
- 关闭标签页、修改书签
- 捕获网络请求

如果不加限制，Claude Code 可能在处理任务时**误操作**（如关闭重要标签页、在表单中填入错误数据、触发删除操作等）。通过 `settings.json` 的 `deny` 规则，可以在保留读取能力的同时禁止危险的写入操作。

## 2. 权限分类原则

| 分类 | 策略 | 理由 |
|------|------|------|
| **只读/观察类** | allow | 不会修改浏览器状态，安全 |
| **交互/写入类** | deny | 可能误操作，造成不可逆后果 |
| **需要时手动放行** | 按需 allow | 某些场景需要导航或点击，临时开放 |

## 3. 工具清单与推荐权限（mcp-chrome-bridge@1.0.31）

Claude Code 中的工具名格式为 `mcp__chrome-mcp-server__<tool_name>`。

### 3.1 推荐 Allow（只读/安全）

| 工具名 | 功能 | 风险等级 |
|--------|------|----------|
| `get_windows_and_tabs` | 列出所有窗口和标签页 | 无 |
| `chrome_read_page` | 获取页面可访问性树（可见元素） | 无 |
| `chrome_get_web_content` | 提取页面文本/HTML 内容 | 无 |
| `chrome_screenshot` | 截图 | 无 |
| `chrome_history` | 查询浏览历史 | 低（只读） |
| `chrome_bookmark_search` | 搜索书签 | 无 |
| `chrome_console` | 读取控制台输出 | 低（只读） |
| `performance_start_trace` | 开始性能追踪 | 低 |
| `performance_stop_trace` | 停止性能追踪 | 低 |
| `performance_analyze_insight` | 分析性能追踪结果 | 无 |
| `chrome_handle_download` | 等待下载完成并返回信息 | 低（只读） |

### 3.2 推荐 Deny（危险/写入操作）

| 工具名 | 功能 | 风险 |
|--------|------|------|
| `chrome_computer` | 模拟鼠标/键盘全部操作（点击、拖拽、输入、按键） | **高** — 可执行任意操作 |
| `chrome_click_element` | 点击页面元素 | **高** — 可能触发删除、提交等 |
| `chrome_fill_or_select` | 填写表单/选择下拉框 | **高** — 可能提交错误数据 |
| `chrome_keyboard` | 发送键盘事件 | **高** — 可能触发快捷键操作 |
| `chrome_navigate` | 导航到 URL | **中** — 可能离开重要页面 |
| `chrome_close_tabs` | 关闭标签页 | **高** — 丢失未保存内容 |
| `chrome_switch_tab` | 切换标签页 | **低** — 但可能干扰用户 |
| `chrome_javascript` | 在页面执行任意 JS | **高** — 可执行任意代码 |
| `chrome_bookmark_add` | 添加书签 | **低** — 但未经授权的修改 |
| `chrome_bookmark_delete` | 删除书签 | **中** — 不可逆 |
| `chrome_network_capture` | 捕获网络请求（含请求体） | **中** — 可能泄露敏感数据 |
| `chrome_network_request` | 发送 HTTP 请求 | **高** — 可能触发 API 调用 |
| `chrome_upload_file` | 上传文件到网页表单 | **高** — 可能上传敏感文件 |
| `chrome_handle_dialog` | 处理弹窗（确认/取消） | **中** — 可能确认危险操作 |
| `chrome_request_element_selection` | 请求用户选择元素 | **低** — 需要用户参与 |
| `chrome_gif_recorder` | 录制 GIF | **低** — 但会占用资源 |
| `chrome_go_back_or_forward` | 浏览器前进/后退 | **低** |

### 3.3 旧版工具名（Legacy，已不暴露但保留内部引用）

| 旧工具名 | 状态 |
|-----------|------|
| `chrome_network_capture_start` | 已合并到 `chrome_network_capture` |
| `chrome_network_capture_stop` | 已合并到 `chrome_network_capture` |
| `chrome_network_debugger_start` | 已合并到 `chrome_network_capture` |
| `chrome_network_debugger_stop` | 已合并到 `chrome_network_capture` |
| `search_tabs_content` | 已注释掉，不再暴露 |
| `chrome_inject_script` | 已注释掉，不再暴露 |
| `chrome_send_command_to_inject_script` | 已注释掉，不再暴露 |
| `chrome_get_interactive_elements` | 已注释掉，不再暴露 |

## 4. 推荐配置

在 `~/.claude/settings.json` 的 `permissions` 中配置：

```json
{
  "permissions": {
    "allow": [
      "mcp__chrome-mcp-server__get_windows_and_tabs",
      "mcp__chrome-mcp-server__chrome_read_page",
      "mcp__chrome-mcp-server__chrome_get_web_content",
      "mcp__chrome-mcp-server__chrome_screenshot",
      "mcp__chrome-mcp-server__chrome_history",
      "mcp__chrome-mcp-server__chrome_bookmark_search",
      "mcp__chrome-mcp-server__chrome_console",
      "mcp__chrome-mcp-server__chrome_handle_download",
      "mcp__chrome-mcp-server__performance_start_trace",
      "mcp__chrome-mcp-server__performance_stop_trace",
      "mcp__chrome-mcp-server__performance_analyze_insight"
    ],
    "deny": [
      "mcp__chrome-mcp-server__chrome_computer",
      "mcp__chrome-mcp-server__chrome_click_element",
      "mcp__chrome-mcp-server__chrome_fill_or_select",
      "mcp__chrome-mcp-server__chrome_keyboard",
      "mcp__chrome-mcp-server__chrome_javascript",
      "mcp__chrome-mcp-server__chrome_navigate",
      "mcp__chrome-mcp-server__chrome_close_tabs",
      "mcp__chrome-mcp-server__chrome_switch_tab",
      "mcp__chrome-mcp-server__chrome_bookmark_add",
      "mcp__chrome-mcp-server__chrome_bookmark_delete",
      "mcp__chrome-mcp-server__chrome_network_capture",
      "mcp__chrome-mcp-server__chrome_network_request",
      "mcp__chrome-mcp-server__chrome_upload_file",
      "mcp__chrome-mcp-server__chrome_handle_dialog",
      "mcp__chrome-mcp-server__chrome_request_element_selection",
      "mcp__chrome-mcp-server__chrome_gif_recorder"
    ]
  }
}
```

## 5. 按需临时放行

如果某些任务需要导航或交互（如让 Claude 帮你填写表单），可以临时在 settings 中将对应工具从 deny 移到 allow。完成后再改回来。

或者，可以在**项目级别**的 settings 中针对特定项目放行，不影响全局安全策略。

## 6. CLAUDE.md 中的配合规则

在 CLAUDE.md 中补充以下规则，让 Claude 在工具被 deny 时给出合理的提示而非报错：

```markdown
# Chrome MCP Permission Policy

Some Chrome MCP tools are denied for safety. When a denied tool is needed:
1. Inform the user which tool is needed and why
2. Suggest the user perform the action manually in their browser
3. Use `chrome_get_web_content` or `chrome_read_page` to verify the result after manual action
4. NEVER attempt to work around denied permissions
```
