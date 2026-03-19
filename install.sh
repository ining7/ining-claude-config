#!/bin/bash
# Deploy claude config via symlinks
# Usage: ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Deploying from: $SCRIPT_DIR"
echo "Target: $CLAUDE_DIR"

# CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && [ ! -L "$CLAUDE_DIR/CLAUDE.md" ]; then
    echo "Backing up existing CLAUDE.md -> CLAUDE.md.bak"
    mv "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak"
fi
ln -sf "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "Linked: CLAUDE.md"

# Skills
mkdir -p "$CLAUDE_DIR/skills"
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    if [ -L "$CLAUDE_DIR/skills/$skill_name" ]; then
        rm "$CLAUDE_DIR/skills/$skill_name"
    fi
    ln -sf "$skill_dir" "$CLAUDE_DIR/skills/$skill_name"
    echo "Linked skill: $skill_name"
done

# Commands
if [ -d "$SCRIPT_DIR/commands" ] && [ "$(ls -A "$SCRIPT_DIR/commands" 2>/dev/null)" ]; then
    mkdir -p "$CLAUDE_DIR/commands"
    for cmd_file in "$SCRIPT_DIR"/commands/*.md; do
        [ -f "$cmd_file" ] || continue
        cmd_name=$(basename "$cmd_file")
        ln -sf "$cmd_file" "$CLAUDE_DIR/commands/$cmd_name"
        echo "Linked command: $cmd_name"
    done
fi

# Patches - mcp-chrome-bridge multi-session fix
if command -v mcp-chrome-bridge &>/dev/null; then
    echo "Applying mcp-chrome-bridge multi-session patch..."
    bash "$SCRIPT_DIR/patches/mcp-chrome-bridge/patch-multi-session.sh"
fi

echo "Done."
