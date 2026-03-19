# Claude Code 自定义配置完全指南

## 目录

- [概述](#概述)
- [核心概念](#核心概念)
  - [CLAUDE.md — 全局行为规则](#claudemd--全局行为规则)
  - [Skills — 自定义技能](#skills--自定义技能)
  - [Commands — 自定义斜杠命令](#commands--自定义斜杠命令)
  - [Plugins — 完整插件包](#plugins--完整插件包)
  - [四者对比](#四者对比)
- [配置文件位置与作用域](#配置文件位置与作用域)
- [CLAUDE.md 详解](#claudemd-详解)
  - [作用](#作用)
  - [位置与优先级](#位置与优先级)
  - [配置示例](#配置示例)
- [Skills 详解](#skills-详解)
  - [文件结构](#文件结构)
  - [SKILL.md 格式](#skillmd-格式)
  - [配置示例：代码审查 skill](#配置示例代码审查-skill)
  - [配置示例：轻量问答 skill](#配置示例轻量问答-skill)
- [Commands 详解](#commands-详解)
  - [文件结构](#文件结构-1)
  - [配置示例](#配置示例-1)
- [维护自己的配置仓库](#维护自己的配置仓库)
  - [为什么要用独立仓库](#为什么要用独立仓库)
  - [仓库结构](#仓库结构)
  - [Symlink 部署策略](#symlink-部署策略)
  - [安装脚本](#安装脚本)
  - [日常工作流](#日常工作流)
  - [新设备部署](#新设备部署)
  - [什么该放进仓库](#什么该放进仓库)
- [进阶用法](#进阶用法)
  - [在 CLAUDE.md 中引用 Skills](#在-claudemd-中引用-skills)
  - [参考社区实践](#参考社区实践)

---

## 概述

Claude Code 支持通过配置文件来定制 AI 的行为、添加自定义命令和技能。所有配置都在 `~/.claude/` 目录下（全局）或项目的 `.claude/` 目录下（项目级）。

本文档介绍所有可定制的内容、配置方法，以及如何用 GitHub 仓库 + symlink 的方式维护一套可跨设备复用的个人配置。

---

## 核心概念

### CLAUDE.md — 全局行为规则

一个 Markdown 文件，Claude Code 每次启动时都会读取。你在里面写的内容会成为 Claude 的"系统指令"的一部分，影响它的行为方式。

类比：相当于给 AI 写了一份工作手册。

### Skills — 自定义技能

一个带有 YAML frontmatter 的 Markdown 文件（`SKILL.md`），定义了一个可被调用的技能。Skills 可以声明工具权限（比如允许执行哪些 bash 命令），比 Commands 更强大。

类比：相当于给 AI 添加了一个专业工具，并附带使用说明和权限控制。

### Commands — 自定义斜杠命令

一个普通的 Markdown 文件，定义一个 `/命令`。内容就是 prompt 模板，不能声明权限。是最轻量的扩展方式。

类比：相当于一个快捷 prompt 模板。

### Plugins — 完整插件包

包含 skills + agents + hooks 的完整包，有 `plugin.json` 描述元数据。通常由社区发布，通过 marketplace 或 skillfish 安装。

类比：相当于一个完整的扩展应用。

### 四者对比

| 特性 | CLAUDE.md | Command | Skill | Plugin |
|------|-----------|---------|-------|--------|
| 本质 | 行为规则文件 | prompt 模板 | 带权限的 prompt | 完整扩展包 |
| 触发方式 | 自动加载 | `/命令名` | `/技能名` 或自动 | 安装后生效 |
| 能否声明工具权限 | 否 | 否 | 是 | 是 |
| 文件格式 | `.md` | `.md` | `SKILL.md`（带 frontmatter） | 多文件 + `plugin.json` |
| 存放位置 | `CLAUDE.md` | `commands/xxx.md` | `skills/xxx/SKILL.md` | `plugins/` |
| 复杂度 | 低 | 低 | 中 | 高 |

---

## 配置文件位置与作用域

Claude Code 支持两个级别的配置：

| 级别 | 路径 | 作用范围 |
|------|------|----------|
| 全局（用户级） | `~/.claude/` | 所有项目 |
| 项目级 | `项目根目录/.claude/` | 仅当前项目 |

项目级配置优先于全局配置。两者可以共存，Claude Code 会合并加载。

全局目录完整结构：

```
~/.claude/
├── CLAUDE.md          # 全局行为规则
├── settings.json      # 模型、环境变量等配置（Claude Code 自动管理）
├── skills/            # 自定义 skills
│   └── skill-name/
│       └── SKILL.md
├── commands/          # 自定义 commands
│   └── command-name.md
├── plugins/           # 已安装的 plugins（通常由工具管理，不手动编辑）
├── rules/             # 提取的项目规则
├── history.jsonl      # 对话历史（自动生成）
├── cache/             # 缓存（自动生成）
├── debug/             # 调试日志（自动生成）
└── ...                # 其他自动生成的文件
```

---

## CLAUDE.md 详解

### 作用

CLAUDE.md 中的内容会被 Claude Code 作为指令的一部分读取。你可以在里面定义：

- 编码风格偏好
- 工作流程规则（比如 Plan Mode 的行为）
- 项目约定
- 禁止或强制的行为

### 位置与优先级

| 文件 | 作用范围 |
|------|----------|
| `~/.claude/CLAUDE.md` | 全局，所有项目生效 |
| `项目根目录/CLAUDE.md` | 当前项目 |
| `项目根目录/.claude/CLAUDE.md` | 当前项目（等效于上面） |

多个文件同时存在时，Claude Code 会全部加载，内容叠加生效。

### 配置示例

```markdown
# 全局规则

## Plan Mode
在 Plan Mode 中，退出前必须使用 /code-review skill 对当前方案进行独立审查，
将审查反馈中的关键问题整合进计划后，才能 ExitPlanMode。

## 编码风格
- 优先使用函数式编程风格
- 变量命名使用 snake_case（Python）或 camelCase（JavaScript/TypeScript）
- 不要添加不必要的注释，代码应该自解释

## 禁止事项
- 不要自动 git push
- 不要修改 .env 文件
- 不要在没有说明原因的情况下删除测试用例
```

---

## Skills 详解

### 文件结构

```
skills/
└── skill-name/          # 文件夹名就是 skill 名
    └── SKILL.md         # 必须叫 SKILL.md
```

安装位置：
- 全局：`~/.claude/skills/skill-name/SKILL.md`
- 项目级：`项目/.claude/skills/skill-name/SKILL.md`

### SKILL.md 格式

```markdown
---
name: skill-name
description: 一句话描述这个 skill 的用途。Claude 会根据这个描述判断何时建议使用。
allowed-tools: Bash(命令前缀 *)
---

# Skill 标题

下面写 prompt 正文。Claude 调用这个 skill 时会读取这里的全部内容。

可以包含：
- 使用说明
- 执行步骤
- 输出格式要求
- 示例

$ARGUMENTS 会被替换为用户调用时传入的参数。
```

**frontmatter 字段说明**：

| 字段 | 必须 | 说明 |
|------|------|------|
| `name` | 是 | skill 名称，对应 `/name` 命令 |
| `description` | 是 | 功能描述，Claude 用来判断是否建议调用 |
| `allowed-tools` | 否 | 权限声明，限制 skill 能使用哪些工具 |

**allowed-tools 常见写法**：

| 写法 | 含义 |
|------|------|
| `Bash(claude *)` | 只允许执行 `claude` 开头的命令 |
| `Bash(codex *)` | 只允许执行 `codex` 开头的命令 |
| `Bash(*)` | 允许执行任意 bash 命令 |
| 不写 | 使用默认权限 |

### 配置示例：代码审查 skill

`skills/code-review/SKILL.md`：

```markdown
---
name: code-review
description: Launches a separate Claude instance to perform systematic code review on a plan or code changes.
allowed-tools: Bash(claude *)
---

# Code Review

Launches an independent Claude instance to review the current plan or code changes.

## Execution

Run the review using `claude -p` in print mode:

```bash
claude -p "You are a senior code reviewer. Review the following content.

## Review Checklist
1. Security: injection, hardcoded secrets, permission issues
2. Architecture: over-engineering, coupling, hardcoded values
3. Language-specific: memory leaks (C++), mutable defaults (Python), etc.
4. Performance: memory leaks, N+1 queries, redundant computation
5. Maintainability: naming, complexity, readability

List all issues by priority. For must-fix items, provide reason and suggested fix.

Content to review:
$ARGUMENTS"
```
```

### 配置示例：轻量问答 skill

`skills/ask-quick/SKILL.md`：

```markdown
---
name: ask-quick
description: Quick question to another Claude instance for a second opinion.
allowed-tools: Bash(claude *)
---

# Quick Ask

Ask a quick question to a separate Claude instance:

```bash
claude -p "$ARGUMENTS"
```
```

---

## Commands 详解

### 文件结构

Commands 比 Skills 更简单，就是一个 `.md` 文件：

```
commands/
└── command-name.md      # 文件名（不含 .md）就是命令名
```

文件内容就是 prompt 模板，没有 frontmatter，没有权限控制。

安装位置：
- 全局：`~/.claude/commands/command-name.md`
- 项目级：`项目/.claude/commands/command-name.md`

### 配置示例

`commands/explain.md`（使用 `/explain` 调用）：

```markdown
请用中文详细解释以下代码的逻辑，包括：
1. 整体功能
2. 关键步骤
3. 潜在的边界情况

代码：
$ARGUMENTS
```

`commands/test-plan.md`（使用 `/test-plan` 调用）：

```markdown
为以下功能或代码生成测试计划：
1. 列出需要测试的场景（正常路径 + 边界情况 + 错误情况）
2. 每个场景写出具体的测试描述
3. 标注优先级（P0/P1/P2）

功能描述：
$ARGUMENTS
```

---

## 维护自己的配置仓库

### 为什么要用独立仓库

直接把 `~/.claude/` 作为 git repo 的问题：

- `~/.claude/` 下有大量自动生成的文件（`history.jsonl`、`cache/`、`debug/`、`todos/` 等）
- `settings.json` 可能包含设备特定的配置（model ARN 等）
- 需要维护一个复杂的 `.gitignore`，容易遗漏

**独立仓库 + symlink** 的优势：

- 只包含你主动维护的文件，干净清晰
- 公开分享时不会泄露隐私配置
- 一键部署到任何设备
- 结构清晰，方便他人参考和 fork

### 仓库结构

```
ining-claude-config/           # 你的 GitHub 仓库
├── CLAUDE.md                  # 全局行为规则
├── skills/
│   └── code-review/
│       └── SKILL.md
├── commands/
│   └── explain.md
├── install.sh                 # 部署脚本
├── .gitignore
└── docs/
    └── claude-code-customization-guide.md   # 本文档
```

### Symlink 部署策略

原理：用操作系统的软链接（symlink）让 `~/.claude/` 下的文件指向仓库中的实际文件。

```
~/.claude/CLAUDE.md  →  ~/ining-claude-config/CLAUDE.md
~/.claude/skills/x   →  ~/ining-claude-config/skills/x/
~/.claude/commands/x  →  ~/ining-claude-config/commands/x
```

Claude Code 读取 `~/.claude/CLAUDE.md` 时，操作系统自动跳转到仓库中的文件。对 Claude Code 完全透明。

**好处**：在仓库中编辑文件后立刻生效，不需要重新部署。

### 安装脚本

`install.sh` 负责创建所有 symlink：

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Deploying from: $SCRIPT_DIR"
echo "Target: $CLAUDE_DIR"

# CLAUDE.md：如果已存在普通文件，备份后替换为 symlink
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && [ ! -L "$CLAUDE_DIR/CLAUDE.md" ]; then
    mv "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak"
fi
ln -sf "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# Skills：遍历仓库中的每个 skill 目录，创建 symlink
mkdir -p "$CLAUDE_DIR/skills"
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    [ -L "$CLAUDE_DIR/skills/$skill_name" ] && rm "$CLAUDE_DIR/skills/$skill_name"
    ln -sf "$skill_dir" "$CLAUDE_DIR/skills/$skill_name"
done

# Commands：遍历仓库中的每个 command 文件，创建 symlink
if [ -d "$SCRIPT_DIR/commands" ] && [ "$(ls -A "$SCRIPT_DIR/commands" 2>/dev/null)" ]; then
    mkdir -p "$CLAUDE_DIR/commands"
    for cmd_file in "$SCRIPT_DIR"/commands/*.md; do
        [ -f "$cmd_file" ] || continue
        ln -sf "$cmd_file" "$CLAUDE_DIR/commands/$(basename "$cmd_file")"
    done
fi

echo "Done."
```

脚本设计要点：
- 已有普通文件会备份为 `.bak`，不会丢失
- 已有 symlink 会先删除再重建，保证指向最新
- 幂等：多次运行结果一致

### 日常工作流

```
1. 编辑仓库中的文件
   vim ~/ining-claude-config/CLAUDE.md

2. Claude Code 立刻生效（symlink，无需额外操作）

3. 提交到 GitHub
   cd ~/ining-claude-config
   git add .
   git commit -m "更新审查规则"
   git push

4. 其他设备同步
   cd ~/ining-claude-config
   git pull
   # 如果是新增了 skill/command，重新运行 install.sh
```

### 新设备部署

```bash
# 1. 克隆仓库
git clone https://github.com/你的用户名/ining-claude-config.git ~/ining-claude-config

# 2. 运行安装脚本
chmod +x ~/ining-claude-config/install.sh
~/ining-claude-config/install.sh

# 完成
```

### 什么该放进仓库

| 放进仓库 | 不放进仓库 |
|----------|-----------|
| `CLAUDE.md`（全局规则） | `settings.json`（含设备特定配置） |
| `skills/`（自定义技能） | `history.jsonl`（对话历史） |
| `commands/`（自定义命令） | `cache/`、`debug/`、`todos/` |
| `install.sh`（部署脚本） | `plugins/`（通过其他方式管理） |
| `docs/`（文档） | `session-env/`、`shell-snapshots/` |

---

## 进阶用法

### 在 CLAUDE.md 中引用 Skills

可以在 CLAUDE.md 中写规则，让 Claude 在特定场景自动调用 skill：

```markdown
## Plan Mode 规则
在 Plan Mode 退出前，必须使用 /code-review skill 审查当前方案。

## 代码提交规则
每次 git commit 前，使用 /code-review 审查即将提交的变更。
```

### 参考社区实践

一些可以参考的开源配置仓库和资源：

- [hiroro-work/claude-plugins](https://github.com/hiroro-work/claude-plugins)：包含 ask-claude、ask-codex、ask-gemini 等跨 AI 审查 skills
- [MCP Market](https://mcpmarket.com)：社区 skills 和 plugins 市场
- skillfish 工具（`npx skillfish add`）：从 GitHub 仓库快速安装社区 skills

安装社区 skill 的两种方式：

```bash
# 方式一：通过 skillfish
npx skillfish add 仓库拥有者/仓库名 skill名

# 方式二：手动
# 从 GitHub 下载 SKILL.md，放到 ~/.claude/skills/skill名/SKILL.md
```
