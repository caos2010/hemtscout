---
name: hemt-paper-research-fast
description: Fast local HEMT paper research with automatic PDF sync and page-level evidence.
version: 0.5.2
metadata:
  hermes:
    tags: [research, papers, HEMT, semiconductor, RAG]
    category: research
---

# HEMT paper research

## When to use

For any question about HEMT, GaN, AlGaN, 2DEG, donor density, band offsets, mobility, dispersion, or papers in the local collection, search HEMTScout before answering. Do not claim that the library or a source is missing until you have attempted the workflow below. For unrelated questions, answer normally without forcing paper citations.

When this skill is listed as activated, its instructions are already available. Do not spend another model/tool turn calling `skill_view` or reloading it; proceed directly to the terminal workflow.

## Mandatory evidence gate

Never answer a paper-specific factual question from model memory. The retrieval command must finish successfully and return relevant source text. If it exits nonzero, errors, or returns no relevant passage, state that retrieval failed and stop; do not guess, infer material names, or present a likely answer as sourced. A failed terminal call is not evidence. For electron-transfer direction, follow the retrieved band-alignment statement (higher Ec to lower Ec) and name the materials only when the retrieved page identifies that mapping.

## Run sync and retrieval in one terminal call

On this Windows-native Hermes setup, the terminal tool runs through Git Bash. Use Bash syntax and `/c/...` paths. Never send PowerShell syntax (`Join-Path`, `$env:...`, `Set-Location`) to this tool, and do not retry the same command using a different shell.

Resolve the project directory in Bash so the skill also works after the project is moved or cloned:

```bash
project_root="${USERPROFILE:-$HOME}/Documents/Codex/2026-10-14/xaa/outputs/hemtscout"
if [[ -n "${HEMTSCOUT_HOME:-}" ]]; then
  project_root="$HEMTSCOUT_HOME"
fi
project_root="$(cygpath -u "$project_root")"
```

For each in-scope question, make one terminal call containing `cd`, `sync`, and the appropriate retrieval command, in that order. Example for an exact page:

```bash
cd "$project_root" || exit 2
./.venv/Scripts/python.exe -m hemtscout.cli sync
./.venv/Scripts/python.exe -m hemtscout.cli paper "hemt1.pdf" --from-page 2 --to-page 2
```

Use the final command appropriate to the question:

- Exact filename and page/range: `./.venv/Scripts/python.exe -m hemtscout.cli paper "<file>" --from-page <first> --to-page <last>`; honor the requested range.
- One topic: `./.venv/Scripts/python.exe -m hemtscout.cli search --limit 4 "<topic>"`.
- Deep, multi-part, or comparative question: split into at most 3 facets and run `search --limit 2` for each facet in the same terminal call. Include the requested filename in each query when given; combine Vietnamese and English technical terms when useful.

The sync command compares PDF size and modification time, indexing new or changed files in `data/papers` and skipping unchanged ones. If sync itself reports an error, still run retrieval so already indexed evidence can be used. If the working directory or `/c/...` path is missing, make at most one diagnostic call with `pwd` and `ls`; do not guess another path or retry PowerShell. Report the access failure plainly and use any evidence retrieval did return.

If retrieval returns no useful passage, make one shorter retry with the key English technical terms. Never use `ask` or `papers ask`, which starts another model and adds latency. Do not browse the web to extract local papers. Sync only indexes PDFs already in `data/papers`; it does not download papers or OCR scans.

## Answer

Answer in Vietnamese by default. Give the direct answer first and explain technical terms simply. Keep routine answers concise; for deep questions cover each requested part with clear headings or bullets.

Cite each paper-based claim with the exact filename and PDF page reported by HEMTScout, e.g. `[hemt1.pdf, trang PDF 2]`. Separate explicit paper findings from labeled inference. Preserve units, conditions, device names, and scope. Do not invent values or causal links. If retrieved evidence is insufficient, say what is missing; do not imply that a few excerpts cover all 34 papers.
