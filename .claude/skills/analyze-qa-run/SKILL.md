---
name: analyze-qa-run
description: Analyse the latest GitHub Actions QA run for the current PCP repository and branch. Detects repo/branch automatically from local git context.
aliases: [qa-analysis, check-qa-run, qa-report]
tools: Bash, Glob, Grep, Read, WebFetch
---

# PCP QA Run Analyser

Analyses the latest GitHub Actions run of the `qa-macos.yml` workflow, detecting
the repository and branch automatically from the local git context.

## Usage

```
/analyze-qa-run
```

## What This Does

1. Fetches the latest workflow run status via `gh` CLI
2. If successful — reports success briefly and stops
3. If failed — downloads the `qa-logs` artifact and job logs, then:
   - Extracts test pass/fail statistics from `check.log`
   - Categorises failures from `.bad` files by error type
   - Sorts failure categories by frequency (most common first)
   - Compares with the previous run to measure progress
   - Reviews recent commits and assesses their impact

## When to Use

- After a push to `macos-qa-uplift` to check if the CI run passed
- Before starting work on new fixes, to understand the current failure landscape
- To assess whether recent commits actually resolved any test failures
- When another agent needs context on the QA state before suggesting changes

## Output

A structured markdown report covering:
- Run status and basic metadata
- Test statistics table
- Ranked failure category table
- Deep-dive on the top 3 failure types with sample output
- Commit impact assessment comparing this run to the previous

---

When invoked, immediately use the Task tool to launch the `pcp-qa-run-analyzer` agent
with the prompt: "Analyse the latest GitHub Actions QA run for this repository and
produce a full failure analysis report."
