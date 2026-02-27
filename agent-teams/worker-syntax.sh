#!/bin/bash
# worker-syntax.sh — Worker 1: Homun-Lang compiler syntax changes
# Works in Homun-Lang/src/ — modifies ast.rs, parser.rs, codegen.rs, sema.rs, lexer.rs
# Usage: bash agent-teams/worker-syntax.sh <worker_id> [task_description]

cd "$(dirname "$0")/.." || exit 1
PROJECT_DIR="$(pwd)"
WORK_DIR="${PROJECT_DIR}/Homun-Lang"
WORKER_ID="${1:-1}"
TASK_DESC="${2:-}"
TRIGGER_FILE="${PROJECT_DIR}/_trigger_${WORKER_ID}"
LOG_FILE="${PROJECT_DIR}/out/worker_${WORKER_ID}.log"
GIT_LOCK="${PROJECT_DIR}/_git.lock"

mkdir -p out

log() {
  echo "$(date '+%H:%M:%S') [W${WORKER_ID}-syntax] $1" | tee -a "$LOG_FILE"
}

log "Worker ${WORKER_ID} (syntax) starting..."
[ -n "$TASK_DESC" ] && log "Task: ${TASK_DESC}"

if [ -n "$TASK_DESC" ]; then
  TASK_PROMPT="YOUR ASSIGNED TASK: ${TASK_DESC}
Focus ONLY on this specific task. Do not work on other tasks."
else
  TASK_PROMPT="Pick the smallest next syntax/compiler task that has not been done yet."
fi

CLAUDECODE= claude -p \
  --dangerously-skip-permissions \
  --model sonnet \
  "You are the Compiler Syntax Engineer on the Homun-Compiler project.
Your working directory: ${WORK_DIR}

FIRST: Read these files:
1. ${PROJECT_DIR}/.claude/llm.design.md — Section 'Part A: Compiler Changes' is YOUR work
2. ${PROJECT_DIR}/.claude/llm.plan.status
3. ${PROJECT_DIR}/.claude/llm.working.status

${TASK_PROMPT}

YOUR SCOPE — ONLY modify files in Homun-Lang/src/:
- src/ast.rs — AST types (add TryUnwrap, BindPat, extend Pat)
- src/parser.rs — parsing (add ? postfix, tuple bind LHS, nested patterns in match)
- src/codegen.rs — code generation (emit ?, emit tuple destructure, emit nested patterns)
- src/sema.rs — semantic analysis (handle new statement types)
- src/lexer.rs — lexer (add ? token if needed)

DO NOT touch: runtime/, build.rs, main.rs, Cargo.toml, or any other files.
Another worker handles runtime/ — stay in your lane.

WORKFLOW:
1. Read the design doc Part A section for what to implement
2. Make the smallest possible change (one feature at a time)
3. Verify: cd ${WORK_DIR} && cargo test
4. Format: cd ${WORK_DIR} && cargo fmt && cargo clippy
5. Git commit with lock:
   while ! mkdir ${GIT_LOCK} 2>/dev/null; do sleep 2; done
   cd ${PROJECT_DIR} && git add Homun-Lang/src/ && git commit -m 'part-a: description' --no-verify
   rmdir ${GIT_LOCK}
6. Update ${PROJECT_DIR}/.claude/llm.working.status — APPEND with [W${WORKER_ID}] prefix
7. Write DONE to: ${TRIGGER_FILE}

RULES:
- Small steps. One AST change + parser change + codegen change per commit.
- All changes must map 1:1 to Rust — pure syntactic sugar, no new semantics.
- cargo test MUST pass before committing.
- If stuck after 3 attempts: git stash, write BLOCKED to ${TRIGGER_FILE}
- Never ask questions. Make reasonable decisions and document them.
" 2>&1 | tee -a "$LOG_FILE"

log "Worker ${WORKER_ID} (syntax) finished."
