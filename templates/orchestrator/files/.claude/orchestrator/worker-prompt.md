<!--
Mẫu prompt gửi worker cho một task. Orchestrator chép phần dưới đường kẻ vào tasks/<ID>/prompt.md và điền.
- Chỉ trích phần kiến trúc LIÊN QUAN từ memory/summary.md, không gửi cả architecture.md.
- "Relevant Code" là đoạn trích đã chọn sẵn, không bắt worker tự đọc cả repo.
- "File mẫu để bắt chước": 1–3 file CÓ SẴN cùng loại (cùng tầng, cùng kiểu) để worker theo cấu trúc, đặt tên, xử lý lỗi, kiểu test. Lấy từ plan.md; không có thì ghi "Không có".
- "Hợp đồng nguyên văn": tên trường, mã thoát, tên flag, khoá config, ngưỡng, định dạng — chép NGUYÊN VĂN từ design.md (mục Thiết kế API) / plan.md. Không diễn giải, không dịch, không đổi tên.
- Danh sách "Do Not Modify" phải trùng với tasks/<ID>/do-not-modify.txt (script kiểm tra theo file đó).
- Tiêu chí nghiệm thu phải có ít nhất một tiêu chí cho đường lỗi/đầu vào xấu.
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

## File mẫu để bắt chước
<đường dẫn file có sẵn cùng loại — điểm cần theo: cấu trúc, đặt tên, xử lý lỗi, kiểu test>

## Hợp đồng nguyên văn
<tên trường, mã thoát, flag, khoá config, ngưỡng, định dạng — trích nguyên văn; dùng đúng từng ký tự>

## Do Not Modify
<mỗi dòng một đường dẫn/glob, ví dụ: src/auth/**>

## Out Of Scope
<việc không làm trong task này, dù có vẻ liên quan>

## Ràng buộc
- Giữ nguyên kiến trúc hiện có.
- Tuân thủ quy tắc trong .claude/skills/*/rules.md và anti-patterns.md liên quan (nếu có).
- Viết test cho mọi thay đổi hành vi, gồm cả đường lỗi/đầu vào xấu (rỗng, sai định dạng, giá trị biên, quá giờ...), không chỉ đường chạy đúng.
- Không sửa hoặc xoá test có sẵn — test là hợp đồng nghiệm thu — trừ khi mục "Mục tiêu" yêu cầu rõ. Test có sẵn mâu thuẫn với yêu cầu thì giữ nguyên test và ghi vào "Sai lệch so với yêu cầu".
- Giá trị trong "Hợp đồng nguyên văn" dùng đúng từng ký tự, không đổi tên, không diễn giải.
- Chỉ đụng tới file cần thiết cho mục tiêu.
- Đọc file văn bản ở dạng UTF-8 (trên PowerShell 5.1 dùng Get-Content -Encoding UTF8), file không BOM đọc theo mặc định sẽ hỏng tiếng Việt.

## Tiêu chí nghiệm thu
<danh sách từ plan.md>

## Định dạng trả lời
Sau khi sửa file xong, trả lời DUY NHẤT phần sau, bắt đầu bằng dòng "## OUTPUT_START" và kết thúc bằng dòng "## OUTPUT_END".
Không dán lại toàn bộ code (quy trình sẽ tự đọc diff).

## OUTPUT_START
1. Danh sách file đã sửa/tạo (mỗi dòng: đường dẫn — thay đổi chính)
2. Giải thích ngắn cách làm
3. Rủi ro / điểm chưa chắc chắn
4. Cách kiểm thử (test nào đã viết, lệnh để chạy)
5. Sai lệch so với yêu cầu (chỗ nào làm khác prompt và vì sao; ghi "Không có" nếu không có)
## OUTPUT_END
