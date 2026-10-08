---
description: Thay đổi nhỏ theo quy trình orchestrator — bỏ thiết kế và chia task, vẫn qua worker, checks và review
argument-hint: <mô tả thay đổi nhỏ>
---

Thay đổi cần làm: $ARGUMENTS

## Khi nào dùng /quick

- **nhỏ** — ≤ 3 file, không đụng auth/phân quyền, không đổi schema/migration, không đổi API contract hay wire-shape, không sửa `scripts/`, `.claude/`, không đổi cấu hình bảo mật. CHỈ mức này mới dùng `/quick`.
- **vừa** — lớn hơn nhưng còn trong một module → dùng `/feature`.
- **cao** — đụng auth, schema, contract, bảo mật, hoặc dữ liệu → dùng `/feature` và không bỏ bước nào.
- Mức chỉ được NÂNG, không bao giờ hạ. Trong lúc làm mà phạm vi lớn hơn dự kiến → dừng `/quick`, chuyển sang `/feature`, báo người dùng.

## Các bước

1. Đọc `state/workflow-state.json`, `state/task-state.json`: còn task chưa `approved`/`blocked` → báo người dùng, không tự bắt đầu.
2. Phân loại mức, nói rõ một dòng (ví dụ `Mức: nhỏ — 2 file, không đụng contract`). Không phải mức nhỏ → dừng, đề nghị `/feature`.
3. `scripts/update-workflow.ps1 -Feature "<tên ngắn>" -Phase implementing`, đặt một ID task duy nhất.
4. `scripts/update-state.ps1 -TaskId <ID> -Status planned -Title "<tiêu đề>"`.
5. Viết `tasks/<ID>/prompt.md` theo `.claude/orchestrator/worker-prompt.md` và `tasks/<ID>/do-not-modify.txt`. Không viết design.md/plan.md.
6. `scripts/run-task.ps1 -TaskId <ID>`:

   | Mã | Xử lý |
   |---|---|
   | 0 | Sang bước sau. |
   | 6 | DỪNG, báo người dùng danh sách file, không tự hoàn tác, không chạy lệnh git nào. |
   | Mã khác | DỪNG và báo nguyên văn thông điệp của script. |

7. `scripts/update-workflow.ps1 -Phase review-loop`. Review theo `mode`: `lean` thì orchestrator tự đọc `tasks/<ID>/changes.patch` + `tasks/<ID>/output.md` (cả mục "Sai lệch so với yêu cầu") và ghi `tasks/<ID>/review-output.md` theo `.claude/agents/reviewer.md`, gộp cả góc nhìn bảo mật và test; `full` thì gọi 3 subagent song song để ghi `reviewer-output.md`, `security-output.md`, `qa-output.md`.
8. `scripts/finish-task.ps1 -TaskId <ID> -Message "<mô tả ngắn>"`:
   - `0` → xong.
   - `1` còn CRITICAL/HIGH → vòng fix: ghi fix-prompt rồi `scripts/run-task.ps1 -TaskId <ID> -Fix`. Mã `3` = hết lượt → `scripts/update-workflow.ps1 -Phase blocked`, ghi `reviews/<ID>-summary.md`, DỪNG, báo người dùng.
   - `2` thiếu báo cáo → ghi lại báo cáo còn thiếu.
9. `scripts/update-workflow.ps1 -Phase done`. Cập nhật `memory/` chỉ khi thay đổi đáng ghi nhớ. Không merge; merge/PR chỉ khi người dùng yêu cầu.

## Không bao giờ

Không bỏ bước checks hay review. Không approve khi còn CRITICAL/HIGH. Không dùng `/quick` cho mức vừa/cao.
