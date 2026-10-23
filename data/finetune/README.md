# Fine-tuning data

Use this folder for reviewed examples in JSONL chat format. Each record should have a `messages` array with `system`, `user`, and `assistant` roles. Do not train on copyrighted full papers without permission; prefer your own concise, cited notes and question/answer examples. Keep a separate held-out evaluation set and never put its answers in training data.

Example:

```json
{"messages":[{"role":"system","content":"Answer from provided paper excerpts and cite sources."},{"role":"user","content":"Excerpt: ...\nQuestion: ..."},{"role":"assistant","content":"... [Author, year, DOI]"}]}
```

For this laptop, begin with retrieval-augmented generation (RAG), not fine-tuning. A 4 GB GTX 1650 Ti is constrained for training; use a small LoRA/QLoRA experiment on a supported Linux/WSL or cloud environment, then evaluate the adapter before deploying it back in local inference. Fine-tuning teaches response format/task behavior; it is not a reliable way to store a changing paper library.
