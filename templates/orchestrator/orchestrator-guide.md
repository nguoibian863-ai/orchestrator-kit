# Hướng dẫn Orchestrator: Claude Code điều phối worker AI (v3)

> Worker mặc định: **Antigravity CLI** (`agy`). Có sẵn cấu hình cho **Codex CLI** (đăng nhập ChatGPT) và **Gemini CLI** — đổi bằng một chữ trong `orchestrator.config.json` (mục 8).

> Tài liệu tổng quát, không khoá vào stack cụ thể. File trong project là nguồn sự thật — tài liệu này giải thích *vì sao* và *cách dùng*, không chép lại toàn bộ nội dung file.

## 0. Thay đổi so với v2

Cập nhật v3.1: worker trung tính (`run-gemini.ps1` → `run-worker.ps1`, `gemini.log` → `worker.log`, `gemini-prompt.md` → `worker-prompt.md`); cấu hình nhiều worker có tên, chọn bằng `"worker": "<tên>"` hoặc `-Worker <tên>`; mặc định chuyển sang Antigravity CLI vì Gemini CLI đăng nhập bằng tài khoản Google cá nhân bị từ chối (`IneligibleTierError`).

Cập nhật v3.2: `run-worker.ps1` chụp dấu vân tay `.git/config`, `.git/hooks/**`, `.git/info/**` và `core.hooksPath` trước/sau worker; thay đổi `.git` trả mã 6 và không chạy lệnh git hậu xử lý khi `.git/config` hoặc `.git/info` đổi.

Cập nhật v3.3: worker có khoá `output`; `agy` mặc định dùng JSON envelope để phân biệt bị từ chối, không trả lời và status lỗi. Thứ tự mã thoát của `run-worker.ps1` là `6 > 124 > 3 > 11 > 10 > 8 > 9 > 5 > 7`.

Cập nhật v3.4: 3 agent review ghi nhãn độ tin cậy cho từng phát hiện; `run-review.ps1` chỉ chặn CRITICAL/HIGH có nhãn HIGH/MEDIUM hoặc thiếu nhãn, còn nhãn LOW được liệt kê riêng.

Cập nhật v3.5: bổ sung mẫu prompt worker, fix-prompt và agent planner với "File mẫu để bắt chước", "Hợp đồng nguyên văn", quy tắc không sửa test có sẵn, test đường lỗi và mục output "Sai lệch so với yêu cầu"; reviewer và qa đối chiếu mục này với prompt.

Cập nhật v3.6: worker `agy` mặc định thêm `--mode accept-edits` (không tương tác mới ghi được file).

Cập nhật v3.7: `run-task.ps1` và `finish-task.ps1` gói các bước của một task (orchestrator gọi 2 lệnh thay vì ~8); `run-checks.ps1` không in lại dòng lệnh của từng bước.

Cập nhật v3.8: vòng fix tiếp tục phiên worker cũ (`-Resume` + `resume_args`); mỗi lần gọi worker ghi một dòng `tasks/<ID>/metrics.jsonl`.

Cập nhật v3.9: khoá `mode` (`lean` mặc định | `full`) — lean thì orchestrator tự thiết kế/chia task/review và `run-review.ps1` đọc một file `review-output.md`; thêm lệnh `/quick` cho thay đổi nhỏ.

Cập nhật v3.10: kiểm tra phạm vi theo dõi thêm `.gitignore`, `HEAD`/ref nhánh và các file trong `scope.watched_external` (cấu hình quyền của worker).

Cập nhật v3.11: có thể miễn trừ phát hiện CRITICAL/HIGH qua `tasks/<ID>/waivers.md` (có lý do, hiện ở mục riêng của báo cáo).

| Vấn đề ở v2 | Cách v3 xử lý |
|---|---|
| `commands/`, `agents/`, `skills/` ở gốc project → Claude Code không nhận, `/feature`... không tồn tại | Chuyển vào `.claude/commands/`, `.claude/agents/`, `.claude/skills/`, có frontmatter; agent là subagent thật (context riêng) |
| `run-checks.ps1` lint FAIL vẫn trả exit 0 | Dừng ở bước lỗi đầu tiên, trả exit 1; danh sách lệnh lấy từ `orchestrator.config.json` |
| `run-gemini.ps1` không bắt mã lỗi của worker, khai báo timeout nhưng không dùng | Kiểm tra mã thoát, timeout thật (giết cả cây tiến trình), mã thoát riêng cho từng tình huống |
| `$ErrorActionPreference=Stop` + `2>&1` làm chết script trên PowerShell 5.1 khi Gemini in cảnh báo | Gọi tiến trình qua `System.Diagnostics.Process`, chạy được trên cả PowerShell 5.1 và 7 |
| State ghi có BOM (Node đọc lỗi), nhận status gõ sai, không khoá file | UTF-8 không BOM, `ValidateSet`, khoá độc quyền khi đọc-sửa-ghi |
| "Do Not Modify" chỉ là lời dặn, `--yolo` cho Gemini toàn quyền | Worker chỉ được sửa file (agy `--mode accept-edits` / Gemini `auto_edit`) hoặc chạy shell trong sandbox (Codex `workspace-write`); sau mỗi lần chạy, script đối chiếu `git diff` với danh sách cấm |
| Nói "mỗi task một branch" nhưng không có bước nào tạo branch | `start-task.ps1` tạo nhánh + ghi commit gốc; `run-worker.ps1` từ chối chạy nếu sai nhánh hoặc trên `main` |
| Check FAIL quay lại sửa mà không tính lượt → có thể lặp vô hạn | Mọi vòng fix (do checks hay review) đều qua `-IncrementFixAttempts`; vượt giới hạn script tự chuyển `blocked`, trả exit 3 |
| `/init-orchestrator` để Claude gõ lại ~15 KB file mẫu | `scaffold.ps1` chép file thật trong 1 giây, không ghi đè, chặn thư mục không trống |
| Gemini trả lại toàn bộ code trong output → Claude đọc lại, tốn token | Worker sửa file trực tiếp, output chỉ là tóm tắt; reviewer đọc `changes.patch`; subagent ghi báo cáo ra file, chỉ trả 1 dòng số liệu |
| `/review` có thể trùng lệnh có sẵn của Claude Code | Đổi thành `/review-task` |

## 1. Mục tiêu & kiến trúc

- **Claude Code** (phiên chính) là *orchestrator*: thiết kế, điều phối, gác cổng chất lượng — không viết code sản xuất.
- **Worker AI** (mặc định Antigravity CLI `agy`; hoặc Codex CLI, Gemini CLI): sửa file trong repo theo prompt chặt phạm vi.
- Mọi thay đổi phải qua **kiểm tra tự động** rồi **review** (3 subagent chạy song song); không duyệt khi còn CRITICAL/HIGH.
- Trạng thái nằm trong `state/`, không phụ thuộc trí nhớ hội thoại. **Mã thoát của script là quyết định**, Claude không tự diễn giải log.

```
Người dùng ──► /orchestrator hoặc /feature
                 │
Claude (orchestrator) ── đọc/ghi state/ qua script
   ├─ subagent retriever  → tasks/feature-<slug>/knowledge.md   (tuỳ chọn)
   ├─ subagent architect  → tasks/feature-<slug>/design.md
   ├─ subagent planner    → tasks/feature-<slug>/plan.md
   │
   └─ với từng task:
        start-task.ps1    → nhánh feature/<ID>, ghi base_commit
        run-worker.ps1    → worker sửa file → output.md, changed-files.txt, changes.patch, kiểm tra phạm vi
        run-checks.ps1    → lint/build/test từ config, dừng ở lỗi đầu tiên
        reviewer ║ security ║ qa  (song song) → tasks/<ID>/*-output.md
        run-review.ps1    → đếm CRITICAL/HIGH → ĐẠT (commit) | CHƯA ĐẠT (fix, tối đa N vòng → blocked)
```

## 2. Yêu cầu môi trường

- Windows, **Windows PowerShell 5.1 hoặc PowerShell 7** (script chạy được trên cả hai; lệnh gọi dùng `powershell`, có sẵn trên mọi máy Windows).
- **Claude Code**, không cần plugin.
- **Ít nhất một worker** đã đăng nhập và chạy được ở chế độ không tương tác:

  | Worker | Kiểm tra cài đặt | Đăng nhập | Thử nhanh |
  |---|---|---|---|
  | `agy` (Antigravity CLI) | `agy --version` (đã thử 1.3.1) | chạy `agy` một lần ở chế độ tương tác (đăng nhập); quyền ghi file do `--mode accept-edits` trong config lo | `agy --output-format json -p "Reply with exactly: PONG"` → thấy `"status":"SUCCESS"` |
  | `codex` (Codex CLI) | `codex --version` (đã thử 0.160.0) | `codex login` bằng tài khoản ChatGPT | `echo "Reply with exactly: PONG" \| codex exec -` |
  | `gemini-cli` | `gemini --version` | API key `GEMINI_API_KEY` (đăng nhập Google cá nhân có thể bị từ chối: `IneligibleTierError`) | `echo hi \| gemini -p "reply OK"` |
- **git**, và project phải là git repo có ít nhất một commit trước task đầu tiên.
- Trình quản lý gói, linter, test runner của dự án — để điền vào `checks`.

## 3. Cài đặt & chia sẻ

Hai thứ cần có trong thư mục người dùng (`~` = `C:\Users\<tên>`):

```
~/.claude/commands/init-orchestrator.md     # lệnh /init-orchestrator
~/.claude/templates/orchestrator/           # toàn bộ thư mục này
    scaffold.ps1
    orchestrator-guide.md
    files/                                  # cây file được chép vào project
```

Chia sẻ cho người khác: gửi đúng hai thứ trên, giữ nguyên đường dẫn. Bộ mẫu không chứa key hay đường dẫn riêng của máy.

Tạo project mới: mở Claude Code trong thư mục trống, gõ `/init-orchestrator nextjs mongodb` (hoặc không tham số để được hỏi).

## 4. Cấu trúc project sau khi scaffold

```
<project>/
├── .claude/
│   ├── agents/          retriever, architect, planner, reviewer, security, qa (.md, có frontmatter)
│   ├── commands/        orchestrator, feature, review-task, fix (.md)
│   ├── skills/          project-code-review, project-security-audit, [<tech>-architecture], [<db>-patterns]
│   ├── orchestrator/    worker-prompt.md, fix-prompt.md (mẫu prompt cho worker)
│   └── settings.json
├── scripts/             _lib.ps1 + 7 script (mục 6)
├── state/               task-state.json, workflow-state.json
├── memory/              summary, architecture, roadmap, decisions, tech-stack, known-issues
├── docs/                business-rules, api-contracts, architecture-rules
├── tasks/               feature-<slug>/ (knowledge, design, plan) và <ID>/ (prompt, output, log, diff, báo cáo, history/)
├── reviews/             báo cáo tổng hợp từng vòng, <ID>-summary.md khi blocked
├── src/
├── .gitignore           state/, tasks/, reviews/
├── orchestrator.config.json
└── orchestrator-guide.md
```

## 5. Agents

Chế độ `lean` (mặc định) KHÔNG dùng subagent — orchestrator tự làm các vai dưới đây và tự ghi `tasks/<ID>/review-output.md`. Lý do: mỗi subagent đọc lại mã từ đầu nên tốn token (đo thật: một lượt architect ~158k token). Bảng dưới áp dụng cho chế độ `full`.

Mỗi agent = **Role** (file trong `.claude/agents/`) + **State** (`state/`) + **Knowledge** (chỉ được đọc những file ghi trong agent). Agent ghi kết quả ra file và chỉ trả về tóm tắt ngắn, để context của phiên chính không phình.

| Agent | Khi nào | Ghi ra | Trả về |
|---|---|---|---|
| retriever | Feature có tài liệu/API ngoài | `tasks/feature-<slug>/knowledge.md` | ≤5 dòng + điểm chưa rõ |
| architect | Mọi feature | `tasks/feature-<slug>/design.md` | ≤10 dòng + điểm chưa rõ + có đổi kiến trúc không |
| planner | Sau design | `tasks/feature-<slug>/plan.md` | Danh sách `ID \| tiêu đề \| phụ thuộc` |
| reviewer | Sau checks PASS | `tasks/<ID>/reviewer-output.md` | `CRITICAL=n HIGH=n MEDIUM=n LOW=n` |
| security | Sau checks PASS | `tasks/<ID>/security-output.md` | như trên |
| qa | Sau checks PASS | `tasks/<ID>/qa-output.md` | như trên |

Agent review chỉ có quyền `Read, Grep, Glob, Write` (không chạy shell). Muốn giảm chi phí, có thể thêm `model: sonnet` (hoặc `haiku`) vào frontmatter của từng agent.

## 6. Scripts & mã thoát

Gọi từ gốc project: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<tên>.ps1 <tham số>`.

| Script | Việc | Mã thoát |
|---|---|---|
| `update-workflow.ps1 -Feature <tên> -Phase <phase> [-Force]` | Bắt đầu feature / đổi phase | 0 ok · 3 đang có feature dang dở |
| `update-state.ps1 -TaskId <ID> -Status <s> [-IncrementFixAttempts] [-Title <t>]` | Đổi status task | 0 ok · 3 hết lượt fix → `blocked` |
| `run-task.ps1 -TaskId <ID> [-Worker <tên>] [-Fix]` | Gói start-task → implementing/fixing → worker → checks → checked | 0 ok · mã nguyên văn của bước lỗi |
| `finish-task.ps1 -TaskId <ID> -Message <mô tả>` | Gói reviewing → review → approved + commit | 0 ok · 1 còn CRITICAL/HIGH · 2 thiếu báo cáo · 3 hết lượt fix |
| `start-task.ps1 -TaskId <ID>` | Tạo/chuyển nhánh `feature/<ID>`, ghi `base_commit` | 0 ok · 1 lỗi (chưa git, chưa commit, cây bẩn...) |
| `run-worker.ps1 -TaskId <ID> [-Worker <tên>] [-Resume]` | Gọi worker với `tasks/<ID>/prompt.md`; `-Resume` dùng `resume_args` để tiếp tục phiên worker đã lưu trong state | 0 ok · 1 thiết lập · 3 worker lỗi · 5 thiếu marker · 6 sửa file cấm/.git · 7 không đổi file nào · 8 bị từ chối, không trả lời · 9 không trả lời · 10 status khác SUCCESS · 11 không phải JSON · 124 quá giờ |
| `run-checks.ps1 [-TaskId <ID>]` | Chạy `checks` theo thứ tự | 0 PASS · 1 FAIL/quá giờ · 2 chưa cấu hình |
| `run-review.ps1 -TaskId <ID>` | Gộp 3 báo cáo, đếm mức độ | 0 đạt · 1 còn CRITICAL/HIGH · 2 thiếu báo cáo |
| `collect-changes.ps1 -TaskId <ID>` | Tạo lại diff + kiểm tra phạm vi (sau khi sửa tay) | 0 ok · 6 sửa file cấm |

`run-worker.ps1` có thể chạy tới `worker.timeout_sec` giây (mặc định 540, vừa trong giới hạn 600 giây của một lệnh shell trong Claude Code). Tăng quá 540 thì phải chạy script ở chế độ nền.

Khi có nhiều điều kiện cùng lúc, ưu tiên mã thoát là `6 > 124 > 3 > 11 > 10 > 8 > 9 > 5 > 7`. Mã 8–11 chỉ áp dụng khi worker đặt `"output": "agy-json"`.

## 7. State

`state/task-state.json` — mỗi task:

```json
{ "title": "", "status": "planned", "phase_history": ["planned"], "fix_attempts": 0, "max_fix_attempts": 3,
  "branch": "feature/AUTH-001", "base_commit": "<sha>", "last_review_summary": "reviews/...", "worker_name": "agy",
  "worker_session": "<session id>", "updated_at": "..." }
```

Status hợp lệ: `designed` → `planned` → `implementing` → `checked` → `reviewing` → `fixing` → `approved` | `blocked`.

`state/workflow-state.json` — feature hiện tại, `current_phase` (`retrieving`, `designing`, `planning`, `implementing`, `review-loop`, `done`, `blocked`), danh sách task, task bị chặn, thời điểm bắt đầu. Danh sách task và task bị chặn được `update-state.ps1` tự đồng bộ.

Quy tắc: đọc `state/` trước mỗi bước; chỉ ghi qua script; phiên mới (`/orchestrator`) luôn bắt đầu bằng việc đọc state để tiếp tục việc dang dở.

## 8. Worker & phạm vi sửa

`orchestrator.config.json` chứa danh sách worker có tên; `"worker"` chọn worker mặc định:

```json
"worker": "agy",
"workers": {
  "agy": {
    "command": "agy",
    "args": ["--output-format", "json", "--effort", "high", "--print-timeout", "8m", "-p", "Read the file {prompt_file} in this workspace and carry out every instruction in it exactly. Your final reply must follow the response format defined in that file."],
    "resume_args": ["--conversation", "{session}", "-p", "Read the file {prompt_file} in this workspace and carry out every instruction in it exactly. Your final reply must follow the response format defined in that file."],
    "output": "agy-json", "stdin_prompt": false, "timeout_sec": 540
  },
  "codex":      { "command": "codex",  "args": ["exec", "--sandbox", "workspace-write", "--color", "never", "-"],         "resume_args": ["exec", "--sandbox", "workspace-write", "--color", "never", "resume", "{session}", "-"], "output": "text", "stdin_prompt": true,  "timeout_sec": 540 },
  "gemini-cli": { "command": "gemini", "args": ["--approval-mode", "auto_edit", "--skip-trust", "-p", "Follow ..."],       "output": "text", "stdin_prompt": true,  "timeout_sec": 540 }
}
```

`workers.<tên>.output` nhận `"text"` (mặc định nếu thiếu, `null` hoặc rỗng) hoặc `"agy-json"`; so sánh không phân biệt hoa thường sau `Trim()`. Giá trị khác trả mã 1. Chế độ `text` tách marker từ stdout như trước. Chế độ `agy-json` tìm JSON envelope, lấy `response` để tách marker và ghi `conversation_id`, `status`, `usage`, `denied_actions` vào `worker.log`.

`workers.<tên>.resume_args` là mảng tham số tùy chọn, dùng thay `args` khi chạy `run-worker.ps1 -Resume`; `{session}`, `{prompt_file}` và `{task_id}` được thay bằng session đã lưu, đường dẫn prompt và ID task. `run-worker.ps1` chỉ resume khi `worker_session` có giá trị, `worker_name` trong state trùng worker đang chọn và worker có `resume_args`; nếu thiếu điều kiện, script chạy phiên mới. Session của `agy-json` lấy từ `conversation_id` trong envelope; session của worker `text` như Codex lấy từ dòng `session id: <UUID>` trong stdout hoặc stderr. Sau mỗi lần gọi worker, `tasks/<ID>/metrics.jsonl` append một dòng với `ts`, `task`, `worker`, `resumed`, `exit`, `timed_out`, `seconds`, `status`, `total_tokens`, `input_tokens`, `output_tokens`, `cached_tokens`, `changed_files` và `session`.

Thứ tự tham số theo từng CLI: `codex` chỉ nhận cờ TRƯỚC subcommand (`exec --sandbox ... resume <id> -`); đặt cờ sau `resume` sẽ bị từ chối với `Usage: codex exec resume <SESSION_ID> [PROMPT]`. `agy` dùng `--conversation <id>` ở bất kỳ vị trí nào trước `-p`.

Phân loại `agy-json`: stdout rỗng → 9; không có envelope → 11; `status` khác `SUCCESS` → 10; response rỗng cùng `denied_actions` → 8; response rỗng không có hành động bị từ chối → 9. Envelope thành công có response thì xử lý marker bình thường; có hành động bị từ chối nhưng vẫn có response sẽ hiện cảnh báo và tiếp tục.

- Đổi worker cho cả dự án: sửa `"worker"`. Đổi cho một lần chạy: `run-worker.ps1 -TaskId <ID> -Worker codex`.
- Prompt dài nên không bao giờ nằm trên dòng lệnh. `stdin_prompt: true` → nội dung `prompt.md` được đưa vào stdin (Codex, Gemini). `stdin_prompt: false` → chỉ truyền đường dẫn qua `{prompt_file}` để worker tự đọc file (agy chỉ nhận prompt qua tham số). Trong `args`, `{prompt_file}` → `tasks/<ID>/prompt.md`, `{task_id}` → `<ID>`. Tham số không được chứa ký tự xuống dòng.
- Quyền của từng worker:
  - `agy`: mặc định hỏi quyền cho mỗi lần ghi file (`toolPermission=request-review`); khi chạy `-p` không ai trả lời nên agy tự từ chối `write_file`. `--mode accept-edits` cho phép sửa file, lệnh shell vẫn bị từ chối. Thêm thư mục vào `trustedWorkspaces` hay cấp quyền tương tác một lần đều không thay được tuỳ chọn này. `--print-timeout 8m` để agy tự dừng trước giới hạn 540 giây của script. Không bao giờ dùng `--dangerously-skip-permissions`.
  - `codex` `workspace-write`: ghi được trong workspace, lệnh shell chạy trong sandbox. Không dùng `--dangerously-bypass-approvals-and-sandbox`.
  - `gemini-cli` `auto_edit`: chỉ sửa file, không chạy shell. Không dùng `yolo`.
- `env` nhận giá trị dạng `"${env:TEN_BIEN}"` để lấy từ biến môi trường — không ghi key vào file.
- Thêm worker khác: thêm một mục vào `workers`. Worker phải tự sửa file trong repo và in kết quả giữa `## OUTPUT_START` … `## OUTPUT_END`. Worker chỉ trả text (ví dụ gọi HTTP qua 9Router) cần thêm bước tách file từ output — chưa có trong bộ mẫu này.

Kiểm tra phạm vi (tự động sau mỗi lần chạy worker): mọi file thay đổi so với `base_commit` (kể cả file mới chưa track) được so với `scope.always_protected` + `tasks/<ID>/do-not-modify.txt`. Glob: `*` không qua `/`, `**` qua mọi cấp, `thu-muc/` = mọi thứ bên trong. `tasks/`, `reviews/`, `state/` không tính (do script ghi).

Script chụp dấu vân tay trước/sau worker cho các loại `config`, `hooks`, `info`, `hooksPath`, `refs`, `gitignore` và `external`. `scope.watched_external` phát hiện worker sửa cấu hình quyền của chính nó; đường dẫn `~/` hoặc `~\` mở thành `$HOME`, đường dẫn tương đối tính từ gốc project, phần tử rỗng/null bị bỏ qua và mảng rỗng tắt theo dõi bên ngoài. Nếu `.gitignore` hoặc refs đổi, kết quả `git diff`/`ls-files` không còn tin được nên script bỏ qua bước liệt kê thay đổi.

`output` có thể đặt về `"text"` để dùng cách đọc stdout cũ; khi đó bỏ `--output-format json` khỏi `agy` args. Nếu agy `--effort high` thường hết `--print-timeout 8m` (mã 9), hạ mức effort trong args.

## 9. Kiểm tra tự động

```json
"checks": [
  { "name": "lint",  "command": "npm run lint",     "timeout_sec": 300 },
  { "name": "test",  "command": "npm test -- --ci", "timeout_sec": 900 }
]
```

Mặc định `checks` trống — `run-checks.ps1` trả exit 2 để orchestrator hỏi người dùng thay vì cho qua. Lệnh chạy qua `cmd.exe` tại gốc project; log đầy đủ ở `tasks/<ID>/checks.log`.

## 10. Review & thang mức độ

Chế độ `lean`: một báo cáo `tasks/<ID>/review-output.md`, nguồn hiển thị là `Orchestrator`; thang mức độ, nhãn `[conf:...]` và quy tắc chặn giữ nguyên. Chế độ `full`: ba báo cáo như bảng trên. Nếu khoá `mode` bị thiếu, `review-output.md` không tồn tại và đủ cả ba báo cáo reviewer/security/qa thì `run-review.ps1` dùng `full` để tương thích ngược; khoá `mode` tường minh luôn thắng.

Ba agent dùng chung thang: **CRITICAL** (khai thác được, mất dữ liệu, crash, sai nghiệp vụ cốt lõi) · **HIGH** (nghiêm trọng, chưa sập ngay) · **MEDIUM** (vi phạm best practice) · **LOW** (nhỏ, style).

Định dạng báo cáo cố định để script đếm: heading `## CRITICAL` / `## HIGH` / `## MEDIUM` / `## LOW`; mỗi phát hiện là một dòng bắt đầu bằng `- ` ở đầu dòng với nhãn `[conf:HIGH]`, `[conf:MEDIUM]` hoặc `[conf:LOW]` ngay sau `- `; chi tiết thụt vào bên dưới; mục trống để trống. CRITICAL/HIGH có nhãn HIGH/MEDIUM hoặc thiếu nhãn tính chặn; CRITICAL/HIGH có nhãn LOW không tính chặn và xuất hiện ở mục riêng. MEDIUM/LOW vẫn được đếm theo mức. Báo cáo cũ không có nhãn tiếp tục tính CRITICAL/HIGH là chặn. `run-review.ps1` ghi báo cáo tổng hợp `reviews/<ID>-round<N>-<thời điểm>.md` với bảng số liệu ở đầu, gồm cột `CRIT/HIGH conf:LOW`.

Waiver đặt trong `tasks/<ID>/waivers.md`, mỗi dòng theo khuôn `- [CRITICAL|HIGH] <chuỗi con của dòng phát hiện> — Lý do: <lý do>` (cũng nhận dấu đầu dòng `*`, `+`, số thứ tự, dấu `-` phân cách và `Ly do:`). Script chỉ miễn trừ CRITICAL/HIGH cùng mức khi chuỗi con dài ít nhất 10 ký tự xuất hiện trong nội dung phát hiện sau khi bỏ nhãn `[conf:...]`, không phân biệt hoa thường. Waiver sai khuôn, khác mức, quá ngắn hoặc thiếu lý do bị bỏ qua và cảnh báo; waiver hợp lệ không khớp cũng được cảnh báo. Phát hiện được miễn trừ không tính vào CRITICAL/HIGH chặn, được đếm ở cột `Miễn trừ` và vẫn hiện trong mục `Phát hiện được miễn trừ (không tính chặn)` của báo cáo tổng hợp. CRITICAL/HIGH `conf:LOW` vẫn được xử lý riêng như trước. Chỉ orchestrator ghi waiver sau khi hỏi người dùng; lý do phải vào memory/decisions.md.

## 11. Vòng fix

- Mọi vòng fix — do checks FAIL hay review còn CRITICAL/HIGH — đều bắt đầu bằng `update-state.ps1 -Status fixing -IncrementFixAttempts`.
- Vượt `max_fix_attempts` (mặc định 3): script tự chuyển `blocked`, trả exit 3. Orchestrator ghi `reviews/<ID>-summary.md`, dừng feature, báo người dùng.
- Fix-prompt (mẫu `.claude/orchestrator/fix-prompt.md`) ghi đè `tasks/<ID>/prompt.md`; mọi prompt/output/log cũ được lưu trong `tasks/<ID>/history/`.
- `run-task.ps1 -TaskId <ID> -Fix` tự tiếp tục phiên worker đã lưu; fix-prompt có thể dùng biến thể ngắn khi resume.

## 12. Memory & docs

- `memory/summary.md` — bản nén 40–60 dòng, đọc **đầu tiên**; chỉ mở file chi tiết khi cần. Cập nhật bằng cách ghi đè phần liên quan sau mỗi feature.
- `memory/decisions.md` — mỗi quyết định thật một mục (Ngày / Quyết định / Lý do / Trạng thái), không xoá lịch sử.
- `architecture.md`, `roadmap.md`, `tech-stack.md`, `known-issues.md` — phản ánh hiện trạng thật.
- `docs/` — tri thức tĩnh (business rules, API contract, architecture rules); retriever tóm tắt phần liên quan cho từng feature.
- Khi khởi tạo, mọi file để placeholder "Chưa có" — không để ví dụ minh hoạ, tránh Claude đọc nhầm thành ngữ cảnh thật.

## 13. Git

- `state/`, `tasks/`, `reviews/` nằm trong `.gitignore` (scaffold tự thêm): đây là dữ liệu lúc chạy, nếu để git theo dõi thì mỗi lần đổi/reset nhánh sẽ kéo state theo.
- Mỗi task một nhánh `feature/<ID>`, tách từ nhánh hiện tại; task sau tách từ nhánh task trước, nên nhánh cuối cùng chứa toàn bộ feature.
- Worker không chạy trên `main`/`master`/`develop` (cấu hình ở `git.protected_branches`).
- Task đạt → commit trên nhánh task: `[worker] <ID>: <mô tả>`. Không tự merge; PR/merge chỉ khi người dùng yêu cầu.
- Task `blocked` → giữ nguyên nhánh, không merge.

## 14. Commands & cách dùng hằng ngày

| Lệnh | Việc |
|---|---|
| `/orchestrator [yêu cầu]` | Xem trạng thái, tiếp tục việc dang dở, hoặc chuyển sang quy trình feature |
| `/feature <mô tả>` | Toàn bộ quy trình: thiết kế → chia task → worker → checks → review → fix → commit |
| `/quick <mô tả>` | Thay đổi nhỏ (≤3 file, không đụng auth/schema/contract): bỏ thiết kế và chia task, vẫn qua worker, checks, review |
| `/review-task <ID>` | Chạy lại vòng review cho một task (ví dụ sau khi sửa tay) |
| `/fix <ID>` | Chạy một vòng fix theo báo cáo gần nhất |

Trước task đầu tiên: điền `checks`, `git init` + commit khung (Claude chỉ làm khi bạn yêu cầu).

## 15. Giới hạn đã biết

- Script chỉ hỗ trợ Windows (dùng `cmd.exe`, `taskkill`).
- `agy -p` từng có lỗi treo khi chạy với output chuyển hướng trên Windows (issue #318 của antigravity-cli, bản 1.0.6). Bản 1.3.1 đã chạy được qua script; nếu bản khác bị treo, script vẫn dừng ở `timeout_sec` và trả mã 124.
- Phát hiện file cấm dựa trên git diff, nên chỉ phát hiện sau khi worker đã sửa — script dừng và báo, không tự hoàn tác. Các loại `config`, `hooks`, `info`, `hooksPath`, `refs`, `gitignore` và `external` được chụp trước/sau worker; thay đổi `config`, `info`, `refs` hoặc `gitignore` khiến script bỏ qua bước liệt kê thay đổi.
- Không chặn được worker ghi file ra ngoài workspace bằng đường dẫn tuyệt đối — việc này do sandbox của worker lo (codex `workspace-write`, agy `accept-edits`). Bộ mẫu chỉ theo dõi các file trong `scope.watched_external`.
- `.git/index` không được theo dõi: `git diff <base_commit>` so với cây làm việc nên sửa index che được rất ít.
- Thay đổi trong `tasks/`, `reviews/`, `state/` không được kiểm tra phạm vi.
- Script đếm phát hiện dựa trên định dạng báo cáo; nhãn sai vị trí hoặc sai giá trị được coi là thiếu nhãn và CRITICAL/HIGH vẫn tính chặn. Agent viết sai định dạng khác vẫn có thể bị đếm sai — Claude vẫn phải đọc báo cáo tổng hợp khi kết quả đáng ngờ.

## 16. Quy tắc quan trọng nhất

1. Claude không viết code sản xuất — Claude thiết kế, điều phối, review.
2. Mã thoát của script là quyết định; không tự diễn giải log để cho qua.
3. Đọc `state/` trước mỗi bước, ghi `state/` chỉ qua script.
4. Worker chỉ chạy trên nhánh task, với prompt có `Do Not Modify` và `Out Of Scope`; vi phạm phạm vi → dừng, báo người dùng.
5. Không bỏ qua kiểm tra tự động hay review. Không approve khi còn CRITICAL/HIGH.
6. Vòng fix có giới hạn, theo dõi qua state; hết lượt → `blocked`, báo người dùng.
7. Quyết định kỹ thuật thật ghi vào `memory/decisions.md`; đổi kiến trúc thì cập nhật `architecture.md` và `summary.md`.
8. Không merge vào nhánh chính khi chưa có xác nhận của người dùng.
