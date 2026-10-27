# Duchaik YTB 0.5.0 — QA ngày 26/10/2026

APK bàn giao: `gen/Duchaik-YTB-0.5.0.apk`, 72.831.376 byte. Package `com.duchaik.ytb`, version code 5, min SDK 24 (Android 7), target SDK 36. Một APK có ARMv7, ARM64 và x86-64, đã kiểm tra đủ `libapp.so`, `libflutter.so`, Python runtime theo từng ABI. Chữ ký APK đã kiểm tra hợp lệ; bản thử vẫn ký debug để cập nhật bản cũ.

SHA-256: `43c8d37e4b31620f36791790f8826961ba3a1221644009eb33956fc4220c4c3a`.

## Thiết bị và kiểm tra

Samsung Galaxy S10+ SM-G975U1, Android 12, ARM64, mạng Wi-Fi tại thời điểm đo. ARM32, x86-64 và các thiết bị khác mới được kiểm tra thành phần trong APK, chưa kiểm tra chạy thực tế. iOS/iPadOS/TV/web chưa phải bản phát hành của đợt này.

- `flutter analyze`: không có vấn đề.
- 13 unit/widget tests đạt: tìm kiếm/gợi ý, chống phản hồi cũ, IME tiếng Việt, các tiện ích player, slider chỉ gửi một lệnh khi thả, thời gian xem thực tế, bỏ qua seek/buffering, tắt cá nhân hóa, điểm sở thích/lưu hồ sơ/giảm trọng số/ẩn video, phân trang hơn 300 video không trùng và phục hồi mạng.
- `discovery_seek_test.dart`: hai nguồn thật VN/GLOBAL, 100 video mỗi nguồn; ngày nguồn trả 24/10/2026. Continuation thật của tìm kiếm trả thêm kết quả mới; 3 trang đề xuất × 24 video không trùng; seek có tiếng, 2160p phát tiếp 5 giây không lỗi.
- `feed_ui_test.dart`: tên/logo mới, không có đăng nhập, cuộn tự nối trang, bật/tắt cá nhân hóa và khôi phục cài đặt ban đầu.
- `fullscreen_test.dart`: bấm video thật, xoay ngang, native PlayerView 2173×1080, TextureView 2173×909 cho video Spring; phát tiếp sau xoay; Back về dọc và phục hồi thanh điều hướng.
- Release: cài trực tiếp APK trong `gen`, mở trang Việt Nam/thế giới, kiểm tra Cài đặt, phát video âm nhạc thực tế từ trang chủ hơn 20 giây, xoay toàn màn hình và Back. Ảnh tại `artifacts/duchaik-0.5/home-release.png`, `fullscreen-release.png`.

## Số đo

Đây là vài mẫu trên thiết bị/mạng nêu trên, không phải p95 hoặc cam kết cho mọi video. Các integration test chạy debug; số release được ghi riêng.

| Hạng mục | Kết quả |
|---|---:|
| Lấy bảng xếp hạng qua mạng, mỗi khu vực | 1.748–2.050 ms |
| Trang đề xuất đầu trong bài test, chart đã lấy trước, truy vấn khám phá/cá nhân hóa qua mạng | 1.277–1.570 ms |
| Trang 2–3 từ tập ứng viên đã lấy, trước tối ưu tính điểm | 115–121 ms |
| Trang 2–3 sau chỉ tính điểm một lần/mỗi ứng viên | 15–19 ms |
| Resolve + load + frame đầu của Bunny trong lượt kiểm tra cuối | 731 ms |
| Resolve + load + frame đầu Spring đã chuẩn bị trước | 216 ms |
| Bốn lần tua 10 s / 180 s trong lượt cuối | 157 / 562 / 350 / 562 ms |
| Release: video âm nhạc trang chủ đã chuẩn bị trước, resolve cache | 0 ms theo log native |
| Release: load đến frame đầu của video đó | 344 ms |

Không coi số trang 2–3 là thời gian tải toàn bộ ảnh/render màn hình hoặc yêu cầu mới qua Internet. App chuẩn bị trước một trang; ảnh được cache/chuẩn bị riêng. Không bảo đảm mọi lần mở/tua dưới 0,5 giây. Báo cáo thô: `artifacts/duchaik-0.5/*.log`, `discovery-seek.json`, `fullscreen.json`, `apk-abis.json`, `installed.json`.

## Nguồn và cá nhân hóa

- Nguồn chính là bảng xếp hạng âm nhạc công khai YouTube Charts `VN` và `GLOBAL`, có ngày nguồn; không giả danh bảng Trending toàn bộ thể loại. [Tài liệu YouTube về Charts](https://support.google.com/youtube/answer/9014376?hl=en).
- Khám phá thêm video phổ biến trong tuần theo nhiều chủ đề VN/quốc tế, xoay chủ đề theo ngày, continuation thật. Tối thiểu một phần trang dành cho khám phá ngoài sở thích khi nguồn có đủ.
- Thời gian xem ghi nhận theo đồng hồ thực tế, loại nhảy vị trí do tua/buffering; học từ kênh và từ khóa tiêu đề, tăng điểm xem sau/hoàn thành, giảm điểm bỏ qua sớm/không quan tâm. Đây là mô hình sở thích cục bộ nhỏ, không phải hệ thống đề xuất hoặc dữ liệu cá nhân hóa của YouTube.
- Không có tài khoản, máy chủ riêng hoặc SDK quảng cáo/analytics. YouTube vẫn nhận các truy vấn tìm kiếm, ảnh và phát video. Hồ sơ không được gửi thành gói lên máy chủ; truy vấn khám phá có thể dùng kênh/từ khóa sở thích.
- Cài đặt cho phép tắt học/xếp theo sở thích, xóa lịch sử/hồ sơ; “Không quan tâm” vẫn là lựa chọn ẩn rõ ràng. Xem sau được giữ khi xóa lịch sử/hồ sơ, đúng thông báo xác nhận. Tắt Android backup/device transfer cho dữ liệu app.
- Không có quota theo ngày. Khi nguồn hết, giao diện báo hết; khi mạng lỗi, cho tải lại. Không thể bảo đảm nguồn video thực sự vô hạn.

## Tối ưu kỹ thuật

Cache video 128 MiB, key ổn định theo video + itag + lastModified (audio thêm track ID), tái sử dụng khi URL có chữ ký thay đổi. Prefetch tối đa 2 video, chỉ tải trước media trên mạng không tính dung lượng. Slider chỉ seek khi thả, Media3 cho phép chọn keyframe ±0,3 giây. Điểm mỗi ứng viên tính một lần khi sort. Tách luồng khám phá khỏi tìm kiếm/phát; trang đầu cache hiện ngay rồi cập nhật, chuẩn bị một trang tiếp theo và thumbnails quanh viewport.

Nguồn không chính thức vẫn có thể đổi/chặn, fallback đóng gói có thể chậm. Video hạn chế tài khoản/tuổi, live/DRM chưa hỗ trợ đầy đủ. Tài trợ chèn sẵn trong video không tự bị cắt. Chưa có cam kết tương thích mọi Android TV/remote hoặc mọi độ phân giải/mạng.
