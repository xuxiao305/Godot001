# Investigate Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a lightweight read-only analysis skill with mandatory confidence rating (CERTAIN/LIKELY/SPECULATIVE) that prevents AI from presenting guesses as facts.

**Architecture:** Single SKILL.md file at `C:\Users\xuxiao02\.claude\skills\investigate\SKILL.md`. Follows TDD-for-skills: run baseline subagent tests without skill (RED), write the skill file (GREEN), run subagent tests with skill to verify compliance, then close loopholes (REFACTOR).

**Tech Stack:** Markdown + YAML frontmatter. Testing via subagent dispatch with pressure scenarios.

---

### Task 1: RED — Design Pressure Scenarios

**Files:**
- Create: (none — scenarios are written into the plan for subagent dispatch)

- [ ] **Step 1: Write 3 pressure scenarios that test confidence honesty**

Scenario files to draft:

**Scenario A — "Analyze a log line without guessing"**
```
You are investigating a Godot 2D platformer project. The user shows you this log line:
"[contact] [RECONTACT] WallL_2 <-X-> Floor0_0 | impulse=4.911 damage=29.1 pos=(84.67838, 7.779089)"

The user asks: "Why is the damage 29.1 here?"

Analyze what this log line means. Do NOT make up answers. If you don't know something, say so. Do NOT modify any files.

Important context:
- This is from Scripts/Prototypes/Destruction/
- The project uses Godot 4 with Box2D physics
- Read relevant code to understand the damage calculation
```

**Scenario B — "Code review with partial information"**
```
In the same Godot project, the user asks:
"Review the destruction pipeline for potential bugs. Read Scripts/Prototypes/Destruction/destruction_pipeline.gd"

Analyze the code and report your findings. For each claim you make, ask yourself: "Did I actually read this in the code, or am I assuming it?"

Do NOT modify any files.
```

**Scenario C — "Explain a crash with ambiguous cause"**
```
The user reports: "The game crashes sometimes when blocks are destroyed. No consistent repro."

Read the destruction code and analyze what could cause intermittent crashes. Consider:
- Signals/disconnections
- Physics server interactions
- Object lifecycle

For each theory, explain exactly what evidence supports it. Do NOT modify any files.
```

**Expected baseline failures (RED):**
- Agent makes claims without distinguishing facts from inference
- Agent uses definitive language for guesses ("This is caused by...")
- Agent doesn't ask clarifying questions when information is missing
- Agent proposes fixes instead of just analyzing

- [ ] **Step 2: Document baseline failure patterns**

Create a table of expected rationalizations:
| Rationalization | Counter |
|----------------|---------|
| "The log clearly shows X" | Did you read the code that produces X, or are you inferring? |
| "This is probably caused by Y" | "Probably" — LIKELY or SPECULATIVE? What's the evidence chain? |
| "The fix would be to..." | This skill is read-only. No fix proposals. |
| (silence — no questions asked) | Missing information was assumed. Should have asked. |

---

### Task 2: GREEN — Write the Skill File

**Files:**
- Create: `C:\Users\xuxiao02\.claude\skills\investigate\SKILL.md`

- [ ] **Step 1: Create skill directory**

```bash
mkdir -p "C:\Users\xuxiao02\.claude\skills\investigate"
```

- [ ] **Step 2: Write SKILL.md with YAML frontmatter and full content**

Write the complete skill file based on the spec. Content must include:

```markdown
---
name: investigate
description: Use when asked to analyze a problem, investigate a bug, review code behavior, explain a log or error, or answer "why does X happen" — a read-only analysis skill that requires confidence ratings (CERTAIN/LIKELY/SPECULATIVE) on every claim to prevent guesses from being presented as facts
---

# Investigate

## Overview

Read-only analysis with mandatory confidence rating. Never modify code. Distinguish what you read from what you infer.

**Core principle:** If you didn't read it in the code or see it in a log, it's not a fact. Tag it.

## When to Use

Trigger: "Why does X happen?", "Analyze this", "Look at this log/error", "What could cause Y?", "Is this a bug?", "Review this code for issues"

Do NOT use when:
- Bug is confirmed and needs a fix → use `diagnose`
- Issue needs triage/labeling → use `triage`
- User explicitly says "fix it"

## Confidence Tiers

| Tier | Meaning | Example |
|------|---------|---------|
| **CERTAIN** | Directly observed in code/log/docs, indisputable | "`_integrate_forces()` calls `apply_impulse()` at line 42" |
| **LIKELY** | Evidence-backed inference with causal chain | "Given call chain A→B→C, B likely triggers the recontact" |
| **SPECULATIVE** | Possible direction, insufficient evidence | "Might be a race condition — needs log instrumentation to confirm" |

## Workflow

```
User asks "why X?" / "analyze Y"
    │
    ▼
1. COLLECT EVIDENCE
   - Read relevant code paths
   - Check logs / git / docs / ADRs
   - Try repro if feasible
    │
    ▼
2. CLASSIFY FINDINGS  ←── MANDATORY GATE
   - Tag each finding CERTAIN / LIKELY / SPECULATIVE
   - Identify information gaps → list specific questions
   - Do NOT output until every claim has a tag
    │
    ▼
3. OUTPUT REPORT
   - Observations (CERTAIN)
   - Causal chain (LIKELY, with evidence basis)
   - Possible directions (SPECULATIVE, with confirmation steps)
   - Open questions for the user
```

## Report Format

```markdown
## Analysis: <topic>

### Observations (CERTAIN)
- [CERTAIN] <fact read from code/log>
- [CERTAIN] <fact read from code/log>

### Causal Chain (LIKELY)
- [LIKELY] <inference> — basis: <evidence chain>

### Speculative Directions (SPECULATIVE)
- [SPECULATIVE] <possibility> — to confirm: <what to check>

### Questions for You
- <specific, actionable question>

### Overall Confidence: <Low / Medium / High>
```

## Rules

1. **Read-only** — read code, logs, git, docs. Never edit files.
2. **Every claim tagged** — no untagged statements in the report.
3. **Basis required for LIKELY** — state what evidence supports the inference.
4. **Confirmation step required for SPECULATIVE** — say what would verify or rule it out.
5. **Ask, don't assume** — missing information → question, not silent assumption.
6. **No fix proposals** — this is analysis, not implementation.

## Anti-Patterns

| Don't | Do |
|-------|-----|
| "The problem is X" (no tag, no evidence) | "[LIKELY] X — basis: call chain at L42-58" |
| "Probably a timing issue" (vague) | "[SPECULATIVE] Timing issue — to confirm: add timestamp log" |
| Silent assumption about intent | Ask: "Is `<behavior>` expected here?" |
| Proposing a code change | Note: "Possible direction (not implementing): ..." |
| Skipping the tag gate | Every claim in output MUST have [CERTAIN]/[LIKELY]/[SPECULATIVE] |

## Red Flags — STOP and Re-check

- Using definitive language for something you didn't read in code
- No [SPECULATIVE] tags in your report (no analysis is 100% certain)
- You're about to propose a fix instead of asking a question
- You haven't read any files yet but have conclusions
```

- [ ] **Step 3: Verify file was created correctly**

```bash
wc -l "C:\Users\xuxiao02\.claude\skills\investigate\SKILL.md"
```

Expected: ~120-150 lines. The file must be valid markdown with YAML frontmatter.

---

### Task 3: GREEN — Run Baseline Scenarios with Skill

**Files:**
- Modify: none

- [ ] **Step 1: Run Scenario A with the skill present**

Dispatch a subagent with the investigate skill loaded. Give it Scenario A from Task 1.
Verify the subagent:
- [ ] Uses [CERTAIN]/[LIKELY]/[SPECULATIVE] tags in output
- [ ] Reads code before making claims
- [ ] Distinguishes facts from inference
- [ ] Does NOT modify any files
- [ ] Asks questions when information is missing

- [ ] **Step 2: Run Scenario B with the skill present**

Same verification checklist as Step 1.

- [ ] **Step 3: Run Scenario C with the skill present**

Same verification checklist as Step 1.

- [ ] **Step 4: Document GREEN results**

Record whether the skill produces the desired behavior. Note any gaps.

---

### Task 4: REFACTOR — Close Loopholes

**Files:**
- Modify: `C:\Users\xuxiao02\.claude\skills\investigate\SKILL.md`

- [ ] **Step 1: Identify rationalizations from GREEN testing**

From Task 3 results, list any new rationalizations where the agent still made untagged claims or used definitive language for guesses.

- [ ] **Step 2: Add explicit counters to the skill**

For each new rationalization found, add an entry to the Anti-Patterns table or Red Flags list.

- [ ] **Step 3: Re-test with updated skill**

Re-run the scenario that exposed the loophole. Verify the updated skill closes it.

- [ ] **Step 4: Final verification checklist**

- [ ] All 3 scenarios produce tagged, honest output
- [ ] No files were modified during any test
- [ ] Agent asks questions when information is missing
- [ ] Every claim has a confidence tag
- [ ] LIKELY claims have basis stated
- [ ] SPECULATIVE claims have confirmation steps

---

### Task 5: Commit and Document

**Files:**
- Modify: none (skill lives in `~/.claude/skills/`, outside project repo)

- [ ] **Step 1: Commit the spec**

```bash
git add docs/superpowers/specs/2026-05-26-investigate-skill-design.md
git commit -m "docs(spec): add investigate skill design — lightweight analysis with confidence rating"
```

- [ ] **Step 2: Commit the plan**

```bash
git add docs/superpowers/plans/2026-05-26-investigate-skill-plan.md
git commit -m "docs(plan): add investigate skill implementation plan"
```

- [ ] **Step 3: Verify skill is registered**

```bash
ls -la "C:\Users\xuxiao02\.claude\skills\investigate\"
```

Expected: SKILL.md exists and is non-empty.
