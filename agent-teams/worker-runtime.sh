#!/bin/bash
# worker-runtime.sh — Worker 2: Homun-Lang runtime libraries
# Works in Homun-Lang/runtime/ — adds heap.rs, re.rs, chars.rs, str_ext.rs, etc.
# Usage: bash agent-teams/worker-runtime.sh <worker_id> [task_description]

cd "$(dirname "$0")/.." || exit 1
PROJECT_DIR="$(pwd)"
WORK_DIR="${PROJECT_DIR}/Homun-Lang"
WORKER_ID="${1:-2}"
TASK_DESC="${2:-}"
TRIGGER_FILE="${PROJECT_DIR}/_trigger_${WORKER_ID}"
LOG_FILE="${PROJECT_DIR}/out/worker_${WORKER_ID}.log"
GIT_LOCK="${PROJECT_DIR}/_git.lock"

mkdir -p out

log() {
  echo "$(date '+%H:%M:%S') [W${WORKER_ID}-runtime] $1" | tee -a "$LOG_FILE"
}

log "Worker ${WORKER_ID} (runtime) starting..."
[ -n "$TASK_DESC" ] && log "Task: ${TASK_DESC}"

if [ -n "$TASK_DESC" ]; then
  TASK_PROMPT="YOUR ASSIGNED TASK: ${TASK_DESC}
Focus ONLY on this specific task. Do not work on other tasks."
else
  TASK_PROMPT="Pick the smallest next runtime library task that has not been done yet."
fi

CLAUDECODE= claude -p \
  --dangerously-skip-permissions \
  --model sonnet \
  "You are the Runtime Library Engineer on the Homun-Compiler project.
Your working directory: ${WORK_DIR}

FIRST: Read these files:
1. ${PROJECT_DIR}/.claude/llm.design.md — Section 'Part B: Runtime Libraries' is YOUR work
2. ${PROJECT_DIR}/.claude/llm.plan.status
3. ${PROJECT_DIR}/.claude/llm.working.status

${TASK_PROMPT}

YOUR SCOPE — ONLY modify files in Homun-Lang/runtime/:
- runtime/heap.rs — Priority queue (wraps BinaryHeap)
- runtime/re.rs — Regex (wraps regex crate)
- runtime/chars.rs — Character classification (is_alpha, is_alnum, is_digit, is_ws)
- runtime/str_ext.rs — String extras (str_repeat, str_pad_center)
- runtime/std/ — Existing stdlib (may need minor additions)

DO NOT touch: src/ (compiler), build.rs, main.rs, or any files outside runtime/.
Another worker handles src/ — stay in your lane.

LIBRARY DESIGN RULES:
- Each library is a standalone .rs file that gets inlined by the compiler via 'use foo'
- Libraries must be SELF-CONTAINED: no external crate imports (except std::)
  Exception: re.rs may need regex crate — document this in the file header
- Export pub functions with simple signatures (no lifetimes, no complex generics)
- Functions should work with types .hom can generate: String, i32, f32, bool, Vec, HashMap, HashSet
- Write functions as if they'll be called from generated Rust code

WORKFLOW:
1. Read the design doc Part B section for API specifications
2. Write one library file at a time
3. Verify: Write a small test .hom that uses the library, compile with homunc, run
   Or: cd ${WORK_DIR} && cargo test (if library has #[cfg(test)] tests)
4. Format: rustfmt on new .rs files
5. Git commit with lock:
   while ! mkdir ${GIT_LOCK} 2>/dev/null; do sleep 2; done
   cd ${PROJECT_DIR} && git add Homun-Lang/runtime/ && git commit -m 'part-b: description' --no-verify
   rmdir ${GIT_LOCK}
6. Update ${PROJECT_DIR}/.claude/llm.working.status — APPEND with [W${WORKER_ID}] prefix
7. Write DONE to: ${TRIGGER_FILE}

RULES:
- Keep libraries minimal. Only export what's in the design doc.
- Test each function works when called from generated Rust.
- If stuck after 3 attempts: git stash, write BLOCKED to ${TRIGGER_FILE}
- Never ask questions. Make reasonable decisions and document them.
" 2>&1 | tee -a "$LOG_FILE"

log "Worker ${WORKER_ID} (runtime) finished."
