# HEMTScout for Hermes Agent

Trợ lý nghiên cứu paper HEMT chạy local trên Windows. Hermes Agent xử lý hội thoại; Ollama chạy model; HEMTScout trích xuất PDF, truy xuất đoạn liên quan, lưu thư viện SQLite và đo chất lượng truy xuất. Một MCP server stdio cục bộ cung cấp các công cụ `hemtscout_paper`, `hemtscout_search` và `hemtscout_papers` cho Hermes. Đọc PDF không cần gateway, tải tệp từ web hay gửi tài liệu lên dịch vụ đám mây.

## Phù hợp với laptop

Model mặc định là `hemt-qwen3-instruct:64k` (Qwen3 4B Q4_K_M), vì model 0.8B thường không gọi đúng công cụ hoặc bịa chi tiết kỹ thuật. Model 4B tốn nhiều RAM hơn và chậm hơn model 0.8B; đây là đánh trade-off để giữ khả năng đọc PDF qua công cụ. Context được đặt 65,536 token vì Hermes cần khoảng 64K cho agentic tools. Radeon iGPU không phải mục tiêu tăng tốc trong cấu hình Windows này.

> Tải model lần đầu cần Internet. Sau khi tải model và cài dependency, đọc/hỏi paper hoạt động local. Cấu hình máy/VRAM thực tế cần kiểm tra trên laptop vì số VRAM khác nhau theo SKU.

## Cài trên Windows PowerShell

1. Cài Ollama và Hermes Agent theo tài liệu chính thức.
2. Mở PowerShell tại thư mục này:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
ollama pull qwen3:4b-instruct
ollama create hemt-qwen3-instruct:64k -f .\Modelfile.hermes-qwen3-instruct-64k
```

3. Trong `%LOCALAPPDATA%\hermes\config.yaml`, đặt model mặc định là `hemt-qwen3-instruct:64k`, endpoint Ollama là `http://127.0.0.1:11434/v1`, context là `65536` và `agent.reasoning_effort: none`. Đăng ký MCP server `hemtscout` bằng `command` trỏ tới `.venv\Scripts\python.exe`, `args: ['-m', 'hemtscout.mcp_server']` và `cwd` là thư mục dự án. Chỉ bật các tool `hemtscout_paper`, `hemtscout_search` và `hemtscout_papers`.
4. Cài skill bằng `& .\install-hermes-skill.ps1`. Script chép `hemt-paper-research-fast` vào `%USERPROFILE%\AppData\Local\hermes\skills\research\` (hoặc thư mục `HERMES_HOME` nếu đã đặt). Quy tắc tiếng Việt và lời chào nằm trong `SOUL.md`. Tạo phiên Hermes mới sau khi đổi SOUL hoặc model; dùng `/reload-mcp` nếu vừa đổi cấu hình MCP trong phiên đang chạy.
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

MCP server đồng bộ các PDF mới hoặc đã đổi trước khi đọc/tìm kiếm; các tệp không thay đổi được giữ nguyên. Dùng `hemtscout sync --force` để tái lập chỉ mục toàn bộ thư viện.

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
