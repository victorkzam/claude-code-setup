---
name: search
description: "Multi-source web research to confirm approaches and find best practices. Use when the user says /search, asks to 'research this', 'look this up', 'confirm this approach', 'find best practices for', 'what's the current consensus on', or needs to cross-reference sources. Covers any domain: coding, business, finance, legal, product, UX, AI/ML, marketing, growth, and more. Trigger proactively when a question would clearly benefit from current web data rather than training knowledge alone."
argument-hint: [--quick] <query>
---

# Multi-Source Web Research

Research any topic by cross-referencing multiple search sources with varied angles. Produce structured, citation-backed findings with a confidence assessment.

## Arguments

The user invoked this with: $ARGUMENTS

Parse the arguments:
- If `$ARGUMENTS` starts with `--quick`, activate **quick mode** and treat the rest as the query.
- If `$ARGUMENTS` starts with `--deep`, this skill has no separate deep-research mode — degrade gracefully to **default mode** (the standard 3-angle search below) using the rest of the text as the query.
- Otherwise, use **default mode** with the full text as the query.

## Step 1: Detect available search sources

Check which MCP tools are available in this session by looking for these specific tools:

- **Context7**: Tools `mcp__context7__resolve-library-id` and `mcp__context7__query-docs` — use for coding documentation lookups (version-specific official docs)
- **Exa**: Tool `mcp__exa__web_search_exa` (primary), `mcp__exa__crawling_exa` (for deep fetching) — use for semantic/conceptual research queries (finds related content by meaning, not just keywords)
- **WebSearch**: Built-in, always available as baseline for general-purpose searches

If an MCP tool is unavailable, fall back to WebSearch for that angle. Never error out due to missing MCPs.

## Error Detection & Fallback Rules

- If any MCP tool call (Exa, Context7) returns an error or empty result, retry ONCE with a simplified query before falling back to WebSearch.
- If the retry also fails, fall back to WebSearch for that angle and report inline: "Note: [Exa/Context7] was unavailable after retry, fell back to WebSearch."
- Never silently swallow errors. If all 3 angles complete but one returned nothing useful, note it in the output.

Note: Time-based timeouts (e.g., "fall back after 15s") are NOT enforceable at the skill level — MCP timeouts are a platform concern.

## Step 2: Detect domain(s)

Auto-detect from query keywords. Domains can overlap — a query may span multiple:

- **Coding**: library/framework names, architecture patterns, errors, APIs, debugging, testing
- **AI/ML**: model names, training, inference, papers, prompts, agents, embeddings, fine-tuning
- **Business/Strategy**: market sizing, pricing, GTM, competition, fundraising, positioning
- **Finance/Legal**: tax, accounting, incorporation, compliance, equity, SAFE, cap table, revenue
- **Product/UX**: design patterns, user research, conversion, analytics, usability, wireframes
- **Marketing/Growth**: SEO, content strategy, paid ads, viral loops, community, acquisition, retention
- **General**: anything that doesn't clearly fit the above

## Step 3: Execute searches

### Quick mode (`--quick`)

Single-angle fast lookup. No parallel searches, no WebFetch.

1. **Domain check**: If the query is coding-domain (library, framework, API, error), use Context7 as the single source (faster, more precise for docs). Otherwise, use WebSearch with "[topic] [current year]".
2. Return a 2-3 bullet summary with source links.
3. Format:

```
## [Query]

### Quick Answer
- [2-3 bullets with citations]

### Sources
- [Title](URL) — description
```

### Default mode

Run 3 searches IN PARALLEL, each with a meaningfully different angle and query formulation:

**Angle 1 — Authoritative/official**
- Goal: Find the canonical, institutional, or official perspective
- Coding domain: Use Context7 if available (fetches version-specific official docs directly), otherwise WebSearch targeting official docs
- Other domains: Use WebSearch targeting authoritative sources
- Query style: "[topic] official documentation" or "[topic] methodology definition"

**Angle 2 — Practitioner/community**
- Goal: Real-world experience, case studies, lessons from practitioners
- Use WebSearch with current year appended for freshness
- Query style: "[topic] best practices real world experience [current year]"

**Angle 3 — Contrarian/risk**
- Goal: Find pitfalls, gotchas, failures, critical viewpoints
- Use Exa if available (semantic search finds conceptually related warnings/critiques), otherwise WebSearch
- Query style: "[topic] pitfalls common mistakes failure" or "why not to [topic]"

Each query MUST be substantively different — not three rephrasings of the same search.

After searches complete, use WebFetch on the 2-3 most authoritative URLs:
- Prefer primary sources over aggregators
- Prefer recent content over old
- Diversify: don't fetch 3 pages from the same domain
- Skip WebFetch if the search snippet already provides sufficient detail

## Step 4: Output

### Default mode format

```
## [Query]

### Key Findings
- [3-5 cross-referenced bullets, each citing at least one source]

### Watch Out For
- [Gotchas, deprecations, version-specific issues, contrarian views found in Angle 3]

### Confidence: [High/Medium/Low]
[One-line justification]

### Sources
- [Title](URL) — one-line description
```

## Quality rules

- Every finding must cite at least one source — no unsourced claims.
- If sources conflict, present both sides explicitly. Do not silently pick one.
- Flag if all sources are older than 1 year for time-sensitive topics.
- Always include the current year in at least one search query per angle for freshness.
- If a section has no findings, include it with "No data found for this angle" rather than omitting it. This makes output structure predictable for the user.
- If the same URL appears in results from multiple angles, cite it once in Key Findings and note which angles it satisfied (e.g., "[source] — confirmed by both authoritative and practitioner angles").
- Confidence levels:
  - **High**: 3+ independent sources agree, sources are recent and authoritative
  - **Medium**: 2 sources agree, or sources are recent but limited in number
  - **Low**: Single source only, sources are outdated, or sources actively contradict each other
