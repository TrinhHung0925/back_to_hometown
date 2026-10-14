package com.example.back_to_hometown

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/// Port từ tài liệu hide_top_and_bottom_navigator_bar.md, chỉnh cho game ngang:
/// ẩn CẢ status bar lẫn navigation bar (bản gốc chỉ làm status bar trong
/// suốt), và cho nội dung vẽ tràn vào vùng tai thỏ — Flutter tự chừa chỗ
/// bằng SafeArea.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        drawIntoDisplayCutout()
        makeStatusBarTransparent()
        hideSystemBars()
        installAutoReHide()
    }

    /// Màn ngang thì tai thỏ nằm ở cạnh trái/phải; không bật cờ này thì
    /// cạnh đó bị một dải đen.
    private fun drawIntoDisplayCutout() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    /// Status bar trong suốt để lúc nó hiện tạm (vuốt từ mép trên) không
    /// che game bằng một dải màu.
    private fun makeStatusBarTransparent() {
        window.statusBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // setDecorFitsSystemWindows(false) đã gọi trong hideSystemBars.
            window.insetsController?.setSystemBarsAppearance(
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
            )
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                window.decorView.systemUiVisibility or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
    }

    // Hệ thống trả lại system bars khi app mất focus (dialog quyền, ads,
    // switch app...) — lấy lại focus thì phải ẩn lại.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemBars()
        }
    }

    // Ads fullscreen là một Activity khác đè lên — đóng ads có thể chỉ bắn
    // onResume mà không đổi window focus, nên ẩn lại ở đây nữa.
    override fun onResume() {
        super.onResume()
        hideSystemBars()
    }

    /// Hai chỗ trên vẫn lọt lưới trường hợp BÀN PHÍM (ô chat trong game): IME
    /// kéo system bars hiện theo, lúc IME rút đi thì bar ở lại mà không có sự
    /// kiện focus nào. Nghe thẳng insets: cứ thấy bar hiện trong khi bàn phím
    /// KHÔNG mở là ẩn lại. (Không ẩn lúc IME đang mở — giật layout bàn phím.)
    private fun installAutoReHide() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.setOnApplyWindowInsetsListener { view, insets ->
                val barsVisible = insets.isVisible(WindowInsets.Type.navigationBars()) ||
                    insets.isVisible(WindowInsets.Type.statusBars())
                val imeVisible = insets.isVisible(WindowInsets.Type.ime())
                if (barsVisible && !imeVisible) {
                    // post: đổi insets ngay trong callback insets là re-entrant.
                    view.post { hideSystemBars() }
                }
                view.onApplyWindowInsets(insets)
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.setOnSystemUiVisibilityChangeListener { visibility ->
                if (visibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION == 0 ||
                    visibility and View.SYSTEM_UI_FLAG_FULLSCREEN == 0
                ) {
                    window.decorView.post { hideSystemBars() }
                }
            }
        }
    }

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.navigationBars() or WindowInsets.Type.statusBars())
                it.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            // Giữ 2 cờ status bar — dòng này ghi ĐÈ toàn bộ
                            // visibility, thiếu chúng là mỗi lần ẩn lại thì
                            // mất status bar trong suốt.
                            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                    )
        }
    }
}
