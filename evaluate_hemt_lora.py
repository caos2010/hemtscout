"""Compare the base model and HEMT LoRA adapter on an unseen paper excerpt."""

from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer


ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "models" / "Qwen3-0.6B"
ADAPTER_DIR = ROOT / "outputs" / "finetune" / "hemt_seed_lora"

SYSTEM = (
    "Bạn là trợ lý phân tích paper HEMT. Chỉ dùng đoạn trích được cung cấp; "
    "giữ nguyên điều kiện đo, phân biệt dữ kiện với cơ chế được đề xuất, "
    "nêu rõ giới hạn nếu nguồn nói còn tranh luận và ghi nguồn/trang PDF."
)
USER = (
    "Nguồn: hemt2.pdf, trang PDF 6. Đoạn trích: Phép đo AC được thực hiện bằng cách "
    "bias thiết bị vào pinch-off rồi dùng xung gate 80 µs để cố khôi phục dòng kênh. "
    "Dòng AC cực đại thấp hơn dòng DC; độ chênh được gọi là dispersion. Một cơ chế "
    "được đề xuất là electron từ gate điền vào surface donor khi pinch-off, làm giảm "
    "2DEG; trap có hằng số thời gian dài không đáp ứng kịp dưới AC, làm giảm dòng kênh "
    "và tăng on-resistance. Bài nói SiN passivation loại bỏ hiệu ứng trong kết quả "
    "trình bày, nhưng cơ chế chính xác còn tranh luận. Hãy giải thích dispersion, "
    "cơ chế được đề xuất và giới hạn của kết luận."
)


def answer(model, tokenizer, device):
    encoded = tokenizer.apply_chat_template(
        [{"role": "system", "content": SYSTEM}, {"role": "user", "content": USER}],
        tokenize=True,
        add_generation_prompt=True,
        enable_thinking=False,
    )
    input_ids = torch.tensor([encoded["input_ids"]], dtype=torch.long, device=device)
    attention_mask = torch.ones_like(input_ids)
    with torch.inference_mode():
        output = model.generate(
            input_ids=input_ids,
            attention_mask=attention_mask,
            max_new_tokens=300,
            do_sample=False,
            pad_token_id=tokenizer.pad_token_id,
        )
    return tokenizer.decode(output[0, input_ids.shape[1] :], skip_special_tokens=True).strip()


def main():
    if not torch.cuda.is_available():
        raise RuntimeError("Không thấy GPU CUDA; dừng để tránh chạy suy luận trên CPU.")
    if not ADAPTER_DIR.is_dir():
        raise FileNotFoundError(f"Không thấy LoRA adapter: {ADAPTER_DIR}")

    device = "cuda"
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR, local_files_only=True)
    if tokenizer.pad_token_id is None:
        tokenizer.pad_token = tokenizer.eos_token
    base = AutoModelForCausalLM.from_pretrained(
        MODEL_DIR,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True,
        local_files_only=True,
    ).to(device)
    base.eval()

    print("=== Model gốc ===")
    print(answer(base, tokenizer, device))

    tuned = PeftModel.from_pretrained(base, ADAPTER_DIR, local_files_only=True)
    tuned.eval()
    print("\n=== Model + LoRA adapter ===")
    print(answer(tuned, tokenizer, device))
    print("\nĐối chiếu với đoạn trích hemt2.pdf, trang PDF 6; đây là kiểm tra định tính, không phải đánh giá tổng quát.")


if __name__ == "__main__":
    main()
