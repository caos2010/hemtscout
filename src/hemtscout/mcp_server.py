"""Small stdio MCP server exposing HEMTScout's local PDF index to Hermes."""

from __future__ import annotations

import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any

from hemtscout.cli import PAPER_DIR, list_papers, print_paper, print_search, sync_papers


SERVER_INFO = {"name": "hemtscout-local", "version": "0.1.0"}
TOOLS = [
    {
        "name": "hemtscout_paper",
        "description": (
            "Đọc PDF đã có trong thư viện cục bộ HEMTScout. Dùng khi người dùng nêu tên PDF; "
            "không tải tệp, không mở web. Trả văn bản trích xuất có số trang PDF."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "filename": {
                    "type": "string",
                    "description": "Tên tệp PDF chính xác, ví dụ hemt1.pdf",
                },
                "from_page": {"type": "integer", "description": "Trang đầu tùy chọn"},
                "to_page": {"type": "integer", "description": "Trang cuối tùy chọn"},
            },
            "required": ["filename"],
            "additionalProperties": False,
        },
    },
    {
        "name": "hemtscout_search",
        "description": (
            "Tìm đoạn liên quan trong các PDF HEMT đã nạp. Dùng cho câu hỏi cần căn cứ từ thư viện."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "question": {"type": "string", "description": "Chủ đề hoặc câu hỏi ngắn"},
                "limit": {"type": "integer", "description": "Số đoạn trả về, từ 1 đến 8"},
            },
            "required": ["question"],
            "additionalProperties": False,
        },
    },
    {
        "name": "hemtscout_papers",
        "description": "Liệt kê tên các PDF đã nạp vào thư viện HEMTScout.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
]
TOOL_NAMES = {tool["name"] for tool in TOOLS}


def _capture(call: Any) -> str:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        call()
    return buffer.getvalue().strip()


def _read_paper(arguments: dict[str, Any]) -> str:
    filename = arguments.get("filename")
    if not isinstance(filename, str) or not filename.strip():
        raise ValueError("Cần tên tệp PDF, ví dụ hemt1.pdf.")
    filename = filename.strip()
    if Path(filename).name != filename or not filename.lower().endswith(".pdf"):
        raise ValueError("Chỉ nhận tên tệp PDF trong thư viện, không nhận đường dẫn ngoài.")
    if not (PAPER_DIR / filename).is_file():
        raise FileNotFoundError(f"Không có {filename} trong thư viện {PAPER_DIR}.")

    page_from = int(arguments.get("from_page") or 0)
    page_to = int(arguments.get("to_page") or 0)
    if page_from < 0 or page_to < 0:
        raise ValueError("Số trang phải là số dương.")

    def read() -> None:
        sync_papers()
        print_paper(filename, page_from, page_to)

    result = _capture(read)
    if not result or "Không tìm thấy" in result:
        raise RuntimeError(result or f"HEMTScout không trích xuất được {filename}.")
    return result


def _search(arguments: dict[str, Any]) -> str:
    question = arguments.get("question")
    if not isinstance(question, str) or not question.strip():
        raise ValueError("Cần nhập chủ đề muốn tìm trong thư viện.")
    limit = max(1, min(int(arguments.get("limit") or 4), 8))
    return _capture(lambda: (sync_papers(), print_search(question.strip(), limit)))


def _papers() -> str:
    return _capture(lambda: (sync_papers(), list_papers()))


def _tool_call(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "hemtscout_paper":
        text = _read_paper(arguments)
    elif name == "hemtscout_search":
        text = _search(arguments)
    elif name == "hemtscout_papers":
        text = _papers()
    else:
        raise ValueError(f"Công cụ không tồn tại: {name}")
    return {"content": [{"type": "text", "text": text}], "isError": False}


def _handle(message: dict[str, Any]) -> dict[str, Any] | None:
    request_id = message.get("id")
    method = message.get("method")
    params = message.get("params") or {}

    if method == "notifications/initialized" or method == "notifications/cancelled":
        return None
    if method == "initialize":
        requested_version = params.get("protocolVersion", "2024-11-05")
        supported = {"2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"}
        version = requested_version if requested_version in supported else "2025-03-26"
        result = {
            "protocolVersion": version,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": SERVER_INFO,
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        tool_name = (params.get("name") or "").strip()
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            arguments = {}
        try:
            result = _tool_call(tool_name, arguments)
        except Exception as exc:  # Return useful diagnostics through MCP, never stdout logs.
            result = {"content": [{"type": "text", "text": str(exc)}], "isError": True}
    else:
        if request_id is None:
            return None
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": f"Method not found: {method}"},
        }

    if request_id is None:
        return None
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def main() -> None:
    if hasattr(sys.stdin, "reconfigure"):
        sys.stdin.reconfigure(encoding="utf-8", errors="replace")
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
            response = _handle(message)
        except Exception as exc:
            response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": str(exc)},
            }
        if response is not None:
            sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
