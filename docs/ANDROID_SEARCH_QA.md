# Android 0.3.0 — tìm kiếm và gợi ý

Ngày kiểm thử: 26/10/2026 (Asia/Saigon). Samsung Galaxy S10+ SM-G975U1, Android 12, ARM64.

## Thay đổi

Trước đây tìm kiếm khởi động yt-dlp/Python và chạy `ytsearch20`, mất khoảng 4,1–4,5 giây trong log release 0.2.0 gần nhất. Bản 0.3.0 gửi HTTPS trực tiếp tới tìm kiếm YouTube; chỉ khởi động engine khi mở video. Tìm kiếm, gợi ý và lấy nguồn có executor riêng. Gợi ý chờ 180 ms sau phím cuối; bỏ phản hồi cũ và bỏ các tác vụ gợi ý đã lỗi thời còn nằm trong hàng đợi. Tối đa 24 kết quả truy vấn và 80 truy vấn gợi ý được cache LRU 5 phút trong RAM, không cache stream ở đây.

Giao diện thêm gợi ý khi nhập, bấm để tìm, mũi tên để điền vào ô, nút xóa từ khóa, tối đa 20 từ khóa gần đây trên thiết bị và nút xóa lịch sử tìm kiếm. Lỗi tải gợi ý không chặn việc gửi truy vấn. Không thay đổi nội dung IME đang soạn tiếng Việt. Khi tìm lại, dùng cache còn hạn; không yêu cầu Mac, USB hoặc backend.

## Đo trên Samsung

Lượt tích hợp cuối đạt trong 25 giây. Đồng hồ Stopwatch đo từ gọi platform channel tới nhận danh sách dữ liệu. Không bao gồm thời gian tải thumbnail, vẽ frame hay thời gian mở nguồn phát. Đây là mẫu đo trên mạng hiện tại, không phải benchmark đối đầu ứng dụng YouTube Premium.

| Truy vấn mới | Thời gian | Video |
|---|---:|---:|
| Blender open movie (lượt đầu tiến trình) | 1.380 ms | 20 |
| nhạc không lời | 700 ms | 20 |
| nhạc lofi | 781 ms | 20 |
| công nghệ | 617 ms | 20 |
| nature documentary 4k | 635 ms | 20 |
| nhạc lofi (cache) | 4 ms | 20 |

Gợi ý: `nhac` 292 ms ở lượt đầu; `nhạc`, `lofi`, `son tung`, `công nghệ` lần lượt 76, 73, 72, 74 ms; `nhac` cache 3 ms. Các số này chưa cộng debounce 180 ms. Hai lượt đo trước cho kết quả mạng thay đổi: tìm kiếm 665–1.524 ms, gợi ý 79–678 ms, cho thấy không nên hứa thời gian cố định.

## Kiểm tra chức năng

- `flutter analyze`: đạt, không có vấn đề.
- 7 unit/widget tests đạt: 3 kiểm thử cũ và 4 kiểm thử debounce/chống phản hồi cũ, chọn gợi ý, xóa khi đang tải, mạng lỗi, gửi trước debounce, lịch sử, IME tiếng Việt.
- Tích hợp nguồn thật: 5 truy vấn mới, truy vấn cache, 5 từ khóa gợi ý, gợi ý cache; tất cả có kết quả. Video `jNQXAC9IVRw` phát tới 2.136 ms, `playing=true`, audio `audio/mp4a-latm`.
- Release: mở video từ kết quả `nhac chill`, nguồn lấy trong 18.239 ms, UI tới 0:24 / 1:32:08 và hiện nút Tạm dừng; không có lỗi player/runtime trong log tiến trình. Sau kiểm tra đã tạm dừng và trở về tìm kiếm.
- Một lượt smoke trước bị gián đoạn kết nối test; giữ trong `integration-interrupted.log`. Lượt hoàn chỉnh cuối mới là kết quả đạt.
- Release 0.3.0 đã cài cập nhật thành công, xác nhận `versionCode=3`, `versionName=0.3.0`.
- Kiểm tra bằng UI thật: gõ `nhac` hiện 8 gợi ý, bấm `nhac chill` điền đúng từ khóa, đóng bàn phím và hiện kết quả video. Log release: tìm lúc mở app 914 ms, gợi ý đầu 313 ms, tìm từ gợi ý 1.142 ms.

Bằng chứng: `artifacts/search/search-qa.json`, `integration.log`, `widget-tests.log`, `analyze.log`, `suggestions-ui.txt`, `results-ui.txt`, `suggestions-release.png`.

## Phạm vi và tái chạy

Gợi ý là từ khóa YouTube và lịch sử tìm kiếm cục bộ; chưa có đề xuất cá nhân hóa theo tài khoản Google. Tốc độ lấy URL/phát video là đường xử lý khác, vẫn có thể mất khoảng 15–20 giây. Chưa thay engine phát trong bản này. Endpoint web không chính thức có thể thay đổi, yêu cầu cập nhật client/parser; không có bảo đảm hoạt động vĩnh viễn.

```sh
source scripts/env.sh
cd apps/native
flutter test test
flutter test integration_test/search_test.dart -d R58N405MC2R --reporter expanded
```

Sau integration test, cài lại APK thường bằng `scripts/install-android.sh SERIAL APK` vì integration test dùng màn hình tạm thời.

## APK

`artifacts/ytb-standalone-0.3.0.apk`, ARM64, ký bằng khóa debug cùng ứng dụng thử trước để cài cập nhật. SHA-256: `5e5bc0d273024a52221796a383d69dc136adb662c2183c861ccc0a4874bd6058`.
