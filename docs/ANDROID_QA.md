# Android preview — kiểm thử thiết bị thật

Ngày: 26/10/2026. Thiết bị: Samsung Galaxy S10+ SM-G975U1, Android 12/API 31, arm64. Ứng dụng: `com.duchaik.ytb`, phiên bản `0.1.0+1`, debug.

## Phương pháp

- Kiểm thử tích hợp gọi cùng platform channel mà UI dùng, chạy Media3 trên Samsung thật, lấy nguồn YouTube thật qua dịch vụ Mac. Video kiểm tra chính: Big Buck Bunny (`aqz-KE-bpKQ`).
- 17 tốc độ từ 1 đến 5×, bước 0,25×. Mỗi mức ổn định 1 giây rồi đo tiến độ phát trong 4 giây bằng đồng hồ thực; dung sai 12%. Chạy ở 480p để tách kiểm tra tốc độ khỏi tải giải mã 4K.
- Chọn từng độ phân giải decoder hỗ trợ; chờ track thực tế khớp và kiểm tra tiến độ tiếp tục tăng. Đây không phải phép đo độ mượt hay độ chính xác màu HDR.
- Timer native 3 giây phải làm player dừng và trả cờ hết giờ. Kiểm tra UI/timer nền riêng bên dưới.
- Kiểm thử UI lấy tọa độ từ UIAutomator hierarchy, không lấy từ ảnh chụp.

## Kết quả đã đo

- `flutter analyze`: không có vấn đề.
- 3 unit test: đạt (URL YouTube, danh sách tốc độ, định dạng thời gian).
- Integration test trên Samsung: đạt, thời gian thực thi 2 phút 30 giây.
- 17/17 tốc độ: đạt. Ví dụ tốc độ đo: 1× → 1,0005; 2× → 2,0015; 3× → 3,0000; 4× → 4,0002. Luồng AAC hiện diện ở mọi mức; không đánh giá chủ quan chất lượng âm thanh khi tăng tốc.
- 8/8 chất lượng: 144, 240, 360, 480, 720, 1080, 1440, 2160p đều chọn đúng track và tiếp tục phát.
- Timer 3 giây: dừng phát và bật cờ hết giờ đúng.
- Timer UI 1 phút ở PiP/nền: hết giờ lúc khoảng 11:41:25, player dừng ở 147865 ms và giữ nguyên vị trí trong các mẫu sau; `timerExpired=true`.
- Lịch sử giữ vị trí 2:27 qua force-stop/mở lại; bấm lịch sử tiếp tục phát tại vị trí đó. Xem sau hiển thị video đã lưu.
- Nút UI chọn 5× hoạt động; sau kiểm thử trả lại 1× và tạm dừng.
- Fullscreen/landscape: video và thanh điều khiển hiển thị được; Back trở về bố cục thường.
- PiP: Android báo task ở `mode=pinned`; ảnh kiểm tra cho thấy chỉ có video trong ô nổi và player tiếp tục phát.
- Source smoke 5 video: 2 video phát được với HTTP Range 206; 3 video bị nguồn từ chối được báo HTTP 422 rõ ràng. Video ID không hợp lệ trả 400. Đây là kiểm tra xử lý lỗi, không phải tỷ lệ phủ nội dung đạt yêu cầu sản phẩm.

Bằng chứng local: `artifacts/qa/integration.log`, `landscape.png`, `pip.png`, `artifacts/provider-smoke.json`. Số liệu player được đọc trong khi test đang chạy; file cache trên máy không còn sau teardown/cài lại. Script đã được sửa để các lần chạy sau xuất JSON vào log trước teardown. URL có chữ ký không được đưa vào báo cáo.


## Giới hạn của bản thử

- Dịch vụ nguồn và relay chạy trên Mac, kết nối điện thoại qua `adb reverse`. Rút kết nối hoặc tắt dịch vụ có thể làm phát dừng khi hết buffer.
- Một số video bị YouTube từ chối nguồn. Không sử dụng cookie/tài khoản Google, không cam kết phát mọi video hoặc hoạt động ổn định lâu dài.
- Không có SDK quảng cáo, không chèn quảng cáo vào player. Nội dung tài trợ đã nằm trong video không được tự cắt.
- Chưa có đăng nhập Google, đồng bộ, live/DVR, Cast, phụ đề UI hoặc playlist đầy đủ.
- Chưa build/test iOS, iPadOS, TV, desktop và web. Layout co giãn trên Android không đồng nghĩa mọi nền tảng đã hỗ trợ.
- Các bài kiểm tra riêng tốc độ 5× và chất lượng 2160p không khẳng định tổ hợp 2160p ở 5× mượt trên thiết bị này.

## APK bàn giao

`artifacts/ytb-preview-0.1.0.apk` — SHA-256 `da70a915b18f4d89fce7bbd84a0896465991b7cde71c9d9463624f642c8b3684`. Đây là APK arm64 đã cài trên Samsung, dùng debug signing.
