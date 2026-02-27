#!/bin/bash
# worker-mermaid.sh — Worker 3: mermaid-ascii rewrite in .hom
# Works in mermaid-hom/ — writes .hom files as a USER of the language
# Does NOT see or modify the Homun-Lang compiler internals
# Usage: bash agent-teams/worker-mermaid.sh <worker_id> [task_description]

cd "$(dirname "$0")/.." || exit 1
PROJECT_DIR="$(pwd)"
WORK_DIR="${PROJECT_DIR}/mermaid-hom"
WORKER_ID="${1:-3}"
TASK_DESC="${2:-}"
TRIGGER_FILE="${PROJECT_DIR}/_trigger_${WORKER_ID}"
LOG_FILE="${PROJECT_DIR}/out/worker_${WORKER_ID}.log"
GIT_LOCK="${PROJECT_DIR}/_git.lock"

mkdir -p out
mkdir -p "${WORK_DIR}/src"
mkdir -p "${WORK_DIR}/dep"

log() {
  echo "$(date '+%H:%M:%S') [W${WORKER_ID}-mermaid] $1" | tee -a "$LOG_FILE"
}

log "Worker ${WORKER_ID} (mermaid) starting..."
[ -n "$TASK_DESC" ] && log "Task: ${TASK_DESC}"

if [ -n "$TASK_DESC" ]; then
  TASK_PROMPT="YOUR ASSIGNED TASK: ${TASK_DESC}
Focus ONLY on this specific task. Do not work on other tasks."
else
  TASK_PROMPT="Pick the smallest next .hom module to write that has not been done yet."
fi

CLAUDECODE= claude -p \
  --dangerously-skip-permissions \
  --model sonnet \
  "You are a Senior Programmer writing mermaid-ascii in .hom (Homun language).
Your working directory: ${WORK_DIR}

You are a USER of the Homun language. You do NOT need to understand the compiler.

FIRST: Read these files:
1. ${PROJECT_DIR}/Homun-Lang/llm.txt — THIS IS YOUR LANGUAGE REFERENCE. Read it carefully.
2. ${PROJECT_DIR}/.claude/llm.plan.status
3. ${PROJECT_DIR}/.claude/llm.working.status
4. ${PROJECT_DIR}/.claude/llm.mermaid-ascii.md — Reference for what mermaid-ascii does

For reference on WHAT to implement (algorithms, data structures), you may read:
- ${PROJECT_DIR}/mermaid-ascii/src/mermaid_ascii/ — Python source (ground truth for logic)

${TASK_PROMPT}

YOUR SCOPE — ONLY files in mermaid-hom/:
- mermaid-hom/src/*.hom — Core logic in Homun language
  - types.hom — Direction, NodeShape, EdgeType, Node, Edge, Subgraph, Graph
  - config.hom — RenderConfig
  - layout_types.hom — Point, LayoutNode, RoutedEdge, LayoutResult
  - parser.hom — Cursor tokenizer + flowchart recursive descent
  - layout.hom — Sugiyama 8-phase algorithm
  - pathfinder.hom — A* edge routing
  - charset.hom — BoxChars, Arms, CharSet
  - canvas.hom — Rect, Canvas (2D char grid)
  - render.hom — ASCII renderer 7 phases
- mermaid-hom/dep/graph.rs — petgraph wrapper (this one is .rs, wraps external crate)
- mermaid-hom/src/main.rs — CLI (clap, .rs)
- mermaid-hom/src/lib.rs — API facade (.rs)

DO NOT modify anything in Homun-Lang/ — you are a user, not the compiler developer.

HOW TO WRITE .hom CODE:
- Read llm.txt for syntax reference
- No methods/impl blocks — use free functions: canvas_set(c, x, y, ch) not c.set(x, y, ch)
- No classes — structs for data, functions for behavior
- Use pipe | for chaining: list | filter(f) | map(g)
- Import libraries: use std, use heap, use re, use chars
- Last expression in {} is the return value

WORKFLOW:
1. Read the Python source for the module you're implementing (for algorithm reference)
2. Rewrite it in .hom following the patterns in llm.txt
3. Verify: Try to compile with homunc if available, otherwise ensure .hom syntax is correct
4. Git commit with lock:
   while ! mkdir ${GIT_LOCK} 2>/dev/null; do sleep 2; done
   cd ${PROJECT_DIR} && git add mermaid-hom/ && git commit -m 'mermaid: description' --no-verify
   rmdir ${GIT_LOCK}
5. Update ${PROJECT_DIR}/.claude/llm.working.status — APPEND with [W${WORKER_ID}] prefix
6. Write DONE to: ${TRIGGER_FILE}

RULES:
- Write clean, readable .hom code — this is the SHOWCASE for the language
- Follow Python logic closely (same algorithms) but use .hom idioms
- One module at a time. Small steps.
- If a language feature you need isn't in llm.txt, work around it or note it as a gap
- If stuck after 3 attempts: git stash, write BLOCKED to ${TRIGGER_FILE}
- Never ask questions. Make reasonable decisions and document them.
" 2>&1 | tee -a "$LOG_FILE"

log "Worker ${WORKER_ID} (mermaid) finished."
