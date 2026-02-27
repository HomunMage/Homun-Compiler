#!/bin/bash
# stop.sh — Stop the tmux orchestrator session and all workers
cd "$(dirname "$0")/.." || exit 1
SESSION="homun-compiler"

echo "Stopping tmux session: ${SESSION}"
tmux kill-session -t "$SESSION" 2>/dev/null && echo "Stopped." || echo "No session found."

# Clean up orphan processes and files
pkill -f "agent-teams/worker.sh" 2>/dev/null || true
rm -f _trigger_* _task_queue
rmdir _git.lock 2>/dev/null
