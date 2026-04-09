---
name: peer-review
description: Launches a separate Claude instance as an independent reviewer for plans or code changes. Use when the task involves significant architectural decisions, complex logic, security-sensitive code, or when the user explicitly requests a review. Do NOT use for trivial changes, simple bug fixes, or straightforward implementations.
allowed-tools: Bash(claude *)
---

# Peer Review

Launches an independent Claude instance to review the current plan or code changes, providing a "second pair of eyes" perspective.

## When to Use

Use this skill when:
- The task involves **significant architectural or design decisions**
- The code touches **security-sensitive** areas (auth, crypto, permissions, input handling)
- The implementation has **complex logic** that could have subtle bugs (concurrency, memory management, state machines)
- **Multiple files or modules** are being changed in a coordinated way
- The user **explicitly requests** a review (e.g., `/peer-review`)

Do NOT use when:
- The change is a simple bug fix, typo, or config tweak
- The implementation is straightforward with no ambiguity
- Only documentation or comments are being changed
- The user has not asked for a review and the change is low-risk

## Usage

Pass the content to review as arguments:

```
/peer-review <plan or code description>
```

## Execution

Run the review using `claude -p` in print mode. Construct the prompt as follows:

```bash
claude -p "You are a senior code reviewer. Review the following content and provide feedback. You MUST respond entirely in Chinese (简体中文).

## Review Checklist

### 1. Security (CRITICAL)
- Injection vulnerabilities (SQL, command, XSS, etc.)
- Hardcoded secrets, keys, passwords, or tokens
- Improper permission or access control
- Unsafe deserialization or input handling

### 2. Architecture & Design
- Over-engineering: unnecessary abstractions, premature generalization
- Responsibility clarity: does each module/class have a single clear purpose
- Coupling: are modules loosely coupled and independently testable
- Are there hardcoded values that should be configurable (paths, URLs, magic numbers)
- Are there absolute paths that should be relative or configurable

### 3. Language-Specific Issues
- For C/C++: memory leaks, buffer overflows, array out-of-bounds, use-after-free, dangling pointers, uninitialized variables
- For Python: mutable default arguments, unclosed resources, GIL-related issues
- For JavaScript/TypeScript: prototype pollution, callback hell, unhandled promise rejections
- For other languages: apply equivalent common pitfalls

### 4. Performance & Resources
- Memory leaks or unbounded growth
- Unnecessary computation or redundant operations
- N+1 queries or inefficient data access patterns
- Missing resource cleanup (file handles, connections, etc.)

### 5. Code Style & Maintainability
- Naming conventions: are names clear and consistent
- Complexity: are functions/methods too long or doing too many things
- Readability: can another developer understand this without extra context

## Output Format

List all issues in a single prioritized list, most critical first.
For each issue:
- One-line summary
- If the issue MUST be fixed: provide the reason and suggested fix

Keep it concise. No praise, no filler.

---

Content to review:

$ARGUMENTS"
```

## Notes

- The `-p` flag runs Claude non-interactively
- The review Claude instance is separate from the current session
- The command inherits the current working directory, so it has access to project files for context
