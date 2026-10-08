---
description: Chạy lại vòng review (reviewer + security + qa) cho một task của quy trình orchestrator
argument-hint: <TaskId>
---

Task cần review: $ARGUMENTS (nếu trống → đọc `state/task-state.json` và chọn task đang `checked`/`reviewing`; có nhiều task thì hỏi người dùng).

Gọi script: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<tên>.ps1 <tham số>`.

1. Đọc `state/task-state.json`. Task phải có `branch`; nếu đang ở nhánh khác → `scripts/start-task.ps1 -TaskId <ID>` để chuyển về.
2. `scripts/collect-changes.ps1 -TaskId <ID>` để tạo lại diff theo trạng thái hiện tại (phòng khi có người sửa tay). Mã 6 → báo người dùng file bị cấm đã bị đổi, dừng.
3. `scripts/update-state.ps1 -TaskId <ID> -Status reviewing`
4. Gọi song song 3 subagent `reviewer`, `security`, `qa` với TaskId; mỗi agent tự ghi `tasks/<ID>/<tên>-output.md`.
5. `scripts/run-review.ps1 -TaskId <ID>`:
   - 0 → `scripts/update-state.ps1 -TaskId <ID> -Status approved`, báo người dùng (commit theo bước 3h của `.claude/commands/feature.md` nếu người dùng đồng ý).
   - 1 → giữ status `reviewing`, báo số CRITICAL/HIGH và đề xuất `/fix <ID>`.
   - 2 → gọi lại agent còn thiếu báo cáo.

Không approve khi còn CRITICAL.
