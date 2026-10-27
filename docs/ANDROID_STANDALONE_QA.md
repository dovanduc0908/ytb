# Android độc lập 0.2.0 — kiểm thử Samsung

Ngày: 26/10/2026. Samsung Galaxy S10+ SM-G975U1, Android 12/API 31, arm64.

## Đường phát

Tìm kiếm → platform channel `ytb/source` → Python/yt-dlp/QuickJS đóng gói trong APK → HTTPS YouTube trên điện thoại. Video và audio → Media3 trên điện thoại → loa/màn hình.

Không có HTTP localhost, proxy/relay Mac hoặc máy chủ riêng trong đường phát mới. `usesCleartextTraffic=false`. Bộ engine được chép từ APK vào vùng dữ liệu riêng của app khi khởi tạo; không tải engine từ máy khác lúc dùng.

## Bằng chứng độc lập

- Tắt tiến trình `node server.mjs` của nguyên mẫu; cổng 8787 trên Mac không còn listener.
- Không có mapping ADB reverse cho 8787; script build/cài/test mới không thêm mapping này.
- Native log trên Samsung ghi `search OK ... on-device`, `resolve OK ... on-device`; video có hình/âm thanh và vị trí tăng khi dịch vụ Mac đã tắt.
- ADB chỉ được dùng để cài và quan sát kiểm thử, không vận chuyển dữ liệu video.

## Kiểm thử

Bài tích hợp dùng chính channel/player của ứng dụng, nguồn YouTube thật. Đo 17 tốc độ ở 480p; mỗi mức cần đủ 30 giây dữ liệu trong buffer trước khi đo 4 giây bằng đồng hồ thực. Điều này kiểm tra tốc độ playback khi có dữ liệu, không cam kết mạng nào cũng đủ nhanh cho 5×. Bài chạy đầu không đợi buffer gặp rebuffer tại 3×; vòng tiếp theo gặp gián đoạn khi chuyển 1080p. Sau đó thay cách tải whole-file bằng HTTPS Range tối đa 8 MiB mỗi yêu cầu. Các log trước sửa được giữ trong `integration.log` và `integration-buffered.log`; kết quả sau sửa trong `integration-chunked.log`.

Kết quả sau sửa: integration test đạt, thời gian 2 phút 56 giây.

- Tìm kiếm trực tiếp: 20 kết quả; không gọi backend.
- 17/17 tốc độ đạt; có luồng AAC. Tốc độ được đo khi đủ dữ liệu trong bộ đệm.
- 8/8 chất lượng 144, 240, 360, 480, 720, 1080, 1440, 2160p chọn đúng track và tiếp tục phát.
- Timer 3 giây: tự dừng phát và trả `timerExpired=true`.
- Video thứ hai `WhWc3b3KhnY`: tự lấy nguồn, bắt đầu tại giây 30, tiếp tục phát có âm thanh; track thực tế 858p theo tỉ lệ khung hình nguồn.
- `flutter analyze`: không có vấn đề. 3 unit test đạt.

Số liệu: `artifacts/standalone/player-qa.json`; log đầy đủ `integration-chunked.log`. Hai lần test trước sửa được giữ để đối chiếu.

| Tốc độ chọn | Tốc độ đo |
| --- | --- |
| 1× | 0.996× |
| 1.25× | 1.250× |
| 1.5× | 1.500× |
| 1.75× | 1.748× |
| 2× | 2.008× |
| 2.25× | 2.251× |
| 2.5× | 2.497× |
| 2.75× | 2.750× |
| 3× | 3.003× |
| 3.25× | 3.247× |
| 3.5× | 3.492× |
| 3.75× | 3.750× |
| 4× | 3.997× |
| 4.25× | 4.251× |
| 4.5× | 4.501× |
| 4.75× | 4.740× |
| 5× | 5.001× |


## Phạm vi

Cài APK rồi dùng Internet trực tiếp. Chưa có OAuth, đồng bộ, live/DVR, Cast, các nền tảng khác. Chưa đánh giá phát dài nhiều giờ hoặc tổ hợp 2160p ở 5×. APK arm64 dùng khóa debug cho cài thử, không phải khóa sản phẩm.

## Kiểm tra bản tối ưu

Bản release đầu gặp lỗi R8 tối ưu nhầm `AsiExtraField` của Apache Commons Compress khi giải nén Python. Đã thêm quy tắc giữ các lớp ZIP dùng reflection của Commons Compress; cold start sau sửa giữ tiến trình hoạt động dưới màn hình khóa; log release PID 23354 ghi tìm kiếm trực tiếp thành công lúc 12:26:20. Bản release sau sửa đã tự lấy và phát hết video thứ ba `jNQXAC9IVRw` (Me at the zoo), UI đạt 0:18/0:18, không có lỗi player trong PID 23354. Đây là lỗi đóng gói release, tách khỏi bài playback integration ở trên. Đồng thời sửa lỗi Android 12 từ chối startService khi Activity đang được tạo dưới màn hình khóa: chỉ khởi động player khi Activity đã resumed/focus, có xử lý trạng thái chưa được phép.

Bản bàn giao cuối đã được cài và mở lại sau khi người dùng mở khóa máy. PID 19275 ghi tìm kiếm trực tiếp thành công (4494 ms), lấy nguồn video thứ ba thành công (15998 ms), không có lỗi player/runtime trong log của tiến trình. Đã phát hết 0:18/0:18, bấm Phát video chuyển về 0:00 và trạng thái Tạm dừng, sau đó tạm dừng bằng UI. Bằng chứng: `release-source-final.log`, `replay-ui.txt`.

## APK

`artifacts/ytb-standalone-0.2.0.apk`, ARM64, 27567717 byte. SHA-256 `0975af6afa397c38865740b0dc3842199ecd656d5c039e04f618125c8f48a1e8`.
