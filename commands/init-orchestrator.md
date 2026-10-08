---
description: Tạo khung dự án "Claude điều phối worker AI (mặc định Antigravity CLI)" (v3) trong một thư mục project mới hoặc trống
argument-hint: "[framework] [database] — vd: nextjs mongodb"
disable-model-invocation: true
---

Tạo khung orchestrator v3 trong thư mục làm việc hiện tại. Bộ mẫu nằm ở `~/.claude/templates/orchestrator/` (hướng dẫn đầy đủ: `orchestrator-guide.md` trong đó). Mọi file được chép bằng `scaffold.ps1` — KHÔNG tự gõ lại nội dung file mẫu.

Tham số: $ARGUMENTS

1. Nếu tham số là một câu hỏi hay yêu cầu khác (không phải tên framework/database) → trả lời yêu cầu đó, KHÔNG scaffold.
2. Stack: từ đầu tiên của tham số là framework, từ thứ hai là database. Không có tham số → hỏi người dùng framework và database; nếu họ chưa biết thì bỏ qua.
3. Chạy (thay `<HOME>` bằng thư mục người dùng, `<CWD>` bằng thư mục hiện tại; chỉ thêm `-Tech`/`-Db` khi đã biết):
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<HOME>/.claude/templates/orchestrator/scaffold.ps1" -Target "<CWD>" -Tech "<framework>" -Db "<database>"
   ```
   - Mã 0: xong.
   - Mã 2: thư mục không trống. Cho người dùng xem danh sách script in ra, nói rõ khung này dành cho project mới, hỏi có chắc không. Chỉ khi người dùng đồng ý mới chạy lại với `-AllowNonEmpty` (script không ghi đè file nào).
   - Mã 3: thư mục đã có khung orchestrator → báo người dùng, dừng.
   - Mã khác: báo nguyên văn lỗi, dừng.
4. Kiểm tra môi trường, chỉ báo chứ không cài: `git --version`, và các worker `agy --version` (Antigravity), `codex --version` (Codex/ChatGPT), `gemini --version`. Worker mặc định là `agy`; nếu máy không có `agy` mà có `codex` hoặc người dùng muốn dùng ChatGPT → hỏi người dùng rồi đổi `"worker"` trong `orchestrator.config.json` sang `"codex"`.
5. Nếu người dùng đã nói lệnh lint/build/test → điền mảng `checks` trong `orchestrator.config.json` theo mẫu `checks_example`. Chưa biết thì để trống.
6. Không `git init`, không commit, trừ khi người dùng yêu cầu.
7. Cây thư mục đã được script in ra. Nhắc người dùng những việc còn lại trước task đầu tiên:
   - Đăng nhập worker đang chọn nếu chưa: `agy` (chạy `agy` một lần ở chế độ tương tác) — config đã có `--mode accept-edits` để agy ghi được file khi chạy không tương tác hoặc `codex` (`codex login` bằng tài khoản ChatGPT).
   - Điền `checks` trong `orchestrator.config.json`.
   - `git init` và commit khung (cần ít nhất một commit trước khi `start-task.ps1` tạo nhánh).
   - `docs/`, `memory/`, `.claude/skills/*` hiện chỉ là khung rỗng, sẽ được điền dần khi có task thật.
   - Bắt đầu bằng `/orchestrator <yêu cầu>` hoặc `/feature <mô tả>`.
