# HEMTScout for Hermes Agent

Trợ lý nghiên cứu paper HEMT chạy local trên Windows. Hermes Agent là lớp hội thoại/skill; Ollama chạy model; HEMTScout trích xuất PDF, truy xuất đoạn liên quan, lưu thư viện SQLite và đo chất lượng truy xuất. Paper và câu hỏi không gửi lên dịch vụ đám mây bởi ứng dụng này.

## Phù hợp với laptop

Ryzen 5 4600H có thể chạy CPU inference; GTX 1650 Ti thường có 4 GB VRAM. Bắt đầu với `qwen3:4b` lượng tử hóa (khoảng 2.5 GB tải mô hình, ngoài ra cần VRAM/RAM cho context và runtime). Nếu bị out-of-memory hoặc chạy quá chậm, thử `qwen3:1.7b`. Giảm context trước khi tăng model. Radeon iGPU không phải mục tiêu tăng tốc trong cấu hình Windows này; Ollama có thể dùng NVIDIA nếu driver/CUDA runtime được hỗ trợ.

> Tải model lần đầu cần Internet. Sau khi tải model và cài dependency, đọc/hỏi paper hoạt động local. Cấu hình máy/VRAM thực tế cần kiểm tra trên laptop vì số VRAM khác nhau theo SKU.

## Cài trên Windows PowerShell

1. Cài Ollama và Hermes Agent theo tài liệu chính thức.
2. Mở PowerShell tại thư mục này:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
ollama pull qwen3:4b
```

3. Hermes cần model đủ mạnh để gọi công cụ. Tạo alias giới hạn context của Qwen3 ở 65536 để Ollama không cấp phát toàn bộ context native 262144 (đã gây lỗi thiếu 36 GiB KV cache): `ollama create hemt-qwen3:64k -f .\outputs\finetune\Modelfile.hermes-qwen3-64k`. Dùng `hemt-qwen3:64k` làm model hội thoại Hermes; giữ `qwen3:4b` cho lệnh HEMTScout và `hemt-pilot` cho thử nghiệm riêng. Hermes dùng endpoint `http://127.0.0.1:11434/v1` và context 65536. Sau khi alias được tạo, cấu hình Hermes local dùng alias này; thoát rồi khởi chạy lại Hermes.
4. Cài skill bằng `& .\install-hermes-skill.ps1`. Script chép `hemt-paper-research-fast` vào `%LOCALAPPDATA%\hermes\skills\research\` (hoặc thư mục `HERMES_HOME` nếu đã đặt). Sau khi cập nhật skill, chạy `/reset` trong Hermes để nạp hướng dẫn mới.
5. Chạy `hemtscout --help` để xem lệnh. Nếu Windows chưa nhận script sau khi cài editable, dùng `python -m hemtscout.cli ...` với Python trong `.venv`.

## Quy trình đọc paper

```powershell
New-Item -ItemType Directory -Force data\papers
Copy-Item "D:\papers\*.pdf" data\papers\
hemtscout ingest-all
hemtscout papers
hemtscout search --limit 8 "So sánh các phương pháp enhancement-mode trong AlGaN/GaN HEMT"
hemtscout ask --limit 8 "So sánh các phương pháp enhancement-mode trong AlGaN/GaN HEMT"
hemtscout paper hemt12.pdf --from-page 3 --to-page 5
```

Nạp PDF cá nhân hoặc paper mà bạn có quyền sử dụng. Parser trích text từ PDF; PDF scan cần OCR trước. Có thể thêm title/DOI khi nạp một file: `hemtscout ingest paper.pdf --title "..." --doi "10...."`.

## Học fine-tune có đánh giá

1. Trước hết tạo một baseline RAG trên các paper và câu hỏi bạn tự kiểm tra.
2. Điền `data/eval/hemt_eval.csv`: câu hỏi, tên file kỳ vọng, đáp án tham chiếu; hiện bộ khung có 3 câu mẫu nhưng chưa gán expected file, nên cần sửa theo tài liệu của bạn.
3. Chạy `hemtscout eval`. Chỉ số hiện tại là Recall@6 theo đúng tên file; xem JSON chi tiết tại `data/eval/latest_retrieval_eval.json`. Chấm thêm câu trả lời bằng rubric: đúng sự kiện, trích đúng nguồn/trang, không bịa, thừa nhận thiếu bằng chứng.
4. Tạo tập JSONL đã được người đọc paper rà soát trong `data/finetune/`. Tách train/validation/test theo paper hoặc DOI để tránh rò rỉ nội dung tương tự.
5. Thử LoRA/QLoRA trên môi trường tương thích (thường Linux/WSL hoặc máy/cloud có GPU VRAM lớn hơn). Giữ base model và adapter riêng; so sánh trước/sau trên cùng held-out set. Chỉ dùng adapter nếu citation accuracy và factuality không giảm.

4 GB VRAM quá chật cho fine-tuning thoải mái, đặc biệt với Windows CUDA stack. Không khuyến nghị full fine-tune. Dự án hiện cung cấp định dạng dữ liệu + evaluation loop, chưa tự huấn luyện adapter. Với cấu hình này, RAG giúp truy xuất hàng trăm paper hiệu quả hơn việc nhồi paper vào fine-tune.

## Lệnh hữu ích

Skill Hermes chạy `hemtscout sync` trước mỗi câu hỏi. Windows-native Hermes dùng Git Bash cho terminal, vì vậy skill dùng đường dẫn `/c/Users/...` và cú pháp Bash; không dùng PowerShell trong terminal tool. Sync chỉ kiểm tra kích thước và thời gian sửa đổi PDF rồi nạp file mới hoặc đã đổi; file không đổi được bỏ qua. Dùng `hemtscout sync --force` để tái lập chỉ mục toàn bộ thư viện.

- `hemtscout ingest <pdf> [--title ...] [--doi ...]`
- `hemtscout ingest-all`
- `hemtscout papers`
- `hemtscout ask "câu hỏi"`
- `hemtscout eval`

## Giới hạn hiện tại

- Chưa tải tự động paper từ internet, Crossref hay arXiv; bạn tự quản lý danh sách và file PDF.
- Tìm kiếm dùng BM25 trên text đã trích, gồm tiêu đề/tên file và mở rộng một số từ khóa HEMT Việt–Anh; chưa dùng embedding/semantic search.
- Chưa OCR PDF scan, chưa tạo model adapter, chưa có chấm tự động đáp án LLM.
- Metadata DOI/title chỉ chính xác khi có trong PDF hoặc bạn khai báo lúc ingest.

## Tài liệu chính thức

- [Hermes Agent: Windows native](https://hermes-agent.nousresearch.com/docs/user-guide/windows-native)
- [Hermes Agent: Ollama/local providers](https://hermes-agent.nousresearch.com/docs/integrations/providers/)
- [Hermes Agent: creating skills](https://hermes-agent.nousresearch.com/docs/guides/work-with-skills/)
- [Ollama: Qwen3 4B model](https://ollama.com/library/qwen3:4b)
- [Hugging Face PEFT: LoRA](https://huggingface.co/docs/peft/en/package_reference/lora)
