**Kế hoạch Duchaik YTB: đề xuất liên tục, karaoke, tua hai chạm, Shorts và kết nối TV**

Ngày đối chiếu: 26/10/2026, giờ Việt Nam. Nền hiện tại: Android 0.5.0. Trạng thái: kế hoạch, chưa triển khai các thay đổi dưới đây. Yêu cầu phủ rộng TV được tổ chức theo hệ điều hành, giao thức và model đã kiểm thử; không coi một APK Android là ứng dụng cho mọi hệ TV.

**1. Kết quả kiểm tra và nguyên nhân cần sửa**

| Phần | Bằng chứng hiện tại | Hệ quả |
| --- | --- | --- |
| Đề xuất dưới video | `main.dart`, `watchPage()`, lấy `videos.where(...).take(6)` | Bị cắt còn 6 video, dùng lại danh sách trang chủ/tìm kiếm; chưa có nguồn liên quan theo video đang xem |
| Cuộn trang xem | `SingleChildScrollView` chứa toàn bộ `Column` | Không có cursor/scroll controller tải thêm riêng; bỏ `take(6)` đơn thuần vẫn không giải quyết nguồn và hiệu năng |
| Hai chạm | `player_overlay.dart` chỉ có `GestureDetector.onTap` | Chưa nhận hai chạm theo nửa trái/phải; hiện chỉ có nút ±10 giây |
| Hàng đợi | `PlaybackService` quản lý một mục đang phát và các track chất lượng | Chưa có danh sách phát tiếp, sắp xếp, lưu phiên hoặc tự chuyển bài |
| Shorts | Parser tìm kiếm hiện lấy `videoRenderer`; điều hướng chưa có Shorts | Không thể chỉ thêm một tab và tìm từ khóa “shorts” rồi gọi đó là Shorts thật |
| TV | Chưa có discovery, session, adapter phát từ xa hoặc app receiver | Cần cả phần điện thoại lẫn cách phát thực sự ở thiết bị nhận |

Đối chiếu giao diện công khai trong lượt này: (1) trang xem YouTube có danh sách liên quan và dải Shorts riêng — bố cục truy cập được; (2) trang Shorts có player dọc và điều khiển chuyển video — bố cục truy cập được. Ảnh đã xem và lưu: [trang xem](../artifacts/plan-0.6/01-youtube-watch.png), [Shorts](../artifacts/plan-0.6/02-youtube-shorts.png). Quan sát này là web chưa đăng nhập; chưa phải kiểm thử app Premium Android, tài khoản cá nhân hóa hoặc truyền lên TV. Nút chỉ qua ảnh không chứng minh hỗ trợ TalkBack, độ trễ hay khả năng kết nối.

Tài liệu YouTube xác nhận hai chạm trái/phải tua 10 giây; hàng đợi trên mobile/tablet là tính năng Premium. Duchaik triển khai hàng đợi riêng, không cần đăng nhập Google. [Tua YouTube](https://support.google.com/youtube/answer/7509567?co=GENIE.Platform%3DAndroid&hl=en-GB), [hàng đợi YouTube](https://support.google.com/youtube/answer/9546304?co=GENIE.Platform%3DAndroid&hl=en-uk).

**2. Phạm vi và thứ tự ưu tiên**

P0: sửa đề xuất dưới player, tìm bài không dừng nhạc, hàng đợi cơ bản, hai chạm và đo tốc độ. P1: Shorts thật, phát tiếp có chuẩn bị trước, TV Android/Google TV và Google Cast sau thử khả thi. P2: mở rộng Samsung Tizen, LG webOS, DLNA, Fire TV/Matter Casting. Apple TV/AirPlay, Roku và các hệ khác có đợt đánh giá riêng theo SDK/giao thức cho phép.

Giữ tên/logo Duchaik YTB, không đăng nhập, hồ sơ xem cục bộ, không SDK quảng cáo, phát trên điện thoại không cần máy tính hoặc máy chủ riêng. Không đồng nhất kết nối TV, phản chiếu màn hình và cài app độc lập trên TV: giao diện sẽ ghi rõ chế độ đang dùng. Nguồn video vẫn phụ thuộc YouTube cung cấp và thiết bị giải mã được.

**3. Trang xem và đề xuất liên tục**

Luồng điện thoại: player cố định phía trên; tiêu đề/kênh và hành động gọn; ô “Tìm bài tiếp theo”; bộ lọc; danh sách dựng theo vùng nhìn phía dưới. Màn hình rộng đặt player bên trái, danh sách/hàng đợi bên phải. Fullscreen có nút mở bảng “Bài tiếp theo” và hàng đợi, giữ nguyên player và vị trí.

Cập nhật yêu cầu giao diện: header chỉ hiện logo D2K, bỏ dòng chữ “Duchaik YTB” cạnh logo để dành chỗ cho tìm kiếm và Cast. Giữ nhãn accessibility Duchaik YTB cho logo; tên ứng dụng trong launcher/Android Settings vẫn là Duchaik YTB. Logo không thay vai trò nút Back trên trang xem.

Thanh tìm kiếm có nút micro với nhãn “Tìm kiếm bằng giọng nói”, vùng chạm tối thiểu 48dp; áp dụng cả tìm kiếm trang chủ và “Tìm bài tiếp theo”. Không làm mất nút xóa hoặc thao tác gửi truy vấn bằng bàn phím ở màn hình hẹp/chữ lớn.

Luồng giọng nói: bấm micro → mở nhận dạng giọng nói → nói tên video/bài karaoke → nhận câu hoàn chỉnh, điền vào ô và tìm kiếm một lần. Ưu tiên tiếng Việt `vi-VN`; cho sửa câu nhận dạng hoặc bấm micro thử lại. Không gửi tìm kiếm theo mỗi kết quả nhận dạng tạm. Hủy/không nghe rõ phải giữ nguyên truy vấn trước đó; lỗi dịch vụ/mạng có thông báo ngắn và vẫn tìm bằng gõ được.

Ưu tiên thử Android `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` qua activity result, kiểm tra dịch vụ có sẵn và xử lý hủy. Nếu cần nhận dạng nhúng trong app, chọn SpeechRecognizer sau khi đánh giá quyền micro/lifecycle. Chỉ nghe khi người dùng bấm; dừng khi hủy/rời màn hình; app không lưu bản ghi âm. Dịch vụ nhận dạng của thiết bị có thể xử lý qua mạng, nên không mô tả giọng nói là luôn offline hoặc hoàn toàn xử lý trên máy. [Android RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent).

Khi đang phát trên điện thoại, phối hợp audio focus để nhạc không lấn giọng: giảm âm/tạm dừng trong lúc nghe và chỉ phục hồi nếu trước đó đang phát, người dùng chưa đổi trạng thái. Khi đang cast, không tự dừng TV chỉ vì mở micro; đánh giá nhiễu âm ở máy thật, có đường nhập chữ dự phòng. Không coi micro trên điện thoại là thu âm/chấm điểm karaoke.

- Mỗi phiên có `RelatedFeedSession` riêng, khóa theo video ID + chế độ + truy vấn; không dùng chung cursor với trang chủ hoặc Shorts.
- Trang đầu mục tiêu 20–24 mục; khi còn khoảng 6–8 mục chưa cuộn tới thì chuẩn bị một trang tiếp. Không quota ngày, không giới hạn cứng 6/24/100 video.
- Thử nguồn liên quan công khai theo video và continuation thực tế trước; đây là hạng mục cần kiểm chứng parser/độ ổn định. Nếu nguồn liên quan không dùng được, dự phòng bằng tìm kiếm theo tên bài, nghệ sĩ, kênh và chủ đề. Ghi đúng nguồn, không gọi kết quả tìm kiếm là đề xuất cá nhân chính thức của YouTube.
- Karaoke ưu tiên ngữ cảnh đang hát; không tự trộn video thời sự/trending khi người dùng đang tìm beat. Mở rộng truy vấn có thứ tự khi một nhánh cạn.
- Loại video đang phát, video ẩn, video trùng; hạn chế một kênh chiếm hết trang. Hàng đợi do người dùng chọn được ưu tiên hơn xếp hạng tự động.
- Cursor là dữ liệu opaque, gắn đúng nguồn/phiên; không tự sửa token. Token lặp, trang rỗng liên tiếp, lỗi mạng và hết nguồn là các trạng thái khác nhau.
- Tối đa một yêu cầu nối trang cho mỗi phiên. Chuyển A sang B phải vô hiệu phản hồi của A; không để kết quả cũ ghi đè video B.
- Back phục hồi vị trí cuộn và bộ lọc. Không nhảy danh sách khi hồ sơ sở thích cập nhật hoặc qua nửa đêm trong lúc đang chọn bài.
- Cache metadata/ảnh cho các trang gần; cửa sổ RAM hữu hạn, lưu metadata cũ xuống đĩa nếu cần. Không giữ hàng nghìn widget và player. TTL của cursor và metadata tách biệt; cursor hết hạn thì nạp phiên mới có loại trùng.
- Mạng lỗi: giữ video đang phát, giữ kết quả đã có, hiện thử lại tại cuối danh sách. Hết tất cả nhánh: báo đã hết kết quả phù hợp và cho đổi bộ lọc; không tạo vòng lặp video giả vô hạn.

Nghiệm thu: với nguồn đủ dữ liệu, cuộn ít nhất 20 trang/400 kết quả; không lặp trong phiên, không đứng ở trang 2, không ngắt nhạc. Fixture hữu hạn phải dừng đúng; fixture lỗi phải retry được; phản hồi cũ phải bị loại. Bỏ qua một trang toàn video trùng không được biến thành vòng request vô hạn.

**4. Karaoke và hàng đợi**

Từ màn hình đang hát, người dùng tìm bài mới mà không rời player. Tìm kiếm có gợi ý, lịch sử và chuẩn bị kết quả như hiện tại. Các chip “Karaoke”, “Beat”, “Tông nam”, “Tông nữ”, “Song ca”, “Cùng ca sĩ” thay đổi truy vấn/xếp hạng. Tông được suy từ mô tả nguồn, không cam kết là kết quả phân tích âm nhạc; đổi tông DSP, thu micro và chấm điểm giọng hát chưa nằm trong đợt này.

Mỗi kết quả có ba hành động rõ: “Phát ngay”, “Phát tiếp”, “Thêm cuối”. Trong chế độ chọn bài karaoke, chạm nút thêm không được thay bài hiện tại. Có thông báo đã thêm và hoàn tác, không đẩy thêm cùng video do chạm hai lần hoặc gửi lại lệnh.

Hàng đợi hỗ trợ mở dạng bảng kéo lên, đổi thứ tự, xóa, phát bài được chọn, bài trước/sau, lặp một bài hoặc cả danh sách. Lưu danh sách karaoke riêng trên máy, đổi tên, khôi phục sau app bị hệ điều hành đóng; dữ liệu lưu ID/metadata, không lưu URL có chữ ký như địa chỉ vĩnh viễn. “Xem sau” vẫn riêng với hàng đợi phiên hiện tại.

Khi bài kết thúc, phát mục kế trong hàng đợi trước; nếu hàng đợi rỗng, chỉ dùng đề xuất khi người dùng đã bật tự động phát. Có lựa chọn dừng sau bài. Timer ngủ thắng autoplay. Bài lỗi báo rõ, cho thử lại/bỏ qua; nếu cho tự bỏ qua thì có giới hạn để không chạy xuyên toàn bộ hàng đợi khi mất mạng.

Chuẩn bị trước bài kế tiếp, giải lại URL gần lúc phát khi cần; dùng lại service/session và cache. Danh sách hàng đợi thay đổi phải hủy công việc chuẩn bị cho mục đã bỏ. TV có hàng đợi riêng trên receiver hoặc đồng bộ phiên có version/sequence; mạng reconnect không nhân đôi bài.

**5. Hai chạm để tua**

- Hai chạm trong cùng vùng trái: −10 giây; phải: +10 giây. Phần giữa dành cho play/pause và thao tác hiện điều khiển.
- Áp dụng cả dọc, ngang và fullscreen; vùng tính từ kích thước player hiện tại, không từ tọa độ màn hình cố định.
- Hiện phản hồi ±10s ngay; chuỗi chạm cùng bên có thể cộng 20/30s, với vị trí đích đang chờ làm gốc. Không cộng từ số position polling cũ mỗi 500 ms.
- Gộp chuỗi chạm ngắn để tránh nhiều lần buffer; vẫn phản hồi hình ngay. Đổi bên thì tính lại từ đích đã nhận, không tạo một lệnh forward đến muộn sau lệnh rewind.
- Clamp vào 0…duration. Giữ trạng thái pause nếu đang pause. Video chưa sẵn sàng, duration chưa biết, stream không seek được phải có xử lý riêng.
- Không nhận gesture trên slider/nút/cửa sổ menu; không khiến thao tác kéo seek hoặc chạm play trở thành hai chạm. Giữ nút ±10 giây có nhãn cho TalkBack; TV remote dùng trái/phải.
- Khi đang cast, lệnh được gửi tới playback target hiện tại; không tua nhầm player ở điện thoại.

Kiểm thử: đầu/cuối video, pause/play, 5×, 10 lần chạm nhanh, đổi bên, rotate giữa chuỗi, bị gián đoạn app, TalkBack. Đo từ lần chạm được công nhận đến frame/âm thanh tại vị trí mới, không chỉ thời gian gọi hàm seek trả về.

**6. Shorts**

Điều hướng dự kiến: Trang chủ / Shorts / Karaoke / Thư viện; Cast ở header/player, Cài đặt ở header. Thư viện gộp lịch sử, xem sau, playlist và dữ liệu cá nhân. Không thêm mục tải lên/bình luận/đăng ký kênh giả khi chưa có khả năng thực hiện.

- Feed Shorts riêng, vuốt dọc từng video, quay lại clip trước; giữ vị trí khi rời tab.
- Nguồn phải cung cấp dấu hiệu Shorts thật hoặc liên kết `/shorts/`; parser xử lý cấu trúc Shorts riêng. Không suy chỉ từ chữ “Shorts” trong tên hoặc ngưỡng 60 giây. YouTube hiện có Shorts đến 3 phút với điều kiện phân loại cụ thể. [YouTube Shorts 3 phút](https://support.google.com/youtube/answer/15424877?hl=en-GB).
- Khi resolve, kiểm tra thời lượng/kích thước thực và khả năng phát. Video không xác minh được không tự nhồi vào feed Shorts; nội dung không phát được có retry/chuyển tiếp có giới hạn.
- Một video thực sự phát tại một thời điểm. Chuẩn bị clip kế, giữ metadata clip trước và thêm một clip phía sau; không tạo nhiều decoder 4K chạy đồng thời.
- Ưu tiên 480/720p để bắt đầu, chỉ nâng khi người dùng dừng và mạng/decoder đủ. Không crop mất chữ dọc hoặc méo video vuông; mặc định fit, lựa chọn fill có chủ ý.
- Play/pause, bật/tắt tiếng, thanh tiến độ, lưu cục bộ, chia sẻ link, “Không quan tâm”, mở trang xem đầy đủ. Nếu có tim thì ghi là yêu thích trên máy, không giả đã like trên YouTube.
- Quy tắc hai chạm hai bên giữ nhất quán với yêu cầu tua; không gán cùng gesture thành thả tim. Clip quá ngắn clamp vị trí. Vuốt dọc phải thắng gesture chạm khi thực sự đang kéo.
- Học theo tỷ lệ xem, thời gian thực, xem lại có giới hạn và bỏ qua nhanh; hồ sơ Shorts tách trọng số khỏi karaoke/video dài để không làm trôi sở thích chọn bài.
- Vào Shorts khi đang hát/cast không tự giành âm thanh hoặc chuyển TV theo mỗi lần vuốt. Khi cast hoạt động, mặc định duyệt thumbnail/tắt tự phát tại máy; chỉ gửi clip khi bấm “Phát trên TV”. Khi trở lại, phục hồi phiên video dài.

Nghiệm thu: 100 lượt vuốt, không hai âm thanh cùng lúc, không lỗi decoder/OOM, không phát clip cũ sau vuốt nhanh; memory ổn định sau nhiều vòng; tắt màn hình/rời tab không để âm thanh Shorts ngoài ý muốn.

**7. Phạm vi TV theo khả năng thực tế**

Mục tiêu là phủ rộng các thiết bị có giao thức tương thích và receiver chạy được. Khác biệt nằm ở OS/model/firmware, không chỉ hãng. Một hãng có thể bán Google TV, Fire TV và hệ riêng.

| Nhóm | Phương án | Mức cam kết sau kiểm thử |
| --- | --- | --- |
| Android TV / Google TV | Duchaik TV receiver chạy Media3, điều khiển LAN; tích hợp Cast Connect khi cấu hình đủ | Ưu tiên đầy đủ hàng đợi, seek, chất lượng theo máy; receiver tự phát không cần Mac |
| Chromecast / Google Cast tích hợp | Google Cast sender + receiver; thử media thực và CORS trước | Chỉ công bố độ phân giải, seek, tốc độ, queue đã xác nhận |
| Samsung Tizen | Receiver Tizen qua SDK hỗ trợ, hoặc giao thức thực có trên model | Cần app TV riêng cho tích hợp sâu; không mặc định Smart View cũ hoạt động trên mọi đời |
| LG webOS | Google Cast trên model có hỗ trợ; app webOS riêng hoặc DLNA trên model tương thích | Chọn adapter theo capability, kiểm tra codec/firmware |
| Fire TV chạy Fire OS | Receiver Fire OS và Matter Casting | Tách khỏi Google Play Services; không phụ thuộc Fling cũ |
| Fire TV chạy Vega OS | Receiver/SDK Vega và Matter Casting | Không cài APK Android và gọi đó là đã hỗ trợ Vega |
| TV có UPnP/DLNA MediaRenderer | Discovery, media URI, play/pause/seek/volume theo service thực | Có thể chỉ hỗ trợ phát cơ bản; không suy có queue hoặc 5× |
| Apple TV / TV chỉ có AirPlay | AirPlay chính thức cho bản Apple về sau; Android cần phương án sender/receiver được xác minh riêng | Chưa đưa vào cam kết của APK Android 0.6 |
| Roku TV | Đánh giá tích hợp/receiver được Roku cho phép; giao thức khác nếu model cung cấp | Không lấy ECP từ app bên thứ ba làm nền tích hợp |
| VIDAA, Titan OS, hệ Linux/hệ riêng khác | Xác định Cast/DLNA/receiver hoặc SDK của model | Ghi rõ đã test/hạn chế/chưa hỗ trợ; không suy từ việc TV có trình duyệt |
| TV không có giao thức/app phù hợp | Thiết bị nhận HDMI tương thích; phản chiếu bằng hệ điều hành nếu có | Phản chiếu phụ thuộc điện thoại, không ngang với receiver độc lập |

Google Cast Connect cần receiver Android TV, không chỉ một nút trong Flutter. [Cast Connect](https://developers.google.com/cast/docs/android_tv_receiver). Samsung yêu cầu sender/receiver và ghi DMP không được hỗ trợ sau 2021. [Samsung Smart View](https://developer.samsung.com/smarttv/develop/extension-libraries/smart-view-sdk/getting-started.html). Các công cụ webOS tạo/cài ứng dụng TV riêng. [LG SDK](https://webostv.developer.lge.com/develop/tools/sdk-introduction).

Amazon Fling hết hỗ trợ ngày 05/03/2026, khuyến nghị Matter Casting. Fire TV hiện có cả Fire OS và Vega OS. [Fling](https://www.developer.amazon.com/docs/fling/using-amazon-fling-with-android-mediarouter.html), [Fire TV OS](https://developer.amazon.com/docs/fire-tv/fire-os-overview.html), [Matter trên Vega](https://developer.amazon.com/docs/vega/0.24/vega-matter-casting-integration). Roku ghi ECP không được gửi từ nền tảng bên thứ ba như mobile app. [Roku ECP](https://developer.roku.com/dev/docs/external-control-api). AirPlay của Apple mô tả đường truyền từ thiết bị Apple, không xác nhận SDK Android tương đương. [Apple AirPlay](https://support.apple.com/en-ie/102661).

**8. Luồng kết nối TV và xử lý nguồn**

Người dùng bấm Cast → danh sách TV cùng mạng → chọn TV → nhập mã ghép nếu cần → màn hình báo đúng tên TV và nội dung đang phát. Lần sau có thiết bị đã ghép và quyền thu hồi. Không tự tìm/quét LAN liên tục khi chưa dùng chức năng TV. Mã Duchaik là của receiver Duchaik, không phải mã ghép YouTube.

Trạng thái rõ: đang tìm, không thấy thiết bị, chờ xác nhận, kết nối, đang nạp, đang phát, kết nối lại, lỗi tương thích. Có hướng dẫn kiểm tra cùng LAN, mạng khách/AP isolation, TV đang bật và receiver được mở; Ethernet TV + Wi-Fi điện thoại vẫn có thể cùng LAN.

Điều khiển: play/pause, seek, bài trước/sau, queue, âm lượng và chất lượng/tốc độ khi receiver báo có hỗ trợ. State trên TV là nguồn chính khi cast; lệnh có sequence ID, ACK và timeout để retry không thêm bài hai lần. Một TV có thể báo nhiều protocol, danh sách cần hợp nhất thành một thiết bị.

Handoff: chuẩn bị phát tại đích, nhận trạng thái sẵn sàng rồi dừng tiếng ở nguồn. Khi ngắt kết nối, cho chọn để TV phát tiếp hoặc chuyển về điện thoại; lấy vị trí thật từ TV, không dùng position local cũ. Receiver độc lập nhận đủ hàng đợi/ID để tiếp tục khi điện thoại khóa màn hình hoặc mất kết nối; chức năng cần điện thoại duy trì phải ghi rõ.

Nguồn hiện tại dùng hai luồng hình/tiếng ghép bằng Media3. Không thể giả định đưa URL video vào TV là đủ. Spike bắt buộc với video đang dùng thực tế: audio, video, codec, init segment/range, manifest DASH/HLS, CORS, header, URL hết hạn và khả năng tải từ chính TV. [Google Cast media](https://developers.google.com/cast/docs/media).

Ưu tiên receiver native tự resolve ID và tải trực tiếp. Web receiver có thể cần manifest phù hợp và hosting HTTPS; custom Cast receiver cần App ID/đăng ký. Default Media Receiver không cần đăng ký nhưng ít khả năng tùy biến, chưa chứng minh dùng được với nguồn tách hình/tiếng của app. [Đăng ký Cast](https://developers.google.com/cast/docs/registration), [Web receiver](https://developers.google.com/cast/docs/web_receiver/basic).

Nếu buộc phải relay/ghép trên điện thoại cho một nhóm TV, đó là chế độ tương thích riêng, có chi phí pin/mạng và phụ thuộc điện thoại; không mặc định chuyển sang chế độ này. Không tạo server trên Mac làm đường chạy cho app. Không tự đẩy sang ứng dụng YouTube TV rồi hứa giữ hành vi quảng cáo, 5× hoặc chất lượng của Duchaik.

Receiver/host SDK, chứng chỉ hoặc tài khoản phát hành của từng hệ là phụ thuộc phát triển, không phải yêu cầu người xem đăng nhập. Chưa tạo tài khoản, trả phí, mở router hoặc phát hành công khai trong bước lập kế hoạch này.

**9. Tối ưu và ngân sách hiệu năng**

Các số dưới đây là mục tiêu cần đo trên release, không phải kết quả đã đạt. Baseline 0.5: trang ứng viên đã có 15–19 ms, video chuẩn bị trước 216 ms, seek 157–562 ms, một trang mới trong test khoảng 1,57 s; đây chỉ là vài mẫu trên Samsung và chưa phải p95.

| Phép đo | Mục tiêu trên Samsung, Wi-Fi ổn định |
| --- | --- |
| Phản hồi hình cho chạm/thêm queue | p95 ≤80 ms |
| Ghép trang metadata đã chuẩn bị vào danh sách | p95 ≤100 ms; đo render/ảnh riêng |
| Bấm video đã chuẩn bị đến frame/tiếng đầu | p50 ≤300 ms, p95 ≤500 ms |
| Seek vùng đủ cache | p50 ≤250 ms, p95 ≤500 ms |
| Seek phải tải qua mạng | p50 ≤800 ms, p95 ≤1.500 ms |
| Mở video chưa chuẩn bị | p50 ≤1.500 ms, p95 ≤2.500 ms, tách lỗi nguồn/fallback |
| Vuốt sang Short đã chuẩn bị | p95 ≤500 ms |
| Cuộn giao diện | Ngân sách 16,7 ms/frame trên màn 60 Hz, đo tỷ lệ frame trễ |
| TV | Đo discovery, kết nối đầu, load và chuyển bài riêng; chốt SLA theo receiver sau spike |

Không áp mục tiêu 500 ms cho lần đầu bắt tay TV hoặc mọi yêu cầu Internet. Không đổi số metadata/cache thành số thời gian có hình/tiếng.

Ưu tiên tài nguyên: video người dùng chọn/seek → bài kế trong queue → metadata trang liên quan → ảnh vùng nhìn → clip Shorts kế → tác vụ khám phá nền. Giảm/dừng speculative prefetch khi player buffer hoặc mạng bị tính dung lượng; không để Shorts/karaoke/TV cùng tải không kiểm soát.

Giữ cache ổn định theo video/track/version và giới hạn đĩa 128 MiB ban đầu; chỉ tăng sau đo. Cache metadata, ảnh, URL nguồn và media có TTL khác nhau. URL hết hạn được resolve lại đúng một tác vụ dùng chung; không chạy lại extractor nặng trên mỗi lần seek. Gộp yêu cầu trùng, hủy tác vụ đã lỗi thời, giảm ưu tiên prefetch khi có thao tác thật. Việc hủy một người chờ không được hủy yêu cầu chia sẻ mà playback đang dùng.

Đánh giá `DefaultPreloadManager` với MergingMediaSource và builder/player dùng chung; nếu không tương thích nguồn hiện tại thì giữ CacheWriter và nâng bộ lập lịch trước. Không thay player chỉ vì thư viện có tên “preload”. [Media3 preloading](https://developer.android.com/media/media3/exoplayer/preloading-media/preloadmanager), [nguyên tắc builder](https://developer.android.com/media/media3/exoplayer/preloading-media/preloadmanager/concepts).

Không dựng lại toàn bộ danh sách mỗi tick 500 ms. Tách trạng thái tiến độ khỏi feed/queue; chỉ dựng item vùng nhìn, decode ảnh theo kích thước thẻ. Giữ bản sửa native surface khi fullscreen. Giới hạn byte/preload theo RAM và codec, tránh giữ nhiều decoder cùng lúc. Không đánh đổi âm thanh, đồng bộ A/V hoặc cache đúng track để có một số TTFF đẹp.

**10. Kiến trúc và điểm sửa cụ thể**

| Thành phần dự kiến | Trách nhiệm |
| --- | --- |
| `RelatedFeedRepository`, `RelatedFeedSession` | Nguồn theo video, cursor riêng, loại trùng, cache, fallback và lỗi |
| `WatchPage`, `RelatedVideoList` | Sliver/lazy list, ngữ cảnh tìm bài, lưu scroll; tách khỏi `main.dart` lớn |
| `QueueController`, `QueueRepository` | Danh sách có revision/entryId, reorder, lưu/khôi phục, playlist karaoke |
| `PlaybackCoordinator` | Một target phát chủ động: máy, Shorts hoặc TV; handoff, timer và next |
| `SeekGestureController` | Vùng chạm, gom chuỗi, pending target, phản hồi và tránh gesture conflict |
| `ShortsRepository`, `ShortsPage` | Nguồn Shorts xác minh, cursor, tín hiệu sở thích riêng và prefetch hữu hạn |
| `CastController`, `RemotePlaybackAdapter` | Discovery, pairing, capabilities, session, queue và reconnect |
| `YouTubeRelated.kt`, `YouTubeShorts.kt` | Adapter nguồn native cần spike/parser fixtures, không hardcode từ DOM sample |
| `PlaybackService.kt`, `StartupCache.kt` | Native queue/next, target seek, preload/cache, audio focus và counters |
| Receiver Android TV / Tizen / webOS / Fire OS / Vega | Player, remote input, tự lấy nguồn, trạng thái và điều khiển theo từng hệ |

Schema chung: `VideoItem` có ID, title, channel, thumbnail, type/shorts evidence, duration; `PageCursor` có provider/seed/mode/token; `QueueEntry` có entryId/videoId/order; `PlaybackSnapshot` có target/session/position/buffering/duration/capabilities; `SourceLease` có track/expiry và không chứa thông tin nhạy cảm trong log.

Capabilities gồm seek, volume, queue, speed, quality, subtitles, receiverOwnsPlayback, continueWithoutPhone. UI không báo có chức năng chỉ vì một TV đã được tìm thấy. Data migration phải giữ lịch sử/xem sau/hồ sơ 0.5; cập nhật không làm mất dữ liệu. Không đồng bộ lịch sử lên TV ngoài phần nội dung/queue người dùng chủ động gửi.

**11. Kế hoạch thực hiện và đầu ra từng mốc**

| Mốc | Công việc | Điều kiện hoàn thành |
| --- | --- | --- |
| A — Baseline và spike | Đo release 0.5; thử related continuation/Shorts thật; kiểm tra media trên Google Cast và receiver native | Kết quả nguồn/TV có bằng chứng, chọn đường triển khai; không mở rộng UI dựa trên giả định chưa chạy được |
| B — Android 0.6 | Header chỉ logo, tìm bằng giọng nói, trang xem phân trang riêng, tìm bài tại chỗ, queue cơ bản/persist, hai chạm | Test giọng nói/hủy/lỗi, 400 mục, 30 bài queue, seek gesture và regression playback đạt; APK cài Samsung |
| C — Android 0.7 | Tab Karaoke hoàn chỉnh, playlist, Shorts, preload và chuyển phiên | 100 lượt Shorts; queue nền/timer; bộ nhớ và latency đạt mục tiêu hoặc có số đo chênh lệch rõ |
| D — TV nền tảng đầu | Duchaik TV cho Android/Google TV + Cast tương thích nguồn đã thử | Điện thoại chọn bài, TV phát liên tục, điều khiển remote, khóa điện thoại, reconnect và chuyển bài đạt |
| E — Mở rộng TV | Tizen/webOS/DLNA, Fire OS/Vega/Matter theo kết quả spike | Có receiver/adapter được xác minh trên từng nhóm, tài liệu model/firmware và giới hạn |
| F — Hệ còn lại | AirPlay/Apple TV, Roku, VIDAA/Titan hoặc phụ kiện nhận phù hợp | Chỉ phát hành khi có đường tích hợp và thiết bị kiểm chứng; không gắn nhãn “tất cả TV” từ test giả lập |

Mốc là thứ tự bàn giao đề xuất, chưa phải lịch ngày cố định. Công việc phụ thuộc TV/SDK không chặn sửa lỗi 6 video trên điện thoại. Mỗi APK có version riêng trong `gen`, giữ bản trước để đối chiếu; việc hạ version trên máy có thể cần quy trình riêng, không mặc định `adb install` hạ được mà vẫn giữ dữ liệu.

**12. Ma trận kiểm thử và tiêu chuẩn bàn giao**

Unit/fixtures: cursor nhiều trang, token lặp, mạng lỗi, kết quả rỗng, id trùng, phản hồi sai phiên; queue insert/remove/reorder/retry/revision; seek cộng dồn/clamp; phân loại Shorts; clock/timer; capability của TV. Test cần kiểm hành vi, không chỉ khớp implementation.

Giọng nói/giao diện: tên tiếng Việt có dấu, tên nước ngoài, nói “karaoke” kèm tên bài; chỉ một truy vấn sau kết quả cuối; hủy/timeout/không có dịch vụ/từ chối quyền nếu có; bấm micro liên tiếp, xoay/rời màn hình, nhạc đang phát hoặc đang pause, phiên cast đang chạy; không tự bật lại bài đã bị người dùng dừng. Header chỉ có logo, tên launcher giữ nguyên, TalkBack đọc đúng, ô tìm và micro không tràn ở chiều rộng 320dp/chữ lớn.

Thiết bị: Samsung hiện có; emulator API tối thiểu và Android mới để kiểm tương thích; tablet/máy gập/landscape; Android TV thật hoặc box, thiết bị Cast thật, Samsung Tizen, LG webOS, Fire OS, Vega, DLNA theo mốc. Emulator không thay thế kiểm codec, DRM, CORS, discovery/multicast và OEM thật. D-pad/focus/Back/overscan và MediaSession TV phải được kiểm riêng. [Android TV quality](https://developer.android.com/docs/quality-guidelines/tv-app-quality).

Mạng: Wi-Fi tốt, Wi-Fi chậm, mạng tính dung lượng, mất mạng rồi có lại, đổi access point, TV Ethernet/điện thoại Wi-Fi, guest isolation, multicast bị chặn, URL hết hạn. Giả lập chỉ dùng cho lỗi/độ trễ kiểm soát được; kết quả mạng thực ghi loại kết nối.

Hiệu năng: ít nhất 50 mẫu warm/prepared và 30 mẫu cold/cache-miss cho mỗi luồng chính, công bố p50/p95, cache hit và tỷ lệ lỗi; tách resolve, load, first frame, audio ready, seek ready. Đo release trên cùng điều kiện, theo nhiều video/kích thước; không trộn sample debug và release. Theo dõi frame trễ, bộ nhớ sau nhiều vòng và dropped frames/A-V sync ở 1×, 2×, 5×/4K khi máy hỗ trợ.

Hồi quy: 17 tốc độ, 144–2160 theo nguồn, hẹn ngủ, PiP/phát nền, audio focus/cuộc gọi, rút tai nghe, xoay/fullscreen/Back, tiếp tục vị trí cũ, nút volume, no-login và opt-out cá nhân hóa. Kiểm actual native video surface sau rotate, không chỉ Flutter widget bounds.

TV: phân biệt tìm thấy thiết bị với phát được media. Phát ≥30 phút, chọn ≥20 bài, seek/reorder giữa phiên, tắt/khóa điện thoại, rút mạng/reconnect, đổi TV, receiver bị đóng, 403 URL hết hạn, TV báo thiếu codec; không mất queue hoặc hai thiết bị phát tiếng ngoài ý muốn. Ghi từng model/OS/firmware/adapter/codec/độ phân giải/tốc độ đã đạt.

Bàn giao mỗi mốc: APK/receiver tương ứng trong `gen`, logo giữ nguyên, SHA-256, hướng dẫn cài, changelog, số đo release, kết quả test và bảng tương thích có ba trạng thái: đã test, hạn chế, chưa test. Đã triển khai bản Android 0.6.0, gồm phần B, Shorts/playlist của C và receiver Android TV cơ bản. Xem `DUCHAIK_0.6_QA.md` để phân biệt kết quả đã test với các mục TV/hiệu năng còn chưa đạt hoặc chưa có phần cứng kiểm chứng. Các mốc D–F chưa hoàn thành toàn bộ.
