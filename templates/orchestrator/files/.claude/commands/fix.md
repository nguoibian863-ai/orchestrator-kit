---
description: Chạy một vòng fix cho task theo báo cáo review gần nhất (có giới hạn số vòng)
argument-hint: <TaskId>
---

Task cần fix: $ARGUMENTS (nếu trống → chọn task đang `reviewing`/`fixing` trong `state/task-state.json`; có nhiều task thì hỏi người dùng).

Gọi script: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<tên>.ps1 <tham số>`.

1. Đọc `state/task-state.json` và báo cáo trong `last_review_summary` của task (hoặc phần cuối `tasks/<ID>/checks.log` nếu lần trước fail ở bước kiểm tra).
2. `scripts/start-task.ps1 -TaskId <ID>` để chắc chắn đang ở đúng nhánh.
3. `scripts/update-state.ps1 -TaskId <ID> -Status fixing -IncrementFixAttempts`
   - 3 → đã hết lượt, task chuyển `blocked`. Ghi `reviews/<ID>-summary.md`, DỪNG, báo người dùng. Không gọi worker.
4. Ghi đè `tasks/<ID>/prompt.md` theo `.claude/orchestrator/fix-prompt.md`: chỉ các vấn đề CRITICAL/HIGH (và lỗi checks), mỗi vấn đề có nguyên nhân gốc, file liên quan, yêu cầu sửa cụ thể. Giữ nguyên `do-not-modify.txt`.
5. Tiếp tục từ bước 3c của `.claude/commands/feature.md` (worker → checks → review → tổng hợp) cho task này.

Chỉ sửa đúng lỗi đã báo cáo. Không thiết kế lại kiến trúc.
