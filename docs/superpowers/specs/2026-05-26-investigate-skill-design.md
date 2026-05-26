# Investigate — Lightweight Analysis with Confidence Rating

## Overview

A lightweight, read-only analysis skill for investigating problems in the codebase. The core differentiator from `diagnose` (heavy-weight, fix-oriented, feedback-loop-required) and `triage` (issue-state-machine) is **mandatory confidence rating** on every claim. No code changes allowed.

## Core Rules

1. **Read-only** — read code, logs, git history, docs. Never edit files.
2. **Fact vs inference** — every statement falls into one of three tiers:
   - **CERTAIN** — read directly from code/log/docs, indisputable
   - **LIKELY** — supported by evidence with a traceable causal chain
   - **SPECULATIVE** — a possible direction, insufficient evidence
3. **Ask when uncertain** — if information is missing, list specific questions. Do not assume.
4. **Confidence-gate output** — every conclusion in the final report must carry a confidence tag. No untagged claims.

## Confidence Tiers

| Tier | Meaning | Example |
|------|---------|---------|
| **CERTAIN** | Directly observed in code/log/docs | "`_integrate_forces()` calls `apply_impulse()` at line 42" |
| **LIKELY** | Evidence-backed inference with causal chain | "Given the call chain A→B→C, B likely triggers the recontact" |
| **SPECULATIVE** | Possible direction, no direct evidence | "Might be a race condition, needs log to confirm" |

## Workflow

```
User asks "why X?" / "analyze Y" / "look at this log"
    │
    ▼
1. COLLECT EVIDENCE
   - Read relevant code paths
   - Check logs / git / docs / ADRs
   - Attempt repro if feasible
    │
    ▼
2. CLASSIFY FINDINGS  ←── MANDATORY GATE
   - Tag each finding CERTAIN / LIKELY / SPECULATIVE
   - Identify information gaps → list questions for user
   - Do NOT proceed to output until every claim is tagged
    │
    ▼
3. OUTPUT REPORT
   - Observations (CERTAIN)
   - Causal chain (LIKELY, with confidence rationale)
   - Possible directions (SPECULATIVE)
   - Open questions for the user
```

## Report Template

```markdown
## Analysis: <topic>

### Observations (CERTAIN)
- [CERTAIN] <fact from code/log>
- [CERTAIN] <fact from code/log>

### Causal Chain (LIKELY)
- [LIKELY] <inference> — basis: <evidence chain>
- [LIKELY] <inference> — basis: <evidence chain>

### Speculative Directions (SPECULATIVE)
- [SPECULATIVE] <possibility> — to confirm: <what to check>

### Questions for You
- <specific question>
- <specific question>

### Overall Confidence: <rough percentage or Low/Medium/High>
```

## Trigger Conditions

Use this skill when:
- "Why does X happen?"
- "Analyze this behavior"
- "Look at this log/error"
- "What could cause Y?"
- "Is this a bug?"
- Any open-ended technical investigation that should NOT modify code

Do NOT use when:
- Bug is confirmed and needs a fix → use `diagnose`
- Issue needs triage/labeling → use `triage`
- User explicitly says "fix it"

## Anti-Patterns

| Don't | Do |
|-------|-----|
| "The problem is X" (no tag) | "[LIKELY] The problem is X — basis: call chain at L42-58" |
| "Probably a timing issue" (vague) | "[SPECULATIVE] Timing issue — to confirm: add timestamp log" |
| Silent assumption about intention | Ask: "Is `<intent>` the expected behavior here?" |
| Proposing code changes | Note "Possible fix direction (not implementing): ..." |
