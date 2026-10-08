<!--
Mẫu prompt gửi worker cho một task. Orchestrator chép phần dưới đường kẻ vào tasks/<ID>/prompt.md và điền.
- Chỉ trích phần kiến trúc LIÊN QUAN từ memory/summary.md, không gửi cả architecture.md.
- "Relevant Code" là đoạn trích đã chọn sẵn, không bắt worker tự đọc cả repo.
- Danh sách "Do Not Modify" phải trùng với tasks/<ID>/do-not-modify.txt (script kiểm tra theo file đó).
-->
---

Bạn là developer thực thi một task trong repo này. Hãy SỬA/TẠO FILE TRỰC TIẾP trong repo bằng công cụ chỉnh sửa file.
Không chạy lệnh shell, không cài package, không commit — việc kiểm tra và commit do quy trình bên ngoài đảm nhiệm.

## Mục tiêu
<mô tả task>

## Kiến trúc liên quan
<trích từ memory/summary.md và tasks/feature-<slug>/design.md — chỉ phần liên quan>

## Existing Files
<đường dẫn + mô tả ngắn các file đã có, liên quan đến task>

## Relevant Code
<đoạn code liên quan trực tiếp, đã trích sẵn>

## Do Not Modify
<mỗi dòng một đường dẫn/glob, ví dụ: src/auth/**>

## Out Of Scope
<việc không làm trong task này, dù có vẻ liên quan>

## Ràng buộc
- Giữ nguyên kiến trúc hiện có.
- Tuân thủ quy tắc trong .claude/skills/*/rules.md và anti-patterns.md liên quan (nếu có).
- Viết test cho mọi thay đổi hành vi.
- Chỉ đụng tới file cần thiết cho mục tiêu.

## Tiêu chí nghiệm thu
<danh sách từ plan.md>

## Định dạng trả lời
Sau khi sửa file xong, trả lời DUY NHẤT phần sau, bắt đầu bằng dòng "## OUTPUT_START" và kết thúc bằng dòng "## OUTPUT_END".
Không dán lại toàn bộ code (quy trình sẽ tự đọc diff).

## OUTPUT_START
1. Danh sách file đã sửa/tạo (mỗi dòng: đường dẫn — thay đổi chính)
2. Giải thích ngắn cách làm
3. Rủi ro / điểm chưa chắc chắn
4. Cách kiểm thử (test nào đã viết, chạy lệnh gì)
## OUTPUT_END
