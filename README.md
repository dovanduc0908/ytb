# Diu Túp — Android độc lập 0.8.5

Ứng dụng Flutter + Android Media3 tự tìm và phát video YouTube ngay trên điện thoại. **Chỉ cần Internet (Wi-Fi/4G/5G); không cần Mac, USB, máy chủ riêng, Termux hay ứng dụng phụ.** Python, yt-dlp, EJS và QuickJS cần cho bộ lấy nguồn đã nằm trong APK.

APK: [gen/Diu-Tup-dung-thu/Diu-Tup-0.8.5.apk](gen/Diu-Tup-dung-thu/Diu-Tup-0.8.5.apk). Cài APK rồi mở **Diu Túp**. Không có đăng nhập hoặc tài khoản. APK chứa ARM32, ARM64 và x86-64; thiết bị đã kiểm tra thực tế là Samsung Galaxy S10+ ARM64/Android 12. Logo D2K: Đức Hai Ka, sinh năm 2000, trong `gen/logo/`.

## Mới trong 0.8.5

Đổi tên ứng dụng thành **Diu Túp**, giữ nguyên mã ứng dụng và khóa ký thử để có thể cập nhật bản Android hiện có. Chưa có bản iOS: cần triển khai phần phát/nguồn cho iOS, Xcode và cấu hình ký ứng dụng.

## Mới trong 0.8.4

- Phụ đề theo ngôn ngữ có sẵn của video, kể cả phụ đề tạo tự động; bật/tắt trong Tùy chọn phát. Dữ liệu phụ đề và chương tải sau khi video bắt đầu, không làm chậm đường phát. Một số video hoặc nguồn không cung cấp phụ đề.
- Danh sách chương có thể chọn để tua. Ưu tiên chương do nguồn cung cấp, dự phòng bằng danh sách mốc thời gian hợp lệ trong mô tả.
- Chất lượng tự động dùng ước lượng băng thông, tốc độ phát và lượng đệm; nâng/hạ có độ trễ chống dao động. Do nguồn hiện tại dùng URL riêng cho từng mức, khi chuyển có thể tạm dừng ngắn; chọn một độ phân giải sẽ giữ cố định.
- Thêm trộn hàng đợi, sao chép liên kết tại thời điểm đang xem, lọc tìm kiếm theo ngày đăng và thời lượng; thư viện có mục đang xem dở, tìm trong lịch sử/xem sau và danh sách đã lưu. Các bộ lọc dùng kết quả YouTube và tiếp tục tải trang tiếp theo.

## Mới trong 0.8.3

- Đường lấy nguồn phát không chờ yêu cầu bổ sung thể loại; thông tin này tải sau khi phát. Nguồn đã lấy chỉ được giữ trong thời gian URL còn hiệu lực, tối đa 15 phút; giới hạn nguồn dự phòng 35 giây.
- Cache media mặc định 256 MiB, tùy chọn 128/256/512 MiB áp dụng khi mở lại; có nút xóa riêng, giữ lịch sử và vị trí xem. Chỉ chuẩn bị trước media trên mạng không tính dung lượng, hủy khi mở video khác hoặc rời app.
- Chỉ video có thời lượng trên 30 phút, không phải live/Shorts, được lưu vị trí xem dở. Video còn lại phát từ đầu khi mở lại; gần hết cũng phát từ đầu. Dịch vụ lưu vị trí khi tạm dừng, đổi video và rời app.
- Nút lặp trên màn hình xem và trong tùy chọn phát chuyển giữa tắt, lặp video và lặp danh sách; mở lại app mặc định tắt lặp. Tự động phát tiếp và hẹn giờ vẫn giữ nguyên.

## Mới trong 0.8.2

Vuốt dọc bên trái để chỉnh âm lượng, bên phải chỉnh độ sáng và ở giữa phía dưới nút pause để đổi tốc độ 0,25–3,5×. Các chỉ báo có biểu tượng và thanh mức, tự ẩn khi ngừng thao tác. Rời ứng dụng bằng Home, Back hoặc đóng tác vụ sẽ dừng phát và dịch vụ; cửa sổ PiP chỉ tiếp tục khi người dùng chủ động mở và còn nhìn thấy cửa sổ.

## Mới trong 0.8.1

Khi khóa toàn màn hình, các nút được ẩn khỏi video; chạm màn hình để hiện hoặc ẩn nút mở khóa, nút cũng tự ẩn sau 3 giây. Khi kéo thanh tiến độ hoặc vuốt ngang để tua, thời gian đích và khoảng tua xuất hiện sát thanh tiến độ. Ở mức zoom mặc định, vuốt ngang trong toàn màn hình tua trái/phải; vuốt dọc vẫn chỉnh độ sáng, âm lượng hoặc tốc độ theo vùng. Khi đã zoom, kéo một ngón tay để đổi vị trí hình.

## Mới trong 0.8.0

- Âm thanh chọn AAC/Opus stereo tốt nhất có sẵn của bản tiếng mặc định, không còn giới hạn AAC. Dùng độ lớn âm thanh YouTube cung cấp để giảm mức phát của bản thu quá lớn, không tăng gain hoặc giả lập bitrate. Mục tùy chọn phát hiển thị codec và bitrate nguồn. Đây không phải quyền truy cập Premium 256 kbps: chất lượng phụ thuộc nguồn được cấp.
- Thẻ video, màn hình xem và Shorts hiển thị lượt xem; số của bảng xếp hạng âm nhạc được ghi rõ là lượt xem trong kỳ BXH. Bấm tên người đăng hoặc “Xem kênh” để mở trang kênh, mô tả, video công khai và tải trang tiếp theo.
- Dịch vụ phát học sau 6 bài nhạc khác nhau được nghe thực tế 15–30 giây mỗi bài. Ưu tiên bài thường nghe, bổ sung nhạc liên quan đã kiểm tra thể loại, loại trùng và tránh 3 bài vừa phát; thêm tối đa 6 bài khi hàng đợi còn tối đa 2. Tự chuyển bài khi kết thúc, bỏ qua gợi ý không phát được, tôn trọng hẹn giờ ngủ và chế độ lặp.
- Phim, Shorts và nội dung chưa xác định là nhạc không kích hoạt danh sách tự động. Mở phim loại bỏ các mục nhạc tự thêm nhưng giữ mục người dùng thêm thủ công. Có công tắc “Tự phát nhạc phù hợp”; xóa lịch sử/xóa hồ sơ sẽ xóa cả dữ liệu học nhạc. Các mục gợi ý có nhãn riêng.

Tham khảo cơ chế công khai: [chất lượng âm thanh Premium](https://support.google.com/youtube/answer/6308116), [tín hiệu đề xuất và video tiếp theo](https://support.google.com/youtube/answer/16089387). Hồ sơ trong ứng dụng được tính trên máy, không sao chép thuật toán hoặc lịch sử tài khoản YouTube.

## Mới trong 0.7.0

Toàn màn hình: vuốt dọc bên trái chỉnh âm lượng media, bên phải chỉnh độ sáng cửa sổ; kéo ngang để tua và vuốt dọc ở giữa phía dưới để đổi tốc độ 0,25–3,5×. Chụm hai ngón để zoom 1–4×, kéo để đổi vị trí khi đã zoom, nút đặt lại để về khung hình gốc. Khóa giữ hướng màn hình và chặn thao tác/Back trong ứng dụng; chạm màn hình để hiện nút mở khóa. Thanh tiến độ hiện thời điểm đích và khoảng tua trước khi thả. Ở màn hình dọc, kéo video xuống để thu về preview video phía trên thanh điều hướng.

Tìm kiếm giữ đầy đủ cấu trúc kết quả và continuation từ YouTube, không cắt còn 30 video/8 gợi ý, thêm bộ lọc “Mới trong tuần”. Từ khóa tìm kiếm đóng góp nhẹ vào hồ sơ đề xuất cục bộ khi bật cá nhân hóa. Tốc độ chỉ giữ trong phiên, mở lại ứng dụng về 1×.

## Mới trong 0.6.0

Header chỉ logo, micro tìm kiếm tiếng Việt, video liên quan tải theo trang riêng, tìm karaoke khi đang phát, hàng đợi nền và danh sách lưu, hai chạm ±10 giây, Shorts thật vuốt dọc. Có receiver Android TV cùng APK, ghép mã trong mạng nội bộ và điều khiển từ điện thoại; các hệ TV khác có lối mở phản chiếu hệ thống tùy khả năng thiết bị. Xem [phạm vi, giới hạn và QA 0.6](docs/DUCHAIK_0.6_QA.md).

## Tính năng

- Trang chủ mới trộn bảng xếp hạng **âm nhạc** Việt Nam/thế giới có ngày nguồn cung cấp với video phổ biến trong tuần thuộc nhiều chủ đề. Đây không phải bảng Trending của mọi thể loại YouTube; mỗi thẻ ghi nguồn đề xuất.
- Cá nhân hóa trên điện thoại từ thời gian xem thực tế, hoàn thành, bỏ qua sớm, xem sau và “Không quan tâm”. Sở thích giảm trọng số theo thời gian; vẫn có phần khám phá ngoài sở thích. Không gửi hồ sơ hành vi lên máy chủ riêng; YouTube nhận yêu cầu tìm kiếm/phát video như thường lệ.
- Cài đặt cho phép tắt cá nhân hóa và xóa lịch sử/hồ sơ đề xuất. Không đồng bộ hoặc sao lưu hồ sơ lên đám mây; mỗi lần cài mới bắt đầu riêng.
- Cuộn tự tải tiếp bằng continuation thật, loại trùng, chuẩn bị trước một trang và ảnh/video gần vùng nhìn. Không đặt hạn mức đề xuất theo ngày; nguồn hết hoặc mạng lỗi có trạng thái/thử lại. Làm mới theo ngày hoặc kéo xuống; trang đầu đã lưu hiện ngay trong khi cập nhật.
- Tìm kiếm qua HTTP/2 với phản hồi đầy đủ; chuẩn bị kết quả sau khi ngừng gõ 400 ms, gộp các yêu cầu trùng.
- Mở video bằng metadata player trực tiếp, dự phòng bằng engine đóng gói. Chuẩn bị trước tối đa hai video; chỉ tải trước phần đầu media trên mạng không tính dung lượng (thường Wi-Fi), cache đĩa mặc định 256 MiB, có thể chọn 128/256/512 MiB. Khóa cache theo video/định dạng/phiên bản nguồn giúp tái sử dụng dữ liệu khi URL có chữ ký đổi.
- Giao diện nền tối, danh sách video sát mép, điều khiển nằm trên hình, toàn màn hình ngang và nút Back trở về dọc.
- Gợi ý YouTube khi gõ (chờ 120 ms sau phím cuối), chọn/điền gợi ý, lịch sử 20 từ khóa có nút xóa.
- Lưu tạm kết quả/gợi ý 1 phút; tìm kiếm và gợi ý có luồng riêng, không bị bộ lấy nguồn chặn.
- Mở liên kết/ID YouTube.
- Trình phát native có âm thanh; 14 mức tốc độ 0,25–3,5×, bước 0,25×.
- Chọn chất lượng theo nguồn và decoder thực tế, tối đa 2160p. Auto khởi đầu ở mức cao nhất không vượt 720p để giảm chờ. Đường nhanh trả cả 2K/4K khi nguồn cung cấp và thiết bị giải mã được; tự điều chỉnh dựa trên băng thông và dữ liệu đệm.
- Tua ±10 giây/slider; chỉ gửi lệnh tua khi thả thanh kéo, tránh tải liên tục trong lúc kéo. Ưu tiên keyframe trong phạm vi ±0,3 giây nếu có. Bố cục dọc/ngang, PiP theo yêu cầu, hẹn giờ ngủ theo phút.
- Lịch sử, tiếp tục vị trí cũ và xem sau lưu trên điện thoại; tốc độ reset về 1× mỗi lần mở lại ứng dụng.
- Không tích hợp SDK quảng cáo hoặc chèn quảng cáo vào player.

Nguồn YouTube không chính thức có thể thay đổi hoặc từ chối một số video. Đường lấy nguồn nhanh có phương án dự phòng; một số video phải dùng engine dự phòng có thể cần vài chục giây; mạng phải đủ nhanh cho chất lượng/tốc độ đã chọn. Video giới hạn tuổi/tài khoản, DRM và live/DVR chưa được hỗ trợ đầy đủ. Nội dung tài trợ nằm sẵn trong video không được tự cắt.

Android điện thoại đã được test trên Samsung. Receiver Android TV có trong cùng APK, chưa kiểm trên TV vật lý. Chưa có bản iOS/iPadOS/web/desktop, Cast chính thức, AirPlay, Tizen/webOS/Roku/Vega, đồng bộ tài khoản. Playlist karaoke lưu trên máy.

## Build từ mã nguồn

Các lệnh sau chỉ dành cho phát triển; người dùng APK không cần thực hiện:

```bash
./scripts/build-release.sh
./scripts/install-android.sh R58N405MC2R apps/native/build/app/outputs/flutter-apk/app-release.apk
```

Bản release hiện dùng khóa debug để cài cập nhật cùng ứng dụng thử trên Samsung; chưa phải cấu hình ký phát hành lên cửa hàng.

```bash
source scripts/env.sh
cd apps/native
flutter analyze
flutter test test
```

`./scripts/test-android.sh SERIAL` chạy kiểm thử tích hợp trên điện thoại. Script không mở ADB reverse và không gọi dịch vụ Mac. `scripts/device-ui.py` kiểm tra UI theo accessibility bounds.

## Cấu trúc

- `apps/native/lib/main.dart`: UI, lịch sử/xem sau, giao tiếp native.
- `apps/native/lib/feed_repository.dart`: bảng xếp hạng, khám phá, continuation, loại trùng và chuẩn bị trang.
- `apps/native/lib/recommendations.dart`: điểm sở thích, thời gian xem thực tế, giảm trọng số và lưu hồ sơ cục bộ.
- `YouTubeCharts.kt`: lấy bảng xếp hạng âm nhạc VN/GLOBAL, cache 1 giờ, dự phòng bản đã lưu tối đa 7 ngày có nhãn.
- `apps/native/android/app/src/main/kotlin/com/duchaik/ytb/OnDeviceSource.kt`: điều phối riêng tìm kiếm/gợi ý và lấy URL nguồn bằng engine đóng gói trong APK.
- `YouTubeSearch.kt`: tìm video/gợi ý qua HTTPS, cache LRU có thời hạn; không cần API key.
- `apps/native/lib/search_box.dart`: debounce, chống phản hồi cũ, gợi ý và lịch sử tìm kiếm.
- `PlaybackService.kt`: lấy video/audio trực tiếp qua HTTPS, ghép luồng Media3, đổi chất lượng giữ vị trí, tốc độ, audio focus và timer native.
- `MainActivity.kt`: platform channels và PiP/video surface.
- `services/source_provider`: nguyên mẫu cũ 0.1.0, **không dùng trong APK từ 0.2.0 trở lên**.
- `toolchain.json`: phiên bản công cụ. [Thành phần nguồn mở](docs/THIRD_PARTY.md).

Xem [QA tính năng 0.6.0](docs/DUCHAIK_0.6_QA.md), [QA đề xuất và tua 0.5.0](docs/DUCHAIK_0.5_QA.md), [QA tốc độ và toàn màn hình 0.4.0](docs/ANDROID_FAST_QA.md), [QA tìm kiếm 0.3.0](docs/ANDROID_SEARCH_QA.md), [kế hoạch tổng thể](PLAN.md), [QA bản độc lập](docs/ANDROID_STANDALONE_QA.md). Báo cáo `ANDROID_QA.md` chỉ mô tả nguyên mẫu cũ 0.1.0.
