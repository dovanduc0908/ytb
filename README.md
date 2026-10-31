# Diu Túp — Android 0.10.0

Diu Túp kết nối thư viện YouTube của từng tài khoản Google và phát video Facebook trên Android. Không cần máy chủ riêng, máy tính hoặc USB khi sử dụng.

Website: https://diutup.duckdns.org/ · [Quyền riêng tư](https://diutup.duckdns.org/privacy.html) · [Điều khoản](https://diutup.duckdns.org/terms.html).

## YouTube và tài khoản Google

- Đăng nhập bằng tài khoản của bạn để đọc kênh đã đăng ký, playlist của bạn và video đã thích qua YouTube Data API v3. Chỉ yêu cầu quyền `youtube.readonly` ngoài nhận diện Google cơ bản.
- Video, playlist, kênh, tìm kiếm, Shorts và karaoke mở trong ứng dụng hoặc website YouTube chính thức. Với playlist riêng tư, chọn cùng tài khoản trong YouTube.
- Bản 0.10.0 đã bỏ lấy nguồn/phát trực tiếp, tìm kiếm không chính thức và tải YouTube. Tệp YouTube cũ không còn phát trong app; người dùng vẫn có thể chủ động xóa chúng.
- Dữ liệu Google chỉ giữ trong bộ nhớ khi mở trang tài khoản. Không đưa token vào bộ lấy nguồn Facebook, lịch sử cục bộ hoặc máy chủ riêng. Google Play Services có thể giữ trạng thái đăng nhập; nút Ngắt kết nối xóa dữ liệu phiên và yêu cầu thu hồi quyền.
- Đổi tài khoản xóa danh sách cũ trước khi kết nối. Đồng bộ chỉ thay toàn bộ dữ liệu sau khi cả ba danh sách tải thành công.

**Trạng thái Google:** dự án đã chuyển sang production; thương hiệu đã được Google xác minh, quyền đọc YouTube vẫn đang chuẩn bị xét duyệt. Console hiện áp dụng giới hạn 100 người cấp quyền và có thể hiện cảnh báo ứng dụng chưa xác minh. Chưa coi đây là đăng nhập công khai không giới hạn. [Cấu hình và các bước còn lại](docs/GOOGLE_ACCOUNT_SETUP.md).

## Trình phát Facebook

- Dán link Facebook để lấy các mức chất lượng nguồn có sẵn, ghép âm thanh riêng và lọc theo khả năng giải mã của thiết bị.
- Auto ưu tiên nguồn tương thích cao nhất trên Wi-Fi; trên SIM ưu tiên mức không vượt 480p, hoặc mức thấp nhất nếu nguồn không có lựa chọn dưới 480p. Chuyển mạng áp dụng lại chính sách, giữ vị trí xem.
- Chọn hướng ngang/dọc hoặc Theo video. Metadata đến muộn không ghi đè hướng người dùng chọn. Vuốt từ mép trên để xem thanh hệ thống không điều chỉnh âm lượng/độ sáng.
- Tăng cường hình ảnh Tắt/Tự động/Mạnh dùng phóng hình Lanczos và tăng nét GPU có giới hạn. Đây không phải AI phục hồi chi tiết và không đổi độ phân giải thật của nguồn.
- Tốc độ 0,25–4×, tua, zoom, hẹn giờ, hàng đợi, lịch sử, xem sau, PiP chủ động và tải Facebook khi nguồn/quyền nội dung cho phép.

Facebook có thể thay đổi nguồn hoặc yêu cầu đăng nhập; video riêng tư/giới hạn truy cập không được bảo đảm hỗ trợ. Chất lượng phụ thuộc video gốc, mạng và thiết bị. Android TV có receiver trong APK nhưng chưa kiểm tra trên TV vật lý. Chưa có bản iOS.

## Cài đặt và phát triển

Bản đã phát hành nằm ở [GitHub Releases](https://github.com/dovanduc0908/ytb/releases). APK chứa ARM32, ARM64 và x86-64. Gói `com.duchaik.ytb` và khóa ký hiện tại được giữ để cập nhật các bản thử đã cài; chưa phải cấu hình phát hành Google Play.

```bash
bash scripts/build-release.sh
bash scripts/install-android.sh SERIAL apps/native/build/app/outputs/flutter-apk/app-release.apk
source scripts/env.sh
cd apps/native
flutter analyze
flutter test test
```

Không đưa client secret, keystore, token hoặc dữ liệu tài khoản vào Git. Web OAuth client ID là mã định danh công khai, có giá trị mặc định trong app; dự án khác có thể ghi đè bằng `--dart-define=YTB_GOOGLE_WEB_CLIENT_ID=...` và phải đăng ký đúng package/chứng thư ký Android.

## Kiến trúc và kiểm thử

- `apps/native/lib/youtube_account.dart`: đăng nhập, API chỉ đọc, phân trang và lỗi an toàn.
- `youtube_account_page.dart`: dữ liệu phiên, đổi/ngắt tài khoản, ba danh sách và mở liên kết chính thức.
- `official_youtube.dart`: chỉ tạo URL YouTube chính thức; nội dung khác trở thành truy vấn tìm kiếm.
- `OnDeviceSource.kt`: lấy nguồn Facebook với danh sách extractor được giới hạn.
- `MediaIdentity.kt`, `PlaybackService.kt`, `OfflineDownloads.kt`: chặn YouTube ở các ranh giới phát/tải native, kiểm tra ID và miền CDN.
- `main.dart`: giao diện, lịch sử Facebook và điều phối native.
- Các nguyên mẫu cũ trong `services/` và các mô-đun feed cũ không được dùng trong ứng dụng hiện tại.

[QA bản Google/YouTube chính thức](docs/GOOGLE_PUBLIC_QA.md) · [QA chất lượng/xoay màn hình](docs/VIDEO_QUALITY_0.9_QA.md) · [Lịch sử các bản cũ](docs/LEGACY_RELEASE_HISTORY.md) · [Thành phần nguồn mở](docs/THIRD_PARTY.md).
