# orchestrator-kit

Lệnh `/init-orchestrator` cho Claude Code và bộ mẫu **orchestrator v3**. Trong mô hình này, Claude Code đóng vai điều phối và gác cổng chất lượng, còn worker AI sửa code. Worker mặc định là Antigravity CLI `agy`; Codex CLI và Gemini CLI cũng được hỗ trợ.

Hướng dẫn đầy đủ (kiến trúc, quy trình, cấu hình worker): [templates/orchestrator/orchestrator-guide.md](templates/orchestrator/orchestrator-guide.md).

## Cấu trúc

```
commands/init-orchestrator.md     lệnh /init-orchestrator, cài vào ~/.claude/commands/
templates/orchestrator/           bộ mẫu, cài vào ~/.claude/templates/orchestrator/
  scaffold.ps1                    chép files/ vào project mới, không ghi đè
  orchestrator-guide.md           hướng dẫn đầy đủ
  files/                          nội dung khung project
install.ps1                       cài hoặc cập nhật repo này vào ~/.claude
```

## Cài đặt

Yêu cầu: Windows, PowerShell 5.1 trở lên, git, Claude Code và ít nhất một worker CLI (`agy`, `codex` hoặc `gemini`).

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

- `-DryRun`: chỉ liệt kê những gì sẽ thay đổi, không ghi gì.
- `-Prune`: xoá file chỉ còn ở bản cài mà repo không còn, ví dụ file đã đổi tên. Chỉ áp dụng cho `templates/orchestrator`. Nên dùng sau khi xoá hoặc đổi tên file, vì `scaffold.ps1` chép mọi thứ trong `files/` vào project mới.

## Sửa bộ mẫu

Repo là nguồn sự thật. **Sửa trong repo, đừng sửa trực tiếp trong `~/.claude`**, vì lần cài sau sẽ ghi đè.

1. Sửa file trong repo.
2. Chạy `install.ps1` (thêm `-Prune` nếu đã xoá hoặc đổi tên file).
3. Commit.

Nếu lỡ sửa trong `~/.claude`, chép file đó ngược về repo trước khi chạy `install.ps1`. Chạy `-DryRun` sẽ thấy file nào đang khác.

## Dùng

Trong Claude Code, mở một thư mục project mới hoặc trống:

```
/init-orchestrator nextjs mongodb
```

Tham số là framework và database, có thể bỏ trống. Sau đó bắt đầu bằng `/orchestrator <yêu cầu>` hoặc `/feature <mô tả>`.
