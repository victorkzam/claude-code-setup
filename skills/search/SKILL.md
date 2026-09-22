---
name: search
description: "Multi-source web research to confirm approaches and find best practices. Use when the user says /cw:search, asks to 'research this', 'look this up', 'confirm this approach', 'find best practices for', 'what's the current consensus on', or needs to cross-reference sources. Covers any domain: coding, business, finance, legal, product, UX, AI/ML, marketing, growth. Trigger proactively when a question would clearly benefit from current web data rather than training knowledge alone."
argument-hint: "[--quick | --deep] <query>"
---

# Multi-Source Web Research

Cross-reference several search sources with deliberately different angles, then
produce structured, citation-backed findings with a confidence assessment.

## Arguments
The user invoked this with: $ARGUMENTS

- `--quick` → quick mode; the rest is the query.
- `--deep` → hand off to the bundled `/deep-research` skill, which runs a much
  wider multi-agent sweep. It needs dynamic workflows enabled; if that is
  unavailable, say so and fall back to default mode here.
- otherwise → default mode with the whole text as the query.

## Step 1: Source detection
Check which tools this session actually has:

- **Context7** — `mcp__context7__resolve-library-id`, `mcp__context7__query-docs`:
  version-specific official docs for library and framework questions.
- **Exa** — `mcp__exa__web_search_exa` (primary), `mcp__exa__crawling_exa` (deep
  fetch): semantic research that finds related material by meaning.
- **WebSearch** — built in, always available, the baseline for everything else.

Source detection never hard-fails: a missing MCP server degrades that angle to
WebSearch.

### Fallback rules
- An MCP call that errors or returns nothing: retry once with a simplified
  query, then fall back to WebSearch for that angle and say so inline — "Note:
  Exa was unavailable after retry, fell back to WebSearch."
- Do not swallow errors silently. If all angles completed but one returned
  nothing useful, note it in the output.
- Time-based timeouts are not enforceable from a skill; MCP timeouts are a
  platform concern.

## Step 2: Detect the domain(s)
Auto-detect from the query; domains overlap freely.

- **Coding** — libraries, frameworks, architecture patterns, errors, APIs, tests
- **AI/ML** — models, training, inference, papers, prompts, agents, embeddings
- **Business/strategy** — market sizing, pricing, GTM, competition, fundraising
- **Finance/legal** — tax, accounting, incorporation, compliance, equity, SAFEs
- **Product/UX** — design patterns, user research, conversion, analytics
- **Marketing/growth** — SEO, content, paid ads, community, acquisition
- **General** — anything else

## Step 3: Search

### Quick mode (`--quick`)
Single-angle lookup, no parallel searches, no WebFetch. Coding-domain query →
Context7 as the single source; otherwise WebSearch with "[topic] [current
year]". Return 2–3 bullets with source links under `### Quick Answer`, then
`### Sources`.

### Default mode — the three-angle sweep
Run three searches in parallel, each a substantively different query, not three
rephrasings of one.

1. **Authoritative/official** — the canonical or institutional view. Coding
   domain: Context7 when available, else WebSearch aimed at official docs.
   Query style: "[topic] official documentation", "[topic] methodology".
2. **Practitioner/community** — real-world experience, case studies, lessons.
   WebSearch with the current year appended. Query style: "[topic] best
   practices real world experience [current year]".
3. **Contrarian/risk** — pitfalls, gotchas, failures, critiques. Exa when
   available, else WebSearch. Query style: "[topic] pitfalls common mistakes",
   "why not to [topic]".

Then WebFetch the two or three most authoritative URLs: primary sources over
aggregators, recent over old, and diversify domains. Skip the fetch when the
search snippet already carries enough detail.

## Step 4: Output

```
## [Query]

### Key Findings
- [3-5 cross-referenced bullets, each citing at least one source]

### Watch Out For
- [gotchas, deprecations, version-specific issues, contrarian findings]

### Confidence: [High/Medium/Low]
[one-line justification]

### Sources
- [Title](URL) — one-line description
```

## Quality rules
- Every finding cites at least one source; no unsourced claims.
- Conflicting sources are presented as a conflict, not silently resolved.
- Flag it when every source is over a year old on a time-sensitive topic.
- Put the current year in at least one query per angle.
- A section with no findings still appears, marked "No data found for this
  angle", so the shape of the output is predictable.
- A URL that surfaced in several angles is cited once, noting which angles it
  satisfied.
- Confidence: **High** = 3+ independent, recent, authoritative sources agree;
  **Medium** = 2 agree, or recent but few; **Low** = single, outdated, or
  contradictory sources.
