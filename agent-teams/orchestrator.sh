#!/bin/bash
# orchestrator.sh — 3-worker orchestrator: syntax + runtime + mermaid-user
# Worker 1: Homun-Lang compiler (src/) — syntax changes
# Worker 2: Homun-Lang runtime (runtime/) — library additions
# Worker 3: mermaid-hom user — writes .hom code, sees only llm.txt
# Usage: bash agent-teams/orchestrator.sh [max_cycles]

cd "$(dirname "$0")/.." || exit 1
PROJECT_DIR="$(pwd)"
LOG_FILE="${PROJECT_DIR}/out/orchestrator.log"
MAX_CYCLES="${1:-50}"
SESSION="homun-compiler"
CYCLE=0

mkdir -p out

log() {
  echo "$(date '+%H:%M:%S') [ORCH] $1" | tee -a "$LOG_FILE"
}

# Task planning: read status, generate 3 tasks for fixed worker roles
plan_tasks() {
  CLAUDECODE= claude -p \
    --dangerously-skip-permissions \
    --model haiku \
    "You are the task planner for the Homun-Compiler project.
Project dir: ${PROJECT_DIR}

Read these files:
1. ${PROJECT_DIR}/.claude/llm.plan.status
2. ${PROJECT_DIR}/.claude/llm.working.status
3. ${PROJECT_DIR}/.claude/llm.design.md

There are 3 fixed worker roles:
- WORKER 1 (Syntax): Works in Homun-Lang/src/ — compiler changes (ast.rs, parser.rs, codegen.rs, sema.rs, lexer.rs)
- WORKER 2 (Runtime): Works in Homun-Lang/runtime/ — library files (heap.rs, re.rs, chars.rs, str_ext.rs, std/)
- WORKER 3 (Mermaid): Works in mermaid-hom/src/ — writes .hom code as a USER of the language

RULES:
- Each worker gets exactly ONE small task matching their role
- Worker 1 and 2 NEVER touch each other's directories
- Worker 3 NEVER touches Homun-Lang/ — it only writes .hom and .rs files in mermaid-hom/
- If a worker's role has no remaining work, assign IDLE for that worker
- Tasks should be the smallest next step in the current phase

Output format (ONLY output this, nothing else):
TASK1: <syntax task for worker 1, or IDLE>
TASK2: <runtime task for worker 2, or IDLE>
TASK3: <mermaid .hom task for worker 3, or IDLE>

If ALL phases are complete, output only:
ALL_DONE
" 2>/dev/null | grep -E '^(TASK[0-9]+:|ALL_DONE)' > "${PROJECT_DIR}/_task_queue"
}

# Spawn a worker in a new tmux window
spawn_worker() {
  local WORKER_ID=$1
  local TASK="$2"
  local WORKER_SCRIPT="$3"
  local WINDOW_NAME="worker-${WORKER_ID}"

  log "Spawning worker ${WORKER_ID}: ${TASK}"

  rm -f "${PROJECT_DIR}/_trigger_${WORKER_ID}"

  tmux new-window -t "${SESSION}" -n "${WINDOW_NAME}" \
    "cd ${PROJECT_DIR} && bash agent-teams/${WORKER_SCRIPT} ${WORKER_ID} '${TASK}'; echo 'Worker ${WORKER_ID} done. Press enter.'; read"
}

# Wait for all active workers to complete
wait_for_workers() {
  local ACTIVE_WORKERS="$1"
  local TIMEOUT=900
  local ELAPSED=0
  local ALL_DONE=false

  while [ "$ELAPSED" -lt "$TIMEOUT" ] && [ "$ALL_DONE" = "false" ]; do
    ALL_DONE=true
    for i in $ACTIVE_WORKERS; do
      if [ ! -f "${PROJECT_DIR}/_trigger_${i}" ]; then
        ALL_DONE=false
        break
      fi
    done

    if [ "$ALL_DONE" = "false" ]; then
      sleep 10
      ELAPSED=$((ELAPSED + 10))
      if [ $((ELAPSED % 60)) -eq 0 ]; then
        local STATUS=""
        for i in $ACTIVE_WORKERS; do
          if [ -f "${PROJECT_DIR}/_trigger_${i}" ]; then
            STATUS="${STATUS} W${i}:$(cat "${PROJECT_DIR}/_trigger_${i}")"
          else
            STATUS="${STATUS} W${i}:running"
          fi
        done
        log "Status check (${ELAPSED}s):${STATUS}"
      fi
    fi
  done

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    log "TIMEOUT: Workers didn't finish in ${TIMEOUT}s"
    return 1
  fi
  return 0
}

# Collect results
collect_results() {
  local ACTIVE_WORKERS="$1"
  local HAS_BLOCKED=false
  local HAS_ALL_COMPLETE=false

  for i in $ACTIVE_WORKERS; do
    local TRIGGER="${PROJECT_DIR}/_trigger_${i}"
    if [ -f "$TRIGGER" ]; then
      local RESULT=$(cat "$TRIGGER")
      log "Worker ${i} result: ${RESULT}"
      case "$RESULT" in
        BLOCKED) HAS_BLOCKED=true ;;
        ALL_COMPLETE) HAS_ALL_COMPLETE=true ;;
      esac
    else
      log "Worker ${i}: no trigger file (may have crashed)"
      HAS_BLOCKED=true
    fi
    rm -f "$TRIGGER"
    tmux kill-window -t "${SESSION}:worker-${i}" 2>/dev/null
  done

  if [ "$HAS_ALL_COMPLETE" = "true" ]; then
    return 2
  elif [ "$HAS_BLOCKED" = "true" ]; then
    return 1
  fi
  return 0
}

log "========================================"
log "Homun-Compiler orchestrator started"
log "Max cycles: ${MAX_CYCLES}"
log "Workers: W1=syntax, W2=runtime, W3=mermaid-user"
log "========================================"

while [ "$CYCLE" -lt "$MAX_CYCLES" ]; do
  CYCLE=$((CYCLE + 1))
  log ""
  log "=== Cycle ${CYCLE}/${MAX_CYCLES} ==="

  rmdir "${PROJECT_DIR}/_git.lock" 2>/dev/null

  log "Planning tasks..."
  plan_tasks

  if grep -q "ALL_DONE" "${PROJECT_DIR}/_task_queue" 2>/dev/null; then
    log "ALL PHASES COMPLETE!"
    exit 0
  fi

  # Parse tasks and spawn workers (skip IDLE workers)
  ACTIVE_WORKERS=""

  TASK1=$(grep '^TASK1:' "${PROJECT_DIR}/_task_queue" | sed 's/^TASK1: //')
  TASK2=$(grep '^TASK2:' "${PROJECT_DIR}/_task_queue" | sed 's/^TASK2: //')
  TASK3=$(grep '^TASK3:' "${PROJECT_DIR}/_task_queue" | sed 's/^TASK3: //')

  if [ -n "$TASK1" ] && [ "$TASK1" != "IDLE" ]; then
    spawn_worker 1 "$TASK1" "worker-syntax.sh"
    ACTIVE_WORKERS="$ACTIVE_WORKERS 1"
  else
    log "Worker 1 (syntax): IDLE"
  fi

  if [ -n "$TASK2" ] && [ "$TASK2" != "IDLE" ]; then
    spawn_worker 2 "$TASK2" "worker-runtime.sh"
    ACTIVE_WORKERS="$ACTIVE_WORKERS 2"
  else
    log "Worker 2 (runtime): IDLE"
  fi

  if [ -n "$TASK3" ] && [ "$TASK3" != "IDLE" ]; then
    spawn_worker 3 "$TASK3" "worker-mermaid.sh"
    ACTIVE_WORKERS="$ACTIVE_WORKERS 3"
  else
    log "Worker 3 (mermaid): IDLE"
  fi

  if [ -z "$ACTIVE_WORKERS" ]; then
    log "All workers IDLE. Retrying in 15s..."
    sleep 15
    continue
  fi

  log "Active workers:${ACTIVE_WORKERS}. Waiting..."
  wait_for_workers "$ACTIVE_WORKERS"

  collect_results "$ACTIVE_WORKERS"
  RESULT=$?

  case $RESULT in
    0) log "Cycle ${CYCLE} complete." ;;
    1) log "Some workers blocked. Waiting 30s..." ; sleep 30 ;;
    2) log "ALL PHASES COMPLETE!" ; exit 0 ;;
  esac

  sleep 5
done

log "Max cycles (${MAX_CYCLES}) reached."
