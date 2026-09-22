# Two-Task Fixture Plan

A minimal plan file used by the load test: two independent tasks, each creating one file at the repo root, listed below.

## Task T1
- scope: Create `a.txt` at the repo root with a single placeholder line.
- files_owned: [a.txt]
- files_forbidden: [b.txt]
- depends_on: none
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `test -f a.txt`
- commit: feat: add a

## Task T2
- scope: Create `b.txt` at the repo root with a single placeholder line.
- files_owned: [b.txt]
- files_forbidden: [a.txt]
- depends_on: none
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `test -f b.txt`
- commit: feat: add b
