# Android 0.4.0 — tốc độ và toàn màn hình

Ngày 26/10/2026. Samsung Galaxy S10+ SM-G975U1, Android 12, ARM64, Wi-Fi tại thời điểm thử.

## Thay đổi

- Search yêu cầu JSON chỉ gồm các trường cần hiển thị và visitor context, giảm phản hồi mẫu từ khoảng 727 KB xuống khoảng 43 KB. Không có máy chủ Mac trung gian.
- Gợi ý sau 120 ms ngừng gõ; chuẩn bị kết quả sau 400 ms. Cache LRU 5 phút, gộp yêu cầu trùng, bỏ công việc cũ còn trong hàng đợi.
- Nguồn player trực tiếp dùng public visitor context, trả AVC/VP9 từ 144p đến 2160p tùy video và decoder. Context ẩn danh lưu tối đa 12 giờ, không phải tài khoản Google. Engine đóng gói vẫn làm dự phòng khi metadata hoặc phát trực tiếp lỗi.
- Chuẩn bị metadata tối đa hai video đầu kết quả. Trên mạng không tính dung lượng, tải trước tối đa 384 KiB video và 64 KiB audio mỗi video. Cache đĩa LRU tối đa 32 MiB; mạng tính dung lượng chỉ chuẩn bị metadata.
- Media và metadata dùng OkHttp/HTTP2, chung connection pool. Range media giới hạn 8 MiB; thời gian chờ media tách khỏi timeout metadata.
- Auto bắt đầu ở track cao nhất không vượt 720p. Ngưỡng bắt đầu phát 250 ms; bộ đệm mục tiêu 15–50 giây. Chưa có adaptive bitrate tự thay đổi chất lượng liên tục.
- Bỏ banner giới thiệu, dùng nền đen/chữ trắng/điểm nhấn đỏ, thumbnail lớn, nút điều khiển trên hình và tự ẩn. Thương hiệu vẫn là YTB.
- Toàn màn hình ép ngang, ẩn thanh hệ thống, video chiếm toàn vùng hiển thị. Tạo lại platform surface theo kích thước cuối sau xoay/PiP; Media3 service giữ nguồn và vị trí phát. Back trở về dọc. Giữ tỷ lệ video nên có thể còn viền đen theo tỷ lệ màn hình.
- Không dựng lại UI khi trạng thái player không đổi; chỉ cập nhật cờ giữ sáng màn hình khi giá trị thực sự đổi.

## Số đo của đường nguồn cuối cùng

`integration-http2.log` đạt trong 64 giây. Cold nghĩa là chưa resolve/prefetch video đó trong tiến trình test; không phải phép đo cài mới hệ điều hành hay xóa cache hệ thống.

Đồng hồ bao trùm resolve → load → callback Media3 `onRenderedFirstFrame`, trên bề mặt video Android thật. Không bao gồm ngón tay, chuyển trang Flutter hoặc thumbnail. Build debug, một lượt hoàn chỉnh; không phải thử đối đầu với YouTube Premium.

| Trường hợp | Lấy nguồn | Đến khung hình đầu | Từ load đến khung hình |
|---|---:|---:|---:|
| Bunny mới, 720p | 407 ms | 927 ms | 474 ms |
| Me at the zoo mới, 240p | 741 ms | 1.266 ms | 521 ms |
| Spring chuẩn bị trước, 536p | 10 ms | 248 ms | 193 ms |
| Spring mở lại, 536p | 7 ms | 144 ms | 126 ms |

Spring có 3 giây để chuẩn bị trước khi bắt đầu đồng hồ; thời gian chuẩn bị không nằm trong 248 ms. Tất cả có AAC và vị trí phát tăng. Bunny/Spring được tua đến 180 giây rồi kiểm tra phát tiếp; Bunny đổi trực tiếp lên 2160p. Mỗi mẫu tiếp tục phát thêm 8 giây sau kiểm tra/tua/đổi chất lượng, không chỉ kiểm tra một khung hình đầu.

Search mới: 1.197 / 747 / 848 ms, mỗi truy vấn 20 video. Search đã chuẩn bị: 9 ms, sau 2 giây chuẩn bị trước. Không tính tải thumbnail. **Chưa đạt dưới 500 ms cho mọi truy vấn hoặc video mới.**

Thử nghiệm IOS ban đầu bị HTTP403 sau đoạn âm thanh đầu. Giảm Range không sửa được nên đã thay đường nguồn. `integration.log`, `integration-initial.log`, `probe.log`, `integration-long.log` là các bước chẩn đoán đã thay thế, không phải bằng chứng phát ổn định của bản bàn giao.

## Toàn màn hình trên thiết bị thật

`fullscreen_test.dart` chạy giao diện sản phẩm: chạm video Spring từ trang đầu, mở toàn màn hình, xác nhận Android thực sự xoay ngang, phát tiếp, rồi Back về dọc. Bài mở rộng kiểm tra bề mặt native đạt trong 12 giây.

Vùng video và viewport cùng 827,81 × 411,43 logical pixels. PlayerView native là 2173 × 1080 pixels, TextureView là 2173 × 909 pixels, khớp tỷ lệ của video Spring. Test xác nhận khung hình được render lên bề mặt mới cả khi đang tạm dừng, thanh điều hướng ứng dụng biến mất, phát tiếp sau xoay và Back phục hồi giao diện dọc. Không có lỗi Flutter. Phần cutout/hệ thống do thiết bị quản lý không được tính là vùng Flutter.

Bằng chứng cuối: `artifacts/fast/fullscreen-surface.log`, `fullscreen-qa.json`. Bài ban đầu `fullscreen.log` chỉ kiểm tra kích thước Flutter và hướng máy nên bỏ sót video nhỏ ở góc; ảnh release đã phát hiện lỗi đó và dẫn đến kiểm tra native cùng sửa cách tạo bề mặt nêu trên.

## Xác nhận bản release đã cài

Đã cài và đối chiếu SHA-256 của APK trên Samsung với `artifacts/ytb-standalone-0.4.0.apk`: khớp. APK 27.758.900 bytes; SHA-256 `5825f8f0ded5e30badcc117d19292d4f56bce482e5acde6e2be0e3e449dfb46f`.

Trên release cuối: search mới 1.012 ms; resolve đã chuẩn bị 0 ms, từ load đến khung hình đầu 237 ms. Đã mở Spring, tạm dừng, bật toàn màn hình và kiểm tra ảnh thật: video phủ đúng vùng hiển thị. Phát tiếp đến 1:34, tạm dừng rồi Back về dọc; không có YTBPlayer error trong log của tiến trình này. Cài đặt giữ sáng màn hình tạm thời khi QA đã trả về giá trị ban đầu 0.

Bằng chứng: `release-install.json`, `release-runtime.log`, `release-fullscreen-ui.txt`, `release-back-ui.txt`, `fullscreen-release.png` trong `artifacts/fast/`. `release-gfxinfo.txt` là snapshot Android view; không dùng nó để khẳng định toàn bộ Flutter UI hết jank.

## Hồi quy

8 unit/widget tests đạt: debounce, phản hồi lỗi thời, IME tiếng Việt, lỗi mạng, lịch sử, parse URL, tốc độ, đồng hồ và điều khiển/bố cục player. `flutter analyze` không có vấn đề.

Bài `player_test.dart` cuối đạt trong 2 phút 53 giây: 17/17 mức tốc độ 1–5×, 8/8 chất lượng 144/240/360/480/720/1080/1440/2160p, timer và video thứ hai. Tốc độ đo ở 480p sau khi có 30 giây buffer; không phải cam kết 4K ở 5×. Bài này dùng `resolveFull` để kiểm tra cả nguồn dự phòng.

Bằng chứng hiệu năng: `artifacts/fast/fast-qa.json`, `integration-http2.log`. Hồi quy cuối: `playback-final.log`; hồi quy trước chuyển HTTP2: `playback-regression.log`.

## Giới hạn

Giao thức nguồn không chính thức có thể thay đổi hoặc không áp dụng cho một số video. Nếu phải dùng engine dự phòng, vẫn có thể chờ 15–20 giây hoặc lâu hơn. Chuẩn bị trước dùng thêm dữ liệu với giới hạn nêu trên. Chưa có đăng nhập Google, đề xuất cá nhân hóa, đồng bộ hoặc bản iOS/TV.

## Tái chạy

Chạy tuần tự, không chạy các lệnh Flutter đồng thời trong cùng thư mục:

```sh
source scripts/env.sh
cd apps/native
flutter analyze
flutter test test
flutter test integration_test/fast_start_test.dart -d R58N405MC2R
flutter test integration_test/fullscreen_test.dart -d R58N405MC2R
flutter test integration_test/player_test.dart -d R58N405MC2R
```

Cài lại APK release sau integration test để trở về giao diện sản phẩm.
