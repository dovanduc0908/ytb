**KẾ HOẠCH ỨNG DỤNG XEM YOUTUBE ĐA NỀN TẢNG — YTB**

**Cập nhật:** Nội dung bên dưới là kế hoạch gốc trước triển khai. App hiện đã có Android 0.5.0, không đăng nhập và chạy độc lập. Kế hoạch nâng cấp mới theo yêu cầu ngày 26/10/2026 nằm tại [đề xuất liên tục, karaoke, hai chạm, Shorts và TV](docs/PLAN_0.6.md); dùng tài liệu mới cho phạm vi nâng cấp tiếp theo.

Ngày lập: 26/10/2026. Trạng thái: kế hoạch trước triển khai; chưa tạo ứng dụng, chưa build APK và chưa cài app lên thiết bị.

**1. Mục tiêu và những điều đã xác nhận**

Người dùng muốn ứng dụng xem YouTube theo trải nghiệm PureTube/YouTube Premium: xem video, tìm kiếm, kênh, thư viện, đăng nhập/đăng xuất, không quảng cáo, tốc độ từ 1× đến 5× với bước 0,25×, chất lượng từ 144p đến 2160p, hẹn giờ ngủ và giao diện dùng được trên nhiều loại màn hình. Người dùng đã xác nhận YouTube là nguồn chính và đã cho phép build/cài/test trực tiếp trên máy đang kết nối. Yêu cầu hiện tại là lập kế hoạch thật chi tiết trước khi triển khai.

Kết quả kiểm tra máy phát triển:

| Hạng mục | Bằng chứng hiện tại | Hệ quả khi triển khai |
| --- | --- | --- |
| Thư mục dự án | `/Users/duchaik/Documents/YTB` ban đầu trống | Khởi tạo dự án mới |
| Máy phát triển | macOS 26.4, kiến trúc arm64 | Dùng làm máy build Android và Apple sau khi đủ công cụ |
| Máy test | Cây USB có thiết bị `SAMSUNG_Android` | Ưu tiên Android thật; chưa xác định model, Android version hay trạng thái cấp quyền ADB |
| Android | Chưa tìm thấy ADB/SDK tại PATH và các đường dẫn thông dụng đã kiểm tra | Cần thiết lập SDK, kiểm tra USB debugging và xác nhận fingerprint trên điện thoại nếu chưa cấp |
| Flutter/Dart | Chưa tìm thấy trong PATH và các vị trí thông dụng đã kiểm tra | Cài phiên bản stable được khóa cho dự án |
| Apple | `xcode-select` đang trỏ tới Command Line Tools; `xcodebuild -version` báo cần Xcode đầy đủ | Chưa thể build iOS/iPadOS/tvOS ngay |
| Node.js | Chưa tìm thấy trong PATH | Thiết lập runtime cho dịch vụ và web khi bắt đầu code |

Không suy diễn rằng USB đã sẵn sàng cho cài app: phải có kết quả `adb devices -l` ở trạng thái `device`. Không cần hỏi lại quyền cài/test bản phát triển vì người dùng đã cho phép; các thao tác Trust/USB debugging do điện thoại yêu cầu vẫn phải thực hiện trên thiết bị.

**2. Phạm vi khả thi và tiêu chuẩn công bố hỗ trợ**

Mục tiêu là bao phủ rộng các thiết bị thực tế. Không thể bảo đảm mọi thiết bị từng tồn tại đều cài được app hoặc đều phát 4K ở 5×. Mỗi bản phát hành phải có bảng gồm: hệ điều hành, model đã test, nguồn video, codec, độ phân giải, tốc độ, âm thanh, PiP và phát nền.

Có ba giới hạn ảnh hưởng trực tiếp tới kiến trúc:

- Trình phát YouTube nhúng chỉ nhận các tốc độ mà video/player hỗ trợ; việc gọi đổi tốc độ không bảo đảm thành công. API hiện được công bố không cung cấp cơ chế ép chất lượng theo danh sách tùy ý của app. Vì vậy không chọn một WebView chứa YouTube làm giải pháp hoàn thành toàn bộ yêu cầu. [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference).
- YouTube API Services không cho phép ứng dụng chặn/sửa quảng cáo của dịch vụ. Hướng dùng nguồn phát không chính thức là một hướng kỹ thuật riêng, có rủi ro thay đổi nguồn, điều khoản và phân phối; việc tách module không làm mất các rủi ro này. Không thể hứa một bản sao đầy đủ của YouTube Premium được hỗ trợ chính thức. [Chính sách nhà phát triển YouTube](https://developers.google.com/youtube/terms/developer-policies-guide).
- Samsung AVPlay công bố các mức tốc độ rời rạc, không phải toàn bộ bước 0,25×; LG công bố native playback không hỗ trợ tốc độ khác 1×. Đây là giới hạn thật của những đường phát này. Cần thử đường phát khác trên model cụ thể; nếu vẫn không đáp ứng thì ghi rõ tính năng chưa đạt trên TV đó. [Samsung AVPlay](https://developer.samsung.com/smarttv/develop/api-references/samsung-product-api-references/avplay-api.html), [LG streaming](https://webostv.developer.lge.com/develop/specifications/streaming-protocol-drm).

Hướng triển khai đề xuất: ứng dụng độc lập với trình phát riêng; nguồn YouTube nằm sau một giao diện có thể thay thế. Kiểm chứng phần lấy nguồn và phát thật trước khi xây giao diện đầy đủ. Bản đầu tập trung video công khai, xem được ở khu vực hiện tại. Video riêng tư, hội viên, DRM, giới hạn tuổi và nội dung bị chặn vùng có trạng thái không hỗ trợ rõ ràng, không được tính là đã xem được chỉ vì lấy được thumbnail.

Yêu cầu không quảng cáo được chia thành tiêu chí đo được:

- App không tích hợp SDK quảng cáo, banner, popup hay màn hình quảng cáo của chính app.
- Luồng phát YouTube thực tế được kiểm tra pre-roll, mid-roll và chuyển video; lưu kết quả theo phiên bản provider, thời điểm và bộ video mẫu.
- Không cam kết vĩnh viễn không có quảng cáo nếu nguồn thay đổi hoặc chèn quảng cáo vào chính luồng nội dung.
- Đoạn tài trợ được người sáng tạo dựng vào video là một loại khác. Tự bỏ qua đoạn này là tính năng tùy chọn về sau, cần dữ liệu mốc thời gian và lựa chọn của người xem.
- Không tự chuyển sang player nhúng có thể phát quảng cáo khi provider lỗi. Hiển thị lỗi và cho người dùng chủ động mở YouTube nếu muốn.

**3. Ma trận nền tảng và thứ tự triển khai**

Các phiên bản tối thiểu dưới đây là mục tiêu dự kiến; chốt lại sau khi nhận dạng Samsung và khóa SDK. Đây chưa phải danh sách thiết bị đã được chứng nhận.

| Thiết bị | Hướng ứng dụng | Mục tiêu ban đầu | Điều kiện quan trọng |
| --- | --- | --- | --- |
| Android điện thoại | Flutter + Media3 | Android 8 trở lên, điều chỉnh theo máy test | 17 tốc độ; chọn track; PiP, nền và timer phải test thật |
| Android tablet/máy gập | Cùng app Android, layout thích ứng | Sau lõi Android | Đổi kích thước cửa sổ, xoay và gập không khởi động lại video |
| Android TV/Google TV | Flutter Android, giao diện remote riêng, Media3 | Sau Android alpha | Launcher TV, D-pad, Back, focus, không phụ thuộc cảm ứng |
| iPhone | Flutter + adapter AVPlayer | iOS 16 trở lên dự kiến | Xcode, signing, thử tốc độ >2× và các tổ hợp codec/stream |
| iPad | Cùng app Apple, layout tablet | Cùng đợt iPhone | Multitasking, PiP và cửa sổ thu nhỏ phải test riêng |
| Web trên máy tính/điện thoại | React/TypeScript + HTML media/MSE | Trình duyệt hiện đại | CORS, autoplay, Safari, codec và giới hạn phát nền |
| Windows/macOS/Linux | Flutter desktop + adapter media_kit | Sau mobile | Build/test trên từng OS; không suy từ macOS sang Windows/Linux |
| Apple TV | Client tvOS riêng dùng SwiftUI/AVPlayer | Giai đoạn mở rộng | Focus remote, signing, HLS/codec, >2× và máy thật |
| Samsung Tizen | Web client dành cho TV + adapter AVPlay/HTML media | Chốt theo model được cung cấp | Bước 0,25× chưa được đường AVPlay đáp ứng |
| LG webOS | Web client dành cho TV + adapter hệ điều hành | Chốt theo model được cung cấp | Đường native đang được tài liệu ghi chỉ hỗ trợ tốc độ 1× |
| TV cũ/thiết bị khác | Web tương thích hoặc thiết bị phát ngoài qua HDMI | Từng trường hợp | Thiết bị không có môi trường cài/chạy app không thể được thêm hỗ trợ chỉ bằng sửa layout |

Flutter có nền tảng triển khai chính thức cho mobile, desktop và web. Các biến thể TV cần SDK/port và đánh giá riêng; không coi chúng là một target đồng nhất. Dự án chọn web client riêng cho Tizen/webOS để kiểm soát khả năng tương thích và điều khiển remote. [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms).

**4. Diễn giải yêu cầu đa màn hình**

Đa màn hình trong bản đầu gồm responsive theo kích thước cửa sổ, dọc/ngang, tablet, máy gập, TV, desktop và Picture-in-Picture khi hệ điều hành hỗ trợ. Chia đôi màn hình với ứng dụng khác là một ca test bắt buộc trên thiết bị có chức năng này.

Đồng bộ vị trí xem giữa hai thiết bị là chức năng của tài khoản. Cast/AirPlay là một giai đoạn bổ sung với receiver riêng. Chạy đồng thời nhiều video trong một cửa sổ và đồng bộ xem cùng lúc giữa nhiều người chưa nằm trong bản đầu; chúng tiêu thụ nhiều decoder và không được suy ra từ yêu cầu responsive.

| Không gian hiển thị | Cấu trúc dự kiến | Kiểm tra bắt buộc |
| --- | --- | --- |
| Nhỏ hơn 600 đơn vị logic | Một cột, điều hướng dưới, player phía trên | Không tràn ngang; nút vẫn bấm được ở cửa sổ 320 rộng |
| Từ 600 đến dưới 840 | Navigation rail; nội dung 1–2 vùng tùy chiều cao | Xoay không mất vị trí xem; chữ lớn không che nút |
| Từ 840 đến dưới 1200 | Player và danh sách liên quan hai vùng | Người dùng thu hẹp cửa sổ không làm video tải lại |
| Từ 1200 trở lên | Sidebar, player lớn, đề xuất/playlist bên cạnh | Cỡ chữ và khoảng trống không kéo giãn vô hạn |
| TV | Chế độ giao diện riêng cho khoảng cách xem xa | Focus rõ; tất cả thao tác dùng được bằng remote |

Breakpoint là giá trị thiết kế ban đầu, dùng kích thước vùng nội dung thực tế, không dùng tên model để quyết định giao diện. TV được chọn theo khả năng thiết bị/input, không chỉ vì chiều rộng lớn. Khu vực chạm tối thiểu dự kiến 48 đơn vị logic; hỗ trợ scale chữ, screen reader, caption, màu tương phản và focus bàn phím.

**5. Kiến trúc đề xuất**

| Lớp | Công nghệ dự kiến | Trách nhiệm |
| --- | --- | --- |
| App native chính | Flutter/Dart | Android, iPhone/iPad, desktop; điều hướng, màn hình và logic dùng chung |
| Web và TV web | React/TypeScript | Web/PWA và giao diện remote cho Tizen/webOS; dùng chung schema/API, không giả định dùng chung widget Flutter |
| Apple TV | SwiftUI | Client mỏng dành riêng cho tvOS, dùng cùng API và quy tắc dữ liệu |
| Trình phát Android | Media3/ExoPlayer qua plugin | Audio/video, track, tốc độ, audio focus, media session, dịch vụ nền |
| Trình phát Apple | AVPlayer qua plugin | HLS/MP4 tương thích, audio session, PiP, điều khiển màn hình khóa |
| Trình phát desktop | media_kit/libmpv qua adapter | Track, codec, tốc độ và cửa sổ desktop; xác minh license gói binary trước phân phối |
| Trình phát web | HTMLVideoElement; thư viện HLS/DASH phù hợp sau spike | Playback thực tế theo browser và codec, không suy hỗ trợ từ giao diện |
| API riêng | Node.js/TypeScript + Fastify | Hồ sơ, thư viện, sync, ghép thiết bị, proxy API nguồn có giới hạn |
| Nguồn YouTube | Provider adapter, thử YouTube.js trước | Tìm kiếm, metadata, kênh, pagination và nguồn phát công khai |
| Dữ liệu local | SQLite trên native; IndexedDB trên web | Lịch sử, playlist, settings, hàng đợi sync |
| Dữ liệu server | PostgreSQL | Tài khoản, dữ liệu thư viện riêng và phiên thiết bị |
| Đăng nhập | OIDC/OAuth qua nhà cung cấp có sẵn | Google sign-in hoặc email; không tự xây hệ thống mật khẩu |

YouTube.js là thư viện cho API nội bộ không chính thức và có thể dùng trong runtime JavaScript. Đây là ứng viên thử nghiệm, chưa phải lời xác nhận rằng nó hiện lấy được mọi nguồn cần dùng. Nếu thất bại, so sánh với yt-dlp/NewPipeExtractor trên cùng bộ mẫu và ghi quyết định. NewPipeExtractor dùng GPL-3.0; việc nhúng nó vào bản phân phối cần xem nghĩa vụ license trước khi chọn. [YouTube.js](https://github.com/LuanRT/YouTube.js), [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor).

Không đóng gói nhiều extractor để tự retry vô hạn. Ban đầu chỉ một provider được bật; adapter giúp thay phiên bản hoặc triển khai khác khi có bằng chứng cần đổi. API nội bộ của YouTube có thể cần token, thay đổi format hoặc từ chối request; tài liệu extractor cũng ghi nhận vấn đề này. [yt-dlp extractor notes](https://github.com/yt-dlp/yt-dlp/wiki/Extractors).

Cấu trúc thư mục dự kiến:

```text
apps/
  native/                 Flutter: Android, Apple mobile, desktop
  web/                    Web/PWA và shell cho TV web
  apple_tv/               tvOS
packages/
  domain/                 Model và quy tắc Dart dùng chung trong native
  design_system/          Widget, theme, spacing và typography Flutter
  player_platform/        Contract trình phát và các plugin native
  contracts/              OpenAPI/JSON Schema; sinh client Dart/TS/Swift
services/
  api/                    Tài khoản, thư viện, sync và ghép thiết bị
  source_provider/        Metadata và nguồn YouTube, tách process khi cần
  media_gateway/          Chỉ thêm nếu spike chứng minh cần relay/remux
infra/                    Cấu hình dev và triển khai
scripts/                  Doctor, build, cài Android, thu log
tests/                    Contract, integration, playback và dữ liệu mẫu
docs/                     Quyết định kiến trúc, ma trận hỗ trợ, báo cáo QA
artifacts/                APK, ảnh màn hình và báo cáo theo build
```

Không tạo toàn bộ cây rỗng ngay từ đầu. Chỉ tạo các module khi bắt đầu mốc tương ứng; giữ hợp đồng dữ liệu đủ rõ để mở rộng.

**6. Luồng lấy nguồn và phát video**

1. Nhận video ID từ card, liên kết chia sẻ hoặc tìm kiếm; chuẩn hóa URL và xác thực host/ID.
2. Provider lấy metadata và các track video/audio có thể truy cập; gắn thời điểm hết hạn, header cần thiết, codec, bitrate, fps và loại luồng.
3. Thiết bị gửi năng lực player/decoder; bộ chọn nguồn ưu tiên codec phát được và không yêu cầu xử lý vượt khả năng máy.
4. Tạo `PlaybackDescriptor`: đường phát trực tiếp hoặc manifest; track audio/subtitle; URL dự phòng có kiểm soát; capabilities và thời hạn.
5. Player chuẩn bị audio/video; xác nhận đã phát khung hình và có âm thanh trước khi báo thành công.
6. Khi 403/hết hạn, xin nguồn mới một lần rồi resume từ vị trí đã lưu; không lặp request gây quá tải. Tách lỗi hết hạn khỏi private, vùng, giới hạn tốc độ và decoder.
7. App chỉ hiển thị tốc độ/chất lượng đã được nguồn và player hỗ trợ; trạng thái chọn phải khớp trạng thái player xác nhận.

Các nút thắt phải giải quyết ở spike, không để tới cuối dự án:

- Video chất lượng cao có thể tách audio/video. Android và desktop cần ghép track đồng bộ; nguồn có hình mà mất tiếng không được tính là thành công.
- AVPlayer cần đường HLS/MP4 với codec tương thích. Không giả định một DASH manifest phát trên Android cũng dùng nguyên vẹn được trên iPhone/tvOS.
- Các nguồn 4K phải kiểm tra codec cụ thể; số 2160 trong metadata không chứng minh iPhone hoặc TV giải mã được.
- URL lấy trên server có thể phụ thuộc IP/session/header. Phải test server và điện thoại ở hai mạng khác nhau, không chỉ `adb reverse`.
- Web cần kiểm tra CORS, range request, MIME, cookie/header và chính sách autoplay. Đưa URL phát vào một thẻ video chưa đủ chứng minh web hoạt động.
- Nếu cần media gateway để relay/remux HLS, phải đo băng thông, thời gian bắt đầu, seek và tải server. Chỉ remux khi codec tương thích; transcode là công việc khác và có chi phí cao hơn.
- Chốt một trong ba cách sau spike: phát trực tiếp; lấy nguồn tại thiết bị phù hợp; hoặc gateway có ngân sách rõ ràng. Không triển khai dịch vụ relay công khai mặc định.

**7. Đặc tả trình phát**

| Nhóm | Hành vi cần làm | Điều kiện nghiệm thu |
| --- | --- | --- |
| Phát cơ bản | Play/pause, seek, toàn màn hình, tiếp tục xem | Vị trí và âm thanh đúng, không phát hai player cùng lúc |
| Tốc độ | 17 mức từ 1× tới 5× | Player thực sự đổi tốc độ, không chỉ thay text |
| Chất lượng | Auto và các mức nguồn có thật | Độ phân giải decoder khớp lựa chọn khi ổn định |
| Tua | Hai lần chạm ±10 giây; kéo timeline; phím/remote | Clamp đầu/cuối, seek không vượt cửa sổ live |
| Âm thanh | Volume, audio focus, pitch phù hợp, tai nghe/Bluetooth | Không mất tiếng sau đổi tốc độ/chất lượng, không chồng âm |
| Phụ đề | Chọn ngôn ngữ, cỡ chữ, bật/tắt | Theo timestamp nội dung khi tua và tăng tốc |
| Hàng đợi | Play next, thêm queue, xóa/đổi thứ tự, autoplay | Timer hết hạn luôn thắng autoplay |
| Nền và PiP | Tách player khỏi màn hình UI | Home/xoay/PiP không tạo phiên phát mới |

Danh sách tốc độ chính xác:

`1.00, 1.25, 1.50, 1.75, 2.00, 2.25, 2.50, 2.75, 3.00, 3.25, 3.50, 3.75, 4.00, 4.25, 4.50, 4.75, 5.00`.

Lưu tốc độ mặc định và tốc độ phiên hiện tại; đổi video có thể giữ tốc độ theo cài đặt. Khi đang phát ổn định, đo chênh lệch thời gian nội dung/thời gian thực để kiểm chứng. Thử tiếng nói và nhạc để phát hiện mất tiếng, đổi cao độ hoặc lệch A/V ở tốc độ cao. Không dùng repeated-seek hoặc chỉ số rate trên UI để kết luận đã có phát liên tục 5×.

Media3 có API đổi tốc độ; AVPlayer có cờ khả năng fast-forward theo từng item và Apple cảnh báo tốc độ >2× có thể giảm độ mượt. Vì vậy khả năng 5× có tiếng trên Apple phải là một kết quả thử nghiệm riêng. Nếu đường AVPlayer không đạt, đánh giá adapter player khác về codec, pin, PiP và license trước khi đổi. [Media3 Player](https://developer.android.com/reference/androidx/media3/common/Player), [Apple fast playback](https://developer.apple.com/library/archive/qa/qa1772/_index.html).

Danh sách chất lượng mục tiêu: `Auto, 144p, 240p, 360p, 480p, 720p, 1080p, 1440p, 2160p`. Chỉ hiển thị những track tồn tại và dùng được. Gắn thêm 30/60fps hoặc HDR khi cần phân biệt. Không nâng video 720p thành nhãn 4K.

Auto cân bằng băng thông, decoder, tốc độ phát và cài đặt tiết kiệm dữ liệu. Chế độ chọn cứng giữ chất lượng đã chọn; nếu không phát nổi thì giải thích và mời đổi, không lặng lẽ báo 2160p trong khi phát 480p. Đổi chất lượng giữ vị trí, trạng thái pause, tốc độ, audio track, phụ đề và sleep timer.

4K và 5× phải test độc lập rồi test kết hợp trên máy phù hợp. Ví dụ minh họa: nguồn trung bình 20 Mb/s phát 5× có thể cần khoảng 100 Mb/s để theo kịp nội dung, chưa tính overhead; đây là tính toán tải, không phải cấu hình băng thông cố định của mọi video. Máy không đủ năng lực phải báo giới hạn thật.

Live có quy tắc riêng: tốc độ >1 chỉ có ý nghĩa khi đang xem chậm hơn điểm trực tiếp và nguồn cho phép; khi bắt kịp live edge phải trở về tốc độ phù hợp. Luồng live không có DVR không cung cấp tua tùy ý.

**8. Hẹn giờ ngủ và vòng đời phát**

Các chế độ: sau 15/30/45/60/90 phút, số phút tùy chỉnh, tới giờ cụ thể theo giờ địa phương, hoặc hết video hiện tại. Có gia hạn, hủy, hiển thị thời gian còn lại và tùy chọn nhỏ dần âm lượng vài giây cuối.

- Đếm thời gian thực: hẹn 30 phút thì dừng sau 30 phút ngoài đời ở cả 1× và 5×. Mặc định thời gian vẫn trôi khi pause hoặc buffering; ghi rõ trong UI.
- Đồng hồ đếm tương đối dùng nguồn thời gian monotonic khi tiến trình sống; lưu deadline và chính sách phục hồi để kiểm tra sau resume/restart. Hẹn giờ cụ thể xử lý múi giờ/đổi ngày và hiển thị thời điểm sẽ dừng.
- Bộ điều khiển timer ở cạnh phiên phát native, không chỉ nằm trong widget Flutter hoặc `setTimeout` của trang web.
- Android gắn với media service; Apple gắn với audio/playback lifecycle. Phải test khóa màn hình, PiP, bỏ nền, tiết kiệm pin và ngắt tai nghe.
- Hết timer: ngăn autoplay, pause player/receiver, lưu tiến độ, bỏ quyền giữ màn hình sáng và giải phóng tài nguyên không cần thiết.
- Khởi động app sau deadline: không tự phát lại. Tiến trình bị hệ điều hành kill thì không hứa JavaScript/Dart vẫn được chạy; chính sách phục hồi bảo đảm không tiếp tục sai khi mở lại.
- Web/TV phải thử khả năng thực thi khi bị suspend. Nếu không bảo đảm đúng giờ thì tính năng phải báo giới hạn trên nền tảng đó, không được công bố ngang bản native đã kiểm chứng.
- Sleep timer dừng phát; nó không có nghĩa app có quyền tắt nguồn điện thoại hay TV.

Android dùng MediaSessionService để player tiếp tục tồn tại ngoài Activity và tương tác với điều khiển hệ thống. [Android background playback](https://developer.android.com/media/media3/session/background-playback).

**9. Màn hình và hành vi người dùng**

| Màn hình | Nội dung và hành động chính | Trạng thái cần có |
| --- | --- | --- |
| Trang chủ | Tiếp tục xem, kênh theo dõi, nội dung khám phá | Chưa có lịch sử, mất mạng, provider lỗi, tải thêm |
| Tìm kiếm | Video/kênh/playlist; lịch sử tìm; bộ lọc khả dụng | Gõ có debounce, hủy kết quả cũ, không kết quả, phân trang |
| Xem video | Player, tiêu đề, kênh, mô tả, queue, đề xuất | Loading, playing, paused, buffering, ended, unavailable, failed |
| Kênh | Thông tin kênh, video, playlist, theo dõi | Kênh không tồn tại, pagination, lỗi một tab |
| Playlist | Danh sách, phát toàn bộ, thêm queue | Video đã xóa/private, playlist rỗng, thứ tự thay đổi |
| Thư viện | Lịch sử, xem sau của app, playlist cá nhân | Guest, đã đăng nhập, đang sync, offline |
| Tài khoản | Google sign-in, phiên thiết bị, đăng xuất | Đang xác thực, người dùng hủy, token hết hạn, đổi tài khoản |
| Cài đặt | Speed/quality mặc định, autoplay, timer, theme, dữ liệu | Lưu local, sync setting, reset từng nhóm |
| Ghép TV | QR/mã, trạng thái chờ, thiết bị được liên kết | Mã hết hạn, hủy, đã xác nhận, thu hồi |

Ngôn ngữ mặc định tiếng Việt, theme tối cho trải nghiệm xem video; hỗ trợ theme sáng/hệ thống. Tên sản phẩm tạm là YTB, không giả định quyền dùng tên/logo YouTube hoặc PureTube. Nhận liên kết `youtube.com`, `youtu.be`, playlist, Shorts và timestamp khi nguồn hỗ trợ. Shorts ban đầu mở trong cùng player dọc; feed vuốt liên tục triển khai sau lõi xem ổn định.

Feed của app gồm nội dung công khai và thư viện do app quản lý; không tuyên bố tái tạo thuật toán cá nhân hóa YouTube. Bình luận chỉ đọc có thể thêm khi provider đạt độ ổn định; viết bình luận, like, subscribe lên tài khoản YouTube phải được xử lý như thao tác tài khoản riêng, không giả lập bằng nút lưu local.

**10. Đăng nhập, đăng xuất và đồng bộ**

Mặc định thiết kế Google sign-in để người dùng dùng tài khoản quen thuộc; guest vẫn tìm và xem video công khai. Email là phương án bổ sung nếu cần. Dùng nhà cung cấp xác thực có sẵn theo OIDC; thử local trước, cấu hình môi trường thật khi có project/client ID. Giao diện đăng nhập mẫu không được tính là hoàn thành đăng nhập thật.

Tách hai loại kết nối trong UI và dữ liệu:

| Chức năng | Ý nghĩa | Phạm vi cam kết |
| --- | --- | --- |
| Đăng nhập Google vào YTB | Xác định người dùng của app và đồng bộ dữ liệu YTB | Là tính năng bắt buộc; cần cấu hình OAuth thật để nghiệm thu |
| Kết nối dữ liệu YouTube | Đọc/ghi các mục YouTube theo quyền được cấp | Chỉ đánh dấu hỗ trợ sau khi kiểm chứng endpoint, scope, quota và tính phù hợp với hướng app |
| Lịch sử, xem sau trong YTB | Dữ liệu người dùng tạo khi dùng YTB | Đồng bộ qua server của app; phải có tên/nhãn rõ ràng |
| YouTube Premium | Quyền lợi của tài khoản trên dịch vụ YouTube | Google login vào YTB không tự tạo hay thay thế quyền Premium |

API YouTube đã ngừng hỗ trợ lấy watch history/watch later theo cách trước đây. Không hứa nhập hoặc ghi đồng bộ toàn bộ hai danh sách này qua API chính thức. Kênh đã đăng ký và playlist thông thường cần một spike riêng cho những quyền hiện được hỗ trợ. Nếu phần liên kết không triển khai được, phải công bố là chưa hỗ trợ, không thay nó âm thầm bằng dữ liệu app. [YouTube Data API revision history](https://developers.google.com/youtube/data/revision_history).

Thiết kế phiên đăng nhập:

- Dùng trình duyệt hệ thống/native sign-in và PKCE khi flow yêu cầu; không xây form thu mật khẩu Google. Mobile/desktop không giữ client secret của server. [Google OAuth for installed apps](https://developers.google.com/identity/protocols/oauth2/native-app).
- Token được lưu trong Keystore/Keychain hoặc session cookie HttpOnly phù hợp với web. API không ghi token, cookie hay URL stream có chữ ký vào log.
- Resolver video công khai không nhận token Google của người dùng. Phiên app, quyền YouTube và trạng thái player là ba đối tượng độc lập.
- TV dùng QR/mã ghép của ứng dụng: điện thoại đã đăng nhập phê duyệt một phiên TV, mã một lần có thời hạn và giới hạn thử. Không bắt gõ mật khẩu bằng remote và không giả định Google device flow dùng được cho mọi scope.
- Đăng xuất máy hiện tại: hủy phiên, xóa token, ngừng sync, hủy request cũ và đóng dữ liệu riêng của tài khoản. Đăng nhập tài khoản khác không nhìn thấy cache của người trước.
- Có thao tác thu hồi các thiết bị khác và xóa dữ liệu tài khoản. Lịch sử guest chỉ gộp vào tài khoản khi người dùng chủ động chọn.
- Đăng xuất Google ở app không được mô tả là đăng xuất toàn bộ Google trên thiết bị.

**11. Dữ liệu, API và đồng bộ nhiều máy**

Các đối tượng chính:

| Đối tượng | Trường/hành vi quan trọng |
| --- | --- |
| User | ID nội bộ, tên hiển thị, provider đăng nhập |
| DeviceSession | Device ID ngẫu nhiên, tên thiết bị, phiên, hạn/thu hồi |
| VideoRef | Provider, video ID, metadata cache có hạn; không chứa URL phát lâu dài |
| PlaybackDescriptor | URL/manifest ngắn hạn, track, headers cần thiết, expiry, kiểu truyền |
| PlaybackCapabilities | Mức tốc độ đã hỗ trợ, quality/codec/fps, PiP, background, seek/live window |
| PlaybackProgress | User, video, vị trí, duration, session, sequence, thời điểm server |
| Playlist/PlaylistItem | Chủ sở hữu, source, vị trí mục, revision, trạng thái xóa |
| FollowedChannel | Theo dõi trong app hoặc kết nối YouTube, ghi rõ nguồn |
| UserSettings | Tốc độ, quality theo loại mạng, theme, autoplay, caption |
| SleepTimer | Deadline/mode, phiên player, hành vi sau restart; mặc định riêng từng thiết bị |

API dự kiến: tìm kiếm, thông tin video/kênh/playlist, `POST /playback/resolve`, lấy/cập nhật thư viện, đồng bộ tiến độ, settings, tạo/xác nhận mã ghép và thu hồi phiên. Dùng schema có version; app cũ nhận lỗi tương thích rõ khi contract thay đổi.

Quy tắc dữ liệu:

- Xem lại dữ liệu thư viện đã cache được khi offline; phát video vẫn cần nguồn khả dụng. Offline library không đồng nghĩa tải video offline.
- Ghi tiến độ theo nhịp khoảng 15 giây và khi pause/background/end; giới hạn tần suất để không gửi một request mỗi frame.
- Đồng bộ dựa vào phiên, sequence và revision server; không lấy vị trí lớn nhất vì người xem có thể tua lại có chủ ý. Phiên xem mới hơn không bị request cũ đến trễ ghi đè.
- Xóa playlist/mục có tombstone hoặc revision để máy offline không làm nội dung đã xóa xuất hiện lại.
- Hàng đợi sync gắn user và phiên. Khi logout, request bị treo không được ghi vào tài khoản kế tiếp.
- URL phát chỉ sống theo expiry; không lưu nó như URL vĩnh viễn trong playlist. Mở lại video phải resolve nguồn mới khi cần.
- Relay, nếu có, chỉ nhận nguồn đã được resolver xác thực; không tạo một endpoint proxy tùy ý ra mạng. Có giới hạn kích thước/rate, timeout và giới hạn chuyển hướng.

**12. Các mốc triển khai, đầu ra và điều kiện qua mốc**

| Mốc | Công việc cụ thể | Đầu ra có thể kiểm tra | Điều kiện qua mốc |
| --- | --- | --- | --- |
| M0 — Môi trường | Khởi tạo Git; khóa SDK; Android SDK/JDK/Flutter; nhận dạng Samsung; cấu hình log; thiết lập Node | Báo cáo doctor, model/OS/ABI, app khung cài được | ADB authorized; build và khởi chạy app trên Samsung; không có lỗi startup |
| M1 — Nguồn và player thử nghiệm | Provider công khai; audio/video tách; 17 tốc độ; các track chất lượng; hết hạn nguồn; khác IP; thử nền/timer tối thiểu | APK thử phát YouTube thật và bảng đo; quyết định direct/relay; danh sách thất bại | Android phát có tiếng, source hợp lệ; xác định mức đạt/chưa đạt; chưa mở rộng UI nếu nguồn còn không ổn định |
| M2 — Nền ứng dụng | Router, state machine, theme, responsive, local DB, error model và contract API | App khung có điều hướng và dữ liệu thật tối thiểu | Navigation, back, resize không làm mất phiên player; có migration DB |
| M3 — Trình phát Android hoàn chỉnh | Speed/quality, seek, queue, subtitles, sleep timer, MediaSession, PiP, lockscreen và audio focus | APK dùng được hằng ngày cho luồng xem cơ bản | Các yêu cầu player cốt lõi qua test thiết bị thật; hạn chế 4K×5 được ghi bằng số liệu |
| M4 — Trải nghiệm xem | Home, search, channel, playlist, link sharing, lịch sử, xem sau, pagination | Android alpha đầy đủ luồng tìm → xem → lưu → xem lại | Không còn dữ liệu giả trong luồng nghiệm thu; lỗi mạng và provider có UI rõ |
| M5 — Tài khoản và sync | OIDC/Google thật, backend DB, thư viện nhiều máy, logout/revoke, QR pairing; spike YouTube library | Bản có tài khoản thật và đồng bộ ít nhất hai client | Đổi tài khoản không lẫn dữ liệu; hủy/token hết hạn/logout được xử lý; phạm vi YouTube sync được công bố |
| M6 — Android đa màn hình/TV | Tablet, máy gập, multiwindow, remote, TV manifest và focus | APK tablet/TV và báo cáo remote | Hoàn tất luồng chính bằng D-pad; resize/xoay không khởi tạo lại player; test ít nhất một TV/box thật khi có |
| M7 — iPhone/iPad | Xcode/signing; player Apple; nguồn tương thích; audio session/PiP/nền; tablet layout | Bản ký cài lên iPhone/iPad và báo cáo codec/speed | 5× có tiếng phải được chứng minh hoặc ghi rõ chưa đạt; không kết luận bằng simulator đơn thuần |
| M8 — Web và desktop | Browser player; CORS; PWA; desktop adapters; keyboard; CI theo OS | Web build và bộ cài desktop tương ứng | Smoke test thực tế Chrome/Safari và OS công bố hỗ trợ; nguồn không phụ thuộc USB/LAN dev |
| M9 — TV mở rộng | tvOS, Tizen, webOS theo model; QR; player native/HTML; capability và retry | Gói cài TV và bảng tính năng riêng từng dòng | Có bằng chứng remote/playback trên máy thật; không gắn nhãn 17 tốc độ nếu player không đáp ứng |
| M10 — Ổn định và bàn giao | Soak test, pin/nhiệt, nâng cấp DB, bảo vệ token, ký release, báo cáo lỗi, tài liệu build | Mã nguồn, artifact, checksum, changelog, hướng dẫn và ma trận hỗ trợ | Không còn lỗi chặn luồng chính trên các target đã cam kết; build tái lập từ phiên bản SDK khóa |

M1 là điểm quyết định kiến trúc. Nếu YouTube không cung cấp ổn định nguồn cần thiết, phải báo kết quả thử, nguyên nhân và hướng đổi trước khi tiếp tục xây trải nghiệm đầy đủ. Một demo chạy video mẫu không thay thế bằng chứng YouTube thật.

Spike Apple và TV nên bắt đầu sớm ngay khi có công cụ/thiết bị, dù hoàn thiện giao diện các nền tảng đó ở mốc sau. Những giới hạn đã thấy trong tài liệu TV phải được phản ánh từ M1. Phần tài khoản có thể chuẩn bị contract trong khi M3/M4 tiến triển; không cần giả định đã có mọi cloud credential.

**13. Chi tiết vòng build và test trên Samsung đang cắm**

1. Kiểm tra `adb devices -l`; xác định chính xác serial nội bộ, model, Android SDK, ABI, RAM và màn hình. Nếu nhiều máy, mọi lệnh sau đều chỉ định serial.
2. Nếu máy báo unauthorized, hướng dẫn người dùng chạm cho phép RSA/USB debugging. Không coi hub USB đã nhận máy là đủ.
3. Tạo application ID bản dev riêng, ký debug nhất quán. Cài cập nhật giữ dữ liệu dev; không gỡ ứng dụng khác hay xóa dữ liệu điện thoại.
4. Build debug để kiểm tra chức năng; cài bằng `adb -s <serial> install -r <apk>`; launch đúng Activity; xác nhận app foreground và không crash.
5. Backend dev kết nối bằng `adb reverse` hoặc địa chỉ LAN được cấu hình. Ghi rõ đây là cấu hình dev; khi rút cáp/đổi mạng phải test lại với endpoint dùng thực tế.
6. Test luồng video, các menu và hẹn giờ trên máy. Thu UI hierarchy/screenshot, logcat theo process và trạng thái media để đối chiếu hành vi.
7. Dùng profile/release để đo start, buffering, dropped frames, CPU, bộ nhớ, nhiệt và pin; không dùng số đo debug làm kết luận hiệu năng sản phẩm.
8. Sửa lỗi theo bằng chứng, build/cài lại và chạy lại các ca liên quan. Lỗi timer/đổi quality cần chạy regression ở những lifecycle liên quan.
9. Lưu APK và báo cáo theo build/commit; ghi model, OS, mạng, video/track, source provider, thời điểm test và kết quả. Không lưu token hay dữ liệu tài khoản vào báo cáo.
10. Để lại bản hoạt động mới nhất trên máy đã cho phép; bàn giao đường dẫn APK và những tính năng thực sự đã kiểm chứng.

Trên iPhone/iPad/tvOS cần Xcode đầy đủ, SDK phù hợp, signing/provisioning, Trust/Developer Mode khi áp dụng. Các bước yêu cầu tương tác tài khoản/thiết bị phải được thông báo đúng lúc; không thể suy ra từ việc Android cắm USB. Windows/Linux có runner hoặc máy build riêng. TV Tizen/webOS cần developer mode, công cụ ký/đóng gói và model cụ thể.

**14. Bộ kiểm thử và tiêu chí nghiệm thu**

Bộ video gồm hai nhóm: file/stream kiểm soát được dùng để tách lỗi player, và khoảng 20 video YouTube công khai đại diện cho video ngắn/dài, có phụ đề, 30/60fps, audio/video tách và 4K khi có. Live/DVR có nhóm riêng. Private, video đã xóa và chặn vùng là ca xác nhận thông báo lỗi đúng, không phải tiêu chí phát thành công. Ghi tỷ lệ thành công theo nhóm và danh sách lỗi, không chọn một video duy nhất rồi tuyên bố nguồn ổn định.

| Nhóm test | Cách kiểm tra | Tiêu chí dự kiến |
| --- | --- | --- |
| Không quảng cáo trong app | Kiểm tra dependency/network và toàn bộ luồng sử dụng | Không có SDK/banner/interstitial của app |
| Quảng cáo từ nguồn | Xem bộ YouTube ở đầu, giữa, đổi video và phiên mới | Báo cáo quan sát không quảng cáo trên mẫu đã test, ghi rõ phạm vi/thời điểm |
| 17 tốc độ | Test từng mức ở 480/720/1080p và nguồn kiểm soát | Đo tiến độ nội dung theo thời gian thực sau buffering; sai lệch mục tiêu ≤5%; có tiếng |
| 4K/tốc độ cao | Test 2160p ở 1× trước rồi tăng dần trên máy đủ năng lực | Báo rate thực, dropped frames, A/V và decoder; 4K×5 không suy từ hai test độc lập |
| Chất lượng | Lần lượt các mức có thật; đổi Auto/manual qua lại | Decoder khớp track; giữ vị trí/speed/pause; không có nhãn chất lượng giả |
| Timer | 1 phút test nhanh và 30–60 phút thật; khóa màn hình/PiP/nền | Mục tiêu dừng trong ±2 giây trên native khi OS vẫn cho phiên media hoạt động; không tự next |
| Phiên phát | Đổi quality/speed/tua 50 lần; đổi video nhanh | Không crash, không hai audio session, không tích lũy player |
| Responsive | 320/360/600/840/1024/1440 rộng; dọc/ngang; chữ lớn | Không overflow, không che nút thiết yếu; giữ vị trí phát |
| TV remote | Chỉ dùng D-pad, OK, Back và phím media | Vào/thoát mọi menu, focus nhìn rõ và được khôi phục |
| Nền và âm thanh | Home, lock, notification, gọi điện, rút tai nghe, Bluetooth | Audio focus đúng; không tự phát lại ngoài lựa chọn người dùng |
| Mạng | Offline, mạng chậm, timeout, Wi-Fi → di động, nguồn 403 | Lỗi rõ, retry có giới hạn, resume khi phù hợp; không treo vô hạn |
| Đăng nhập | Thành công, hủy, token hết hạn, logout, tài khoản A → B | Phiên thật; không lộ dữ liệu chéo; revoke được thiết bị |
| Sync | Hai client xem/tua khác nhau; offline rồi online | Thao tác mới không bị request cũ ghi đè; xóa không hồi sinh |
| Nâng cấp | Cài bản mới đè bản cũ có dữ liệu | Lịch sử/settings giữ đúng, migration thành công |
| Phát dài | Tối thiểu 2 giờ trên máy chủ lực | Không crash/ANR; theo dõi bộ nhớ, nhiệt và mức tiêu thụ pin |

Ngưỡng hiệu năng ban đầu, phải đo rồi điều chỉnh theo máy/mạng: bắt đầu phát p95 dưới 5 giây ở 1080p trên mạng ổn định đủ băng thông; chuyển menu phản hồi nhanh, không làm main thread đứng; seek/đổi chất lượng mục tiêu resume trong vài giây khi nguồn cho phép. Tách thời gian resolver, tải mạng và decoder để biết nơi cần sửa. Đây là mục tiêu kỹ thuật, chưa phải kết quả đã đạt.

Kiểm thử tự động tập trung vào logic dễ sai: state machine, timer, chọn track/capability, URL hết hạn, pagination, chống response cũ, đồng bộ và tách tài khoản. Test contract provider dùng fixture đã loại dữ liệu nhạy cảm; live smoke test hữu hạn xác nhận nguồn thật. Không viết hàng loạt test chỉ để đếm widget hoặc sao chép đúng code implementation.

**15. Phát hành, vận hành và chi phí**

Lộ trình phân phối: APK cài trực tiếp cho Android trước; Apple qua build ký hợp lệ/TestFlight khi đủ điều kiện; web và desktop có artifact riêng; TV theo gói của hệ điều hành. Đưa lên store là công việc riêng với yêu cầu xét duyệt hiện hành. Chạy được nội bộ không đồng nghĩa chắc chắn được duyệt công khai.

Phân tách dev/staging/release; cấu hình endpoint và signing rõ ràng; bí mật nằm ngoài repo. Lưu phiên bản extractor, schema và SDK theo build. Khi YouTube thay đổi, cập nhật provider có regression test và đường rollback. Không tải và chạy mã thực thi tùy ý trên client để vá nóng.

Hạ tầng gồm API/DB cho sync, resolver và có thể thêm relay/remux. Nếu dữ liệu video đi trực tiếp đến thiết bị, server chủ yếu chịu metadata. Nếu relay video, egress tăng mạnh và phải có quota. Ví dụ nguồn trung bình 20 Mb/s tương đương khoảng 9 GB cho mỗi giờ nội dung; xem ở 5× tiêu thụ nội dung nhanh hơn, có thể khoảng 45 GB cho mỗi giờ thời gian thực. Đây là phép tính minh họa, chưa phải báo giá hoặc bitrate mặc định.

Chỉ lập ngân sách tiền cụ thể sau khi đo gateway có cần không, người dùng đồng thời, thời gian xem, chất lượng và chọn nhà cung cấp. Không giả định server miễn phí vận hành 4K vô hạn. Giai đoạn thử dùng local; việc có endpoint hoạt động khi rút cáp là điều kiện riêng trước bàn giao bản dùng độc lập.

**16. Ước lượng công sức và thứ tự ưu tiên**

Các con số là ước lượng cho một người phát triển có kinh nghiệm, làm tập trung, đủ tài khoản và thiết bị; không phải cam kết lịch. Việc sửa nguồn YouTube, tích hợp codec hoặc thiếu thiết bị có thể làm tăng thời gian.

| Nhóm việc | Khoảng công sức dự kiến |
| --- | --- |
| Thiết lập môi trường và spike nguồn/player | 3–7 ngày làm việc |
| Android core player, giao diện, lịch sử và timer | 8–15 ngày |
| Đăng nhập thật, backend sync, pairing và kiểm thử tài khoản | 5–10 ngày |
| Tablet/máy gập và Android TV | 3–6 ngày |
| iPhone/iPad và xử lý nguồn/codec Apple | 5–10 ngày |
| Web và Windows/macOS/Linux | 5–10 ngày |
| tvOS, Tizen và webOS theo model | 8–15 ngày; kết quả 17 tốc độ có thể không đạt ở một số TV |
| Hardening, tài liệu, signing và bộ regression | 3–6 ngày |

Tổng khoảng 40–79 ngày làm việc trước dự phòng; kế hoạch ngân sách thực tế nên tính khoảng 12–20 tuần nếu muốn đi qua toàn bộ nhóm nền tảng và thiết bị. Bản thử YouTube trên Samsung là đầu ra sớm ở M1, không chờ đủ mọi nền tảng. Không đặt thời hạn chắc chắn cho phần nguồn/codec chưa qua spike.

Thứ tự yêu cầu:

- P0: YouTube thật, không quảng cáo do app thêm, player có tiếng, 17 tốc độ trên thiết bị đích đầu tiên, chất lượng đúng, sleep timer, signin/signout thật, responsive và test Samsung.
- P1: Tablet/Android TV, PiP/nền, phụ đề, queue, iPhone/iPad, sync và hoàn thiện phát độc lập khỏi máy dev.
- P2: Web/desktop và TV mở rộng; các target này vẫn thuộc lộ trình đa nền tảng, chưa được gọi là hoàn thành khi chỉ có APK Android.
- P3: Cast/AirPlay receiver, nhập playlist/kênh khi khả dụng, bỏ qua sponsor tùy chọn, tính năng cộng đồng nâng cao.

P0 yêu cầu 17 tốc độ đầy đủ trên target đầu tiên; TV không có khả năng này phải được báo là hạn chế của target, không coi menu 5× là đã đáp ứng. Nếu người dùng yêu cầu đủ 17 tốc độ ngay trên mọi TV, đó là điều kiện có thể không khả thi với các đường phát đã xác minh; thử player khác hoặc receiver Android bên ngoài là một quyết định sản phẩm riêng, không âm thầm thay yêu cầu.

**17. Điều kiện cần từ môi trường và bộ bàn giao**

Có thể tiến hành phần Android theo quyền build/cài/test đã được cấp. Chỉ cần tương tác người dùng khi thiết bị đòi cho phép debug, khi cần đăng nhập OAuth thật hoặc khi cần thông tin chưa thể tự đọc: Apple signing và model TV/thiết bị bổ sung. Không yêu cầu các thông tin này trước khi có phần việc cụ thể cần chúng.

Mỗi mốc bàn giao gồm mã nguồn, hướng dẫn chạy, APK/gói cài tương ứng, commit/build ID, checklist đã chạy với kết quả, ảnh minh chứng cần thiết, lỗi còn tồn tại và ma trận hỗ trợ. Bộ bàn giao cuối bổ sung script build/test, hướng dẫn cấu hình tài khoản/endpoint, license dependency, cách cập nhật provider và khôi phục phiên bản trước.

Bước triển khai đầu tiên sau kế hoạch là M0 rồi M1: nhận dạng Samsung bằng ADB, cài app khung, phát YouTube công khai thật và đo tốc độ/chất lượng/âm thanh. Chỉ sau khi có bằng chứng nguồn phát phù hợp mới đầu tư hoàn thiện toàn bộ màn hình và mở rộng nền tảng.


## Trạng thái triển khai 26/10/2026

Theo quyết định tiếp theo của người dùng, ưu tiên Android xem video, hoãn OAuth vì chưa có Google Cloud client. Đã dựng Flutter UI + Media3 Android và dịch vụ nguồn phát thử trên Mac; cài trực tiếp Samsung Galaxy S10+. Kết quả và giới hạn bản thử xem [docs/ANDROID_QA.md](docs/ANDROID_QA.md). Các nền tảng còn lại vẫn là lộ trình, chưa triển khai.


## Điều chỉnh 0.2.0 — chạy độc lập

Theo yêu cầu tiếp theo, thay toàn bộ nguồn/relay Mac bằng engine nhúng trong APK Android. App tìm kiếm, lấy nguồn và phát HTTPS trực tiếp trên điện thoại, không cần thiết bị khác hay backend riêng. Các script cài/test bỏ `adb reverse`. Báo cáo hiện hành: [ANDROID_STANDALONE_QA.md](docs/ANDROID_STANDALONE_QA.md).


## Cập nhật Android 0.3.0 — 26/10/2026

Đã tách tìm kiếm khỏi engine lấy nguồn video, bổ sung gợi ý từ khóa YouTube khi gõ, lịch sử tìm kiếm cục bộ, bộ nhớ đệm LRU 5 phút và chống phản hồi lỗi thời. Android vẫn độc lập. Đo trên Samsung 5 truy vấn mới: 617–1.380 ms; truy vấn cache: 4 ms. Đã qua kiểm thử nguồn thật và 7 unit/widget tests. Xem `docs/ANDROID_SEARCH_QA.md`. OAuth/các nền tảng khác vẫn chưa triển khai.

## Cập nhật Android 0.4.0 — 26/10/2026

Thêm đường player trực tiếp, HTTP2 cho metadata/media, chuẩn bị nguồn và bộ đệm phần đầu video có giới hạn. Search chuẩn bị trong lúc gõ. Đo Samsung: video mới 927–1.266 ms; chuẩn bị trước/mở lại 144–248 ms; search mới 747–1.197 ms, chuẩn bị trước 9 ms. Đây là số đo trong bài kiểm tra, chưa phải cam kết dưới 500 ms cho mọi video/truy vấn.

Đã sửa toàn màn hình ngang và Back về dọc, đưa điều khiển lên video, đổi giao diện nền đen/chữ trắng/đỏ và thumbnail lớn. Kiểm tra UI xoay thật, phát tiếp sau xoay, tua xa, 4K, 17 tốc độ, 8 chất lượng và timer đều đạt. Chi tiết điều kiện đo và giới hạn trong `docs/ANDROID_FAST_QA.md`. Android tiếp tục chạy độc lập.
