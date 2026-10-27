# Duchaik YTB 0.6.0 — kiểm thử và phạm vi

Ngày triển khai: 26/10/2026. Package `com.duchaik.ytb`, Android API 24+, APK phổ thông ARMv7/ARM64/x86_64. Bản cập nhật thử nghiệm vẫn dùng khóa ký debug như các bản trước để cài đè.

## Có trong mã và bản bàn giao

- Header chỉ logo D2K. Tên launcher vẫn là Duchaik YTB.
- Micro bên thanh tìm: nhận tiếng Việt qua dịch vụ giọng nói Android, gửi một truy vấn khi có kết quả cuối; hủy giữ nội dung cũ, máy thiếu dịch vụ vẫn gõ tìm được. Dịch vụ hệ thống có thể xử lý âm thanh trên mạng; ứng dụng không lưu bản ghi âm.
- Video liên quan có nguồn `next` riêng, theo cursor; tách khỏi danh sách Trang chủ. Danh sách lazy, loại trùng ID, chuẩn bị trước trang tiếp và hai nguồn phát trên mạng không tính dung lượng. Khi nguồn liên quan hết/lỗi, dùng tìm kiếm theo ngữ cảnh; karaoke mở rộng bằng các từ khóa beat/song ca/tông nam/tông nữ. Không hạn mức trang/ngày, nhưng nguồn hữu hạn vẫn có điểm kết thúc và báo rõ.
- Tìm bài dưới video giữ bài đang phát. Karaoke có bộ lọc, phát ngay/phát tiếp/thêm cuối, kéo đổi thứ tự, xóa bài, lặp bài/danh sách và lưu danh sách trên máy.
- Hàng đợi nằm trong MediaSession service và được lưu trên máy. Hết bài sẽ tải bài tiếp; lỗi giữ lại bài trong hàng đợi, hẹn ngủ chặn tự chuyển. Có revision để tránh sửa một bản hàng đợi đã lỗi thời.
- Hai chạm trái/phải tua −/+10 giây, cộng dồn theo chuỗi, giới hạn đầu/cuối. Slider gửi seek khi nhả tay.
- Shorts dùng bộ lọc Shorts thực tế của nguồn, không dựa riêng vào tiêu đề hay thời lượng. Vuốt dọc, một phiên phát, lặp Short, lưu/không quan tâm, thanh tua, chọn tốc độ/chất lượng, thử lại khi lỗi. Sở thích Shorts tách riêng và dùng chung tùy chọn tắt cá nhân hóa. Rời Shorts khôi phục video dài trước đó.
- TV native trong cùng APK: launcher Android TV, màn hình receiver có mã ghép 6 số, discovery DNS-SD và nhập IP:cổng khi multicast bị chặn; truyền ID video và lệnh, TV tự lấy media trực tiếp. Có phát/dừng/tua/tốc độ/chất lượng/hẹn ngủ/hàng đợi; không cần máy Mac hay máy chủ chạy riêng.
- TV receiver chỉ lắng nghe IP riêng Wi-Fi/Ethernet, không mở trên dữ liệu di động; yêu cầu ghép mã, token ngẫu nhiên cho lệnh điều khiển, giới hạn lần nhập sai, kích thước yêu cầu và số worker. Giao thức TCP nội bộ chưa mã hóa: dùng mạng gia đình tin cậy; không chuyển tiếp cổng receiver ra Internet. Token chỉ tồn tại trong phiên.
- Có lối mở chức năng phản chiếu màn hình của hệ thống. Khả năng thực tế tùy điện thoại và TV; phản chiếu cần điện thoại tiếp tục phát.

## Chưa được coi là hoàn thành

Google Cast chính thức, receiver Samsung Tizen/LG webOS, DLNA trực tiếp, Vega/Matter Casting, AirPlay/Apple TV, Roku và VIDAA/Titan chưa được tích hợp/kiểm chứng trong bản này. Không tuyên bố mọi TV có thể phát trực tiếp. Fire OS là mục tiêu cài APK; Vega không phải Fire OS và không cài APK Android này.

Chưa có TV vật lý để kiểm codec/remote/firmware, độ ổn định phiên 30 phút, 20 bài, đổi mạng và reconnect giữa hai thiết bị thật. Kiểm receiver trên Samsung qua LAN chỉ xác nhận giao thức và logic Android; không thay thế kiểm TV.

Chưa có cấu hình Google OAuth; phiên này không có đăng nhập, theo yêu cầu trước. Không cam kết video nào cũng mở hoặc tua dưới 0,5 giây; phụ thuộc nguồn, mạng, cache và codec.

## Bằng chứng hiện có

- 19 unit/widget tests: parsing, tốc độ/clock, cá nhân hóa, phân trang, nguồn lỗi/token lặp/trùng ID, slider, fullscreen widget, hai chạm/clamp, autocomplete và voice submit/hủy/lỗi.
- Integration nguồn/service trên Samsung SM-G975U1 Android 12 (debug): 28 + 20 video liên quan ở hai trang; 408 bài karaoke khác nhau; 38 Shorts thật; tự chuyển sang Spring thành công, first frame native 110 ms trong mẫu đó; timer chặn chuyển bài. Hai trang liên quan mất 2527 ms tổng (network + parse), không phải mỗi trang dưới 0,5 s. Xem `artifacts/duchaik-0.6/features-06.json`.
- Integration giao diện debug: 100 Shorts khác nhau, tìm karaoke giữ video đang phát, thêm hàng đợi và khôi phục video dài khi rời Shorts đều đạt. Xem `features-ui-06.json`.
- Fullscreen trên Samsung: player native 2173×1080, video Spring 2173×909 đúng tỷ lệ nội dung; phát tiếp sau xoay, Back về dọc. Xem `fullscreen-qa.json`.
- `flutter analyze`: không có lỗi/cảnh báo.
- Các phép đo debug dùng để xác nhận chức năng, không so trực tiếp với release.

## Sự cố dữ liệu khi test

Hai lần chạy integration đầu dùng mặc định Flutter tự gỡ app sau test, làm mất dữ liệu cục bộ bản cài trước. Không có bản sao lưu để khôi phục. Đã báo người dùng và đổi các lần chạy sau sang `--no-uninstall`. Các kiểm thử tiếp theo không được mặc định gỡ app hoặc xóa dữ liệu.

## Hướng dẫn TV

Cài cùng APK lên TV chạy Android/Google TV hoặc Fire OS có hỗ trợ cài APK. Mở Duchaik từ launcher TV để hiện mã ghép; giữ TV và điện thoại cùng mạng. Điện thoại bấm biểu tượng TV, chọn thiết bị, nhập mã. Nếu không tự tìm thấy, nhập địa chỉ IP:cổng hiển thị trên TV. Mã chỉ dùng để ghép, không phải tài khoản.

Nếu TV không chạy hệ Android, thử chức năng phản chiếu hệ thống nếu cả hai thiết bị hỗ trợ. Tizen, webOS, Roku, tvOS và Vega không thể cài trực tiếp APK này.

## Tài liệu kỹ thuật

- [Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd)
- [Android TV launcher và yêu cầu thiết bị](https://developer.android.com/training/tv/get-started/create)
- [Android RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent)
- Các ràng buộc Cast/Tizen/Fire OS/Vega/Roku/AirPlay và nguồn chính thức có trong `PLAN_0.6.md`.

## APK

- File: `gen/Duchaik-YTB-0.6.0.apk`
- Dung lượng: 73315040 byte.
- SHA-256: `f748511321b96730c2c26b24b6d358bb065bef12705ac6b25b5c358e5bddb6ef`
- Đã xác minh package/version, min SDK 24, target SDK 36, launcher điện thoại/TV và đủ libapp/libflutter/libpython cho ba ABI.

## Receiver và số đo release

- Samsung chạy màn receiver native, client TCP chạy cục bộ trên thiết bị qua ADB/netcat. Kết nối trực tiếp Mac → Samsung cùng dải Wi-Fi báo `No route to host`; chưa xác định được nguyên nhân mạng/OS. Vì vậy không tính là kiểm TV qua LAN giữa hai thiết bị.
- Đã xác nhận từ chối lệnh không token/mã sai; 52 lượt tải/phát xen kẽ hai video Blender công khai; pause/play/seek/1,5×, hẹn ngủ, hàng đợi 30 mục, đảo thứ tự và từ chối revision cũ.
- Trong 50 lượt sau hai lượt chuẩn bị, thời gian native `loadSources` → first frame: p50 **87 ms**, p95 **112 ms**. Đây là hai video đã có cache trong receiver release; không bao gồm thao tác người dùng, lấy nguồn lạnh hoặc mạng giữa điện thoại và TV. Tổng thời gian tính cả driver ADB nằm trong JSON và không đại diện cho thao tác UI thông thường.
- Chưa đủ bộ 30 cold video / nhiều mạng để kết luận p95 cho mọi nội dung. Không dùng số trên để hứa mở mọi video dưới 0,5 giây.
- Artifact: `artifacts/duchaik-0.6/tv-receiver-release.json`.
- Samsung có hai activity nhận giọng nói của Google. Unit test kiểm submit/hủy/lỗi; chưa kiểm độ chính xác nhận lời nói thật.

## Sửa bổ sung khi kiểm release

Bố cục trang xem chuyển sang hai cột cả khi điện thoại rộng từ 600 dp và tỷ lệ rộng/cao trên 1,2; trước đó ngưỡng 800 dp làm video tràn vùng nội dung ở điện thoại nằm ngang. Bản APK bàn giao chứa bản sửa này. Phép đo receiver ở trên dùng cùng mã native trước sửa bố cục Flutter, không phải đo lại toàn bộ APK sau sửa.

Kiểm cuối trên APK bàn giao: video ngang nằm trong `[107,210]–[1335,901]`, thanh điều hướng bắt đầu y=912; tiêu đề/chi tiết còn hiển thị ở cột phải. Đã kiểm hai chạm thực bằng ADB theo bounds accessibility, có phản hồi `+10s` và vị trí thay đổi tương ứng khi video đang phát (`seek-before.png`, `seek-after.png`).

Snapshot sau luồng mở video/tua/xoay: PSS 260.715 KB, 1 Activity; gfxinfo Android 36.077 frame, 27 frame trễ (0,07%). Đây là mẫu tích lũy của cửa sổ Android trong phiên kiểm release, không phải thống kê đầy đủ raster Flutter và không chứng minh không rò bộ nhớ. Các file `meminfo-release-watch.txt`, `gfxinfo-release-watch.txt` lưu số liệu gốc.

Đối chiếu cuối: SHA-256 của APK đã cài trên Samsung trùng file trong `gen`. Đã đưa máy về Trang chủ dọc, dừng phát và trả các thiết lập xoay/giữ màn hình sáng về giá trị trước kiểm thử. Xem `final-device.json`.
