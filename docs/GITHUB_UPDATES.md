# Cập nhật Android qua GitHub

Trong app chọn **Cài đặt → Kiểm tra cập nhật**. App tải APK từ GitHub Release mới nhất và kiểm tra mã gói, versionCode cùng chữ ký trước khi mở trình cài đặt Android. Android yêu cầu người dùng cho phép cài từ nguồn này và xác nhận cài đặt. Tag `build-<versionCode>` giúp app biết khi đã mới nhất mà không tải lại APK.

Workflow `.github/workflows/android-release.yml` build và tạo GitHub Release sau mỗi push lên `main` khi cấu hình dưới đây đã sẵn sàng. `100000 + GITHUB_RUN_NUMBER` là versionCode; tránh sử dụng lại hoặc hạ số này. Khi đổi kho/đưa repo sang tổ chức khác, kiểm tra giá trị `YTB_UPDATE_REPOSITORY` của workflow và URL app đã phát hành trước đó.

Trong GitHub repository → Settings → Secrets and variables → Actions, người sở hữu cần cấu hình các secret:

- `YTB_ANDROID_KEYSTORE_BASE64`: nội dung keystore được mã hóa Base64, một dòng.
- `YTB_ANDROID_KEY_ALIAS`, `YTB_ANDROID_KEY_PASSWORD`, `YTB_ANDROID_STORE_PASSWORD`: alias và mật khẩu tương ứng.

Không commit keystore, mật khẩu hoặc token vào repository. APK cập nhật phải ký cùng khóa với APK đã cài. Bản thử hiện tại dùng debug keystore của máy build; nếu ký bằng khóa khác, Android sẽ từ chối cập nhật đè. Lưu khóa an toàn và chọn khóa ổn định trước khi phát hành rộng rãi. Workflow có quyền ghi Contents để tạo Release; đặt giới hạn quyền branch và secret cho người có thẩm quyền.

App cần truy cập công khai GitHub Release và asset APK, hoặc một dịch vụ phân phối riêng được cấu hình riêng. Repo riêng tư không thể phân phối APK cho người dùng ẩn danh bằng cách nhúng token vào app. Hệ thống không tự cài mã nguồn: Actions phải build thành công và APK phải ký đúng khóa trước khi người dùng có bản cập nhật.
