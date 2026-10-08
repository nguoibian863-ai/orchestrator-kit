---
description: Triển khai một feature theo quy trình orchestrator — Claude thiết kế, điều phối, review; worker AI (mặc định Antigravity CLI) viết code
argument-hint: <mô tả feature>
---

Feature cần làm: $ARGUMENTS

## Quy ước

- Gọi script từ thư mục gốc project: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<tên>.ps1 <tham số>`. Bên dưới chỉ ghi `scripts/<tên>.ps1 <tham số>`.
- **Mã thoát của script là quyết định.** Không tự đọc log rồi "cho qua" khi script trả mã lỗi.
- Không tự sửa file trong `state/` — chỉ ghi qua `update-state.ps1`, `update-workflow.ps1`, `start-task.ps1`.
- `run-worker.ps1` có thể chạy tới `worker.timeout_sec` giây (mặc định 540): đặt timeout của lệnh shell 600000 ms, hoặc chạy nền rồi chờ thông báo hoàn tất.
- Subagent ghi kết quả ra file và chỉ trả về tóm tắt ngắn — không chép nội dung file vào hội thoại.
- Tạo/sửa file (prompt, do-not-modify, memory, báo cáo) bằng công cụ Write/Edit, không dùng heredoc hay `echo >` trong shell — tránh bị hỏi quyền thừa và lỗi mã hoá trên Windows.

## 0. Chuẩn bị

1. Đọc `state/workflow-state.json` và `state/task-state.json`. Nếu có feature khác chưa `done`, hoặc task chưa `approved`/`blocked` → báo người dùng, hỏi tiếp tục hay bỏ. Không tự bắt đầu feature mới.
2. Kiểm tra `orchestrator.config.json` có `checks`. Nếu trống → hỏi người dùng lệnh lint/build/test và điền vào (theo mẫu `checks_example`) trước khi code.
3. Đặt `<slug>` (chữ thường, `-`) và tiền tố ID task cho feature. Chạy `scripts/update-workflow.ps1 -Feature "<tên ngắn>" -Phase designing`. Mã 3 → hỏi người dùng.

## 1. Tri thức và thiết kế

1. Đọc `memory/summary.md` (chỉ mở `architecture.md`/`decisions.md` khi cần chi tiết).
2. Nếu feature có tài liệu/API bên ngoài liên quan → gọi subagent `retriever` (thư mục `tasks/feature-<slug>/`).
3. Gọi subagent `architect` → `tasks/feature-<slug>/design.md`. Có "Điểm chưa rõ" → hỏi người dùng trước khi đi tiếp. Có "Thay đổi kiến trúc" → tóm tắt cho người dùng và chờ đồng ý.

## 2. Chia task

1. `scripts/update-workflow.ps1 -Phase planning`
2. Gọi subagent `planner` → `tasks/feature-<slug>/plan.md`.
3. Với mỗi task theo thứ tự: `scripts/update-state.ps1 -TaskId <ID> -Status planned -Title "<tiêu đề>"`

## 3. Thực hiện từng task (theo thứ tự phụ thuộc)

`scripts/update-workflow.ps1 -Phase implementing`, rồi với mỗi task `<ID>`:

**a. Nhánh riêng** — `scripts/start-task.ps1 -TaskId <ID>`. Mã khác 0 → dừng, báo người dùng nguyên văn lỗi.

**b. Prompt** — viết `tasks/<ID>/prompt.md` theo `.claude/orchestrator/worker-prompt.md`, và `tasks/<ID>/do-not-modify.txt` (mỗi dòng một glob, lấy từ "Không được sửa" trong plan).

**c. Worker** — `scripts/update-state.ps1 -TaskId <ID> -Status implementing`, rồi `scripts/run-worker.ps1 -TaskId <ID>`. Worker mặc định theo `"worker"` trong `orchestrator.config.json`; chỉ thêm `-Worker <tên>` (ví dụ `codex`, `agy`, `gemini-cli`) khi người dùng yêu cầu worker khác:

| Mã | Xử lý |
|---|---|
| 0 | Đọc `tasks/<ID>/output.md` và `changed-files.txt`, sang bước d. Script in `CẢNH BÁO: worker bị từ chối ...` → ghi nhận để nêu trong tổng kết |
| 6 | Worker sửa file bị cấm hoặc sửa `.git/` (hook, config, info) → DỪNG, báo người dùng danh sách file. Không tự hoàn tác, không chạy lệnh git nào (commit, checkout...) |
| 1, 3, 5, 7, 8, 9, 10, 11, 124 | DỪNG, báo người dùng thông điệp của script (kèm đường dẫn `worker.log`/`output.md`). Không tự đoán kết quả |

**d. Kiểm tra tự động** — `scripts/run-checks.ps1 -TaskId <ID>`:
- 0 → `scripts/update-state.ps1 -TaskId <ID> -Status checked`, sang bước e.
- 1 → sang bước g, lỗi lấy từ phần cuối log mà script in ra (log đầy đủ: `tasks/<ID>/checks.log`).
- 2 → hỏi người dùng lệnh kiểm tra, điền `checks`, chạy lại bước d.

**e. Review** — `scripts/update-state.ps1 -TaskId <ID> -Status reviewing` và `scripts/update-workflow.ps1 -Phase review-loop`. Gọi **song song** 3 subagent `reviewer`, `security`, `qa` với TaskId; mỗi agent tự ghi `tasks/<ID>/<tên>-output.md`.

**f. Tổng hợp** — `scripts/run-review.ps1 -TaskId <ID>`:
- 0 → sang bước h; nếu script in `Chú ý: ... conf:LOW` → ghi vào Nợ kỹ thuật, không tự chặn.
- 1 → còn CRITICAL/HIGH, sang bước g.
- 2 → thiếu báo cáo: gọi lại đúng agent còn thiếu.

**g. Fix** — `scripts/update-state.ps1 -TaskId <ID> -Status fixing -IncrementFixAttempts`:
- 3 → đã hết lượt, task chuyển `blocked`: `scripts/update-workflow.ps1 -Phase blocked`, ghi `reviews/<ID>-summary.md` (lịch sử các vòng + vấn đề còn tồn đọng + hướng xử lý thủ công đề xuất), DỪNG cả feature, báo người dùng.
- 0 → ghi đè `tasks/<ID>/prompt.md` bằng fix-prompt theo `.claude/orchestrator/fix-prompt.md` (bản cũ đã được lưu trong `tasks/<ID>/history/`), quay lại bước c.

**h. Duyệt** — `scripts/update-state.ps1 -TaskId <ID> -Status approved`, rồi commit trên nhánh task: `git add -A` và `git commit -m "[worker] <ID>: <mô tả ngắn>"`. Không merge. Task kế tiếp sẽ tách nhánh từ nhánh này.

## 4. Kết thúc feature

1. Cập nhật `memory/decisions.md` (mục mới cho mỗi quyết định thật), `memory/architecture.md` (nếu kiến trúc đổi), `memory/roadmap.md`, và ghi đè phần liên quan trong `memory/summary.md` (giữ 40–60 dòng).
2. Commit trên nhánh hiện tại: `[orchestrator] cập nhật memory sau feature <tên>`.
3. `scripts/update-workflow.ps1 -Phase done`.
4. Báo cáo theo mẫu "Tổng kết" trong `.claude/commands/orchestrator.md`, kèm tên nhánh cuối cùng (chứa toàn bộ task). Mục "Nợ kỹ thuật" liệt kê từng phát hiện MEDIUM/LOW và CRITICAL/HIGH gắn conf:LOW còn lại, đọc từ báo cáo tổng hợp gần nhất của mỗi task trong `reviews/` (chỉ đọc các dòng phát hiện, không đọc lại toàn bộ code). Merge hoặc tạo PR chỉ khi người dùng yêu cầu.

Không bao giờ bỏ qua bước kiểm tra tự động hoặc bước review. Không approve khi còn CRITICAL.
