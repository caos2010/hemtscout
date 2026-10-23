"""Tiny LoRA pilot using only the four examples in hemt_seed_train.jsonl.

This is a pipeline smoke-run, not a scientifically meaningful fine-tune.
It trains only on assistant responses and keeps the base model frozen.
"""

import json
from pathlib import Path

import torch
from peft import LoraConfig, get_peft_model
from transformers import AutoModelForCausalLM, AutoTokenizer, Trainer, TrainingArguments


ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "models" / "Qwen3-0.6B"
TRAIN_FILE = ROOT / "data" / "finetune" / "hemt_seed_train.jsonl"
OUTPUT_DIR = ROOT / "outputs" / "finetune" / "hemt_seed_lora"
MAX_LENGTH = 1024


def load_examples(tokenizer):
    records = [
        json.loads(line)
        for line in TRAIN_FILE.read_text(encoding="utf-8-sig").splitlines()
        if line.strip()
    ]
    examples = []
    for row_number, record in enumerate(records, start=1):
        messages = record.get("messages", [])
        if len(messages) < 3 or messages[-1].get("role") != "assistant":
            raise ValueError(f"Dòng {row_number}: cần conversation kết thúc bằng assistant.")

        prompt_encoded = tokenizer.apply_chat_template(
            messages[:-1],
            tokenize=True,
            add_generation_prompt=True,
        )
        full_encoded = tokenizer.apply_chat_template(
            messages,
            tokenize=True,
            add_generation_prompt=False,
        )
        prompt_ids = prompt_encoded["input_ids"]
        full_ids = full_encoded["input_ids"]
        if full_ids[: len(prompt_ids)] != prompt_ids:
            raise ValueError(f"Dòng {row_number}: prompt không khớp tiền tố conversation đầy đủ.")
        if len(full_ids) > MAX_LENGTH:
            raise ValueError(
                f"Dòng {row_number}: {len(full_ids)} token vượt MAX_LENGTH={MAX_LENGTH}."
            )
        labels = [-100] * len(prompt_ids) + full_ids[len(prompt_ids) :]
        examples.append({"input_ids": full_ids, "labels": labels})

    if not examples:
        raise ValueError(f"Không có mẫu nào trong {TRAIN_FILE}")
    return examples


class PadBatch:
    def __init__(self, pad_token_id):
        self.pad_token_id = pad_token_id

    def __call__(self, features):
        width = max(len(item["input_ids"]) for item in features)
        input_ids = torch.full((len(features), width), self.pad_token_id, dtype=torch.long)
        attention_mask = torch.zeros((len(features), width), dtype=torch.long)
        labels = torch.full((len(features), width), -100, dtype=torch.long)
        for index, item in enumerate(features):
            size = len(item["input_ids"])
            input_ids[index, :size] = torch.tensor(item["input_ids"], dtype=torch.long)
            attention_mask[index, :size] = 1
            labels[index, :size] = torch.tensor(item["labels"], dtype=torch.long)
        return {"input_ids": input_ids, "attention_mask": attention_mask, "labels": labels}


def main():
    if not torch.cuda.is_available():
        raise RuntimeError("PyTorch chưa thấy GPU CUDA. Dừng để tránh train nhầm trên CPU.")
    if not MODEL_DIR.is_dir():
        raise FileNotFoundError(f"Không thấy model local: {MODEL_DIR}")
    if not TRAIN_FILE.is_file():
        raise FileNotFoundError(f"Không thấy dataset seed: {TRAIN_FILE}")

    gpu = torch.cuda.get_device_name(0)
    vram_gb = torch.cuda.get_device_properties(0).total_memory / 1024**3
    print(f"GPU: {gpu} ({vram_gb:.2f} GiB)")
    print(f"Dataset: {TRAIN_FILE}")
    print("Lưu ý: 4 mẫu chỉ dùng để thử quy trình; mô hình có thể học thuộc, chưa đánh giá được năng lực HEMT.")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR, local_files_only=True)
    if tokenizer.pad_token_id is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"
    examples = load_examples(tokenizer)
    print(f"Số mẫu nạp được: {len(examples)}; chỉ tính loss trên câu trả lời assistant.")

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_DIR,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True,
        local_files_only=True,
    )
    model.to("cuda")
    model.config.use_cache = False
    model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
    if hasattr(model, "enable_input_require_grads"):
        model.enable_input_require_grads()

    lora = LoraConfig(
        task_type="CAUSAL_LM",
        r=8,
        lora_alpha=16,
        lora_dropout=0.05,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        bias="none",
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()

    args = TrainingArguments(
        output_dir=str(OUTPUT_DIR),
        per_device_train_batch_size=1,
        gradient_accumulation_steps=1,
        num_train_epochs=3,
        learning_rate=1e-4,
        optim="adamw_torch",
        fp16=True,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        logging_strategy="steps",
        logging_steps=1,
        logging_first_step=True,
        save_strategy="no",
        report_to="none",
        dataloader_pin_memory=False,
        remove_unused_columns=False,
        seed=42,
    )
    trainer = Trainer(
        model=model,
        args=args,
        train_dataset=examples,
        data_collator=PadBatch(tokenizer.pad_token_id),
        processing_class=tokenizer,
    )
    trainer.train()
    trainer.save_model(str(OUTPUT_DIR))
    tokenizer.save_pretrained(OUTPUT_DIR)
    print(f"LoRA pilot hoàn tất. Adapter được lưu tại: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
