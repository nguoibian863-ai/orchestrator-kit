<!--
Mẫu fix-prompt. Orchestrator chép phần dưới đường kẻ vào tasks/<ID>/prompt.md (ghi đè; bản cũ đã nằm trong tasks/<ID>/history/).
Chỉ đưa vào vấn đề CRITICAL/HIGH tính chặn (không đưa mục gắn conf:LOW) và lỗi lint/build/test. 'Yêu cầu sửa cụ thể' trích nguyên văn tên trường/mã thoát/flag từ báo cáo hoặc design.md. Giữ nguyên tasks/<ID>/do-not-modify.txt.
-->
---

Bạn là developer sửa lỗi cho task <ID> trong repo này (vòng fix <n>/<max>). Hãy SỬA FILE TRỰC TIẾP.
Không chạy lệnh shell, không cài package, không commit. Chỉ sửa đúng các lỗi dưới đây — không refactor, không thiết kế lại. Không sửa hoặc xoá test có sẵn trừ khi lỗi dưới đây yêu cầu rõ.

## Bối cảnh task
<mục tiêu + tiêu chí nghiệm thu, rút gọn từ prompt gốc>

## Các lỗi cần sửa
### Lỗi 1 — <mức độ> — <tiêu đề>
- Vấn đề:
- Nguyên nhân gốc:
- File liên quan:
- Yêu cầu sửa cụ thể:

### Lỗi 2 — ...

## Do Not Modify
<giống tasks/<ID>/do-not-modify.txt>

## Out Of Scope
<giữ như prompt gốc>

## Định dạng trả lời
Trả lời DUY NHẤT phần sau, bắt đầu bằng dòng "## OUTPUT_START" và kết thúc bằng dòng "## OUTPUT_END". Không dán lại toàn bộ code.

## OUTPUT_START
1. Lỗi đã sửa (theo số thứ tự) — file — cách sửa
2. Lỗi chưa sửa được và lý do (nếu có)
3. Rủi ro mới phát sinh (nếu có)
4. Sai lệch so với yêu cầu (ghi "Không có" nếu không có)
## OUTPUT_END
