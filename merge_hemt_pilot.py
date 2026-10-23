"""Merge the four-example HEMT pilot LoRA into its exact local base model."""

from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

ROOT = Path(__file__).resolve().parent
BASE = ROOT / "models" / "Qwen3-0.6B"
ADAPTER = ROOT / "outputs" / "finetune" / "hemt_seed_lora"
MERGED = ROOT / "outputs" / "finetune" / "hemt_pilot_merged"

if not (ADAPTER / "adapter_config.json").is_file():
    raise FileNotFoundError(f"Không thấy LoRA adapter: {ADAPTER}")
if (MERGED / "model.safetensors").is_file() and (MERGED / "config.json").is_file():
    print(f"Merged pilot already exists: {MERGED}")
    raise SystemExit(0)

tokenizer = AutoTokenizer.from_pretrained(BASE, local_files_only=True)
model = AutoModelForCausalLM.from_pretrained(
    BASE,
    torch_dtype=torch.float16,
    device_map="cpu",
    local_files_only=True,
)
model = PeftModel.from_pretrained(model, ADAPTER, local_files_only=True)
model = model.merge_and_unload()
model.save_pretrained(MERGED, safe_serialization=True, max_shard_size="2GB")
tokenizer.save_pretrained(MERGED)
print(f"Merged pilot model: {MERGED}")
