package com.example.back_to_hometown

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        makeStatusBarTransparent()
        hideNavigationBar()
        installAutoReHide()
    }

    /// Status bar trong suốt, content vẽ tràn ra sau — Flutter tự chừa chỗ
    /// bằng SafeArea. Icon để màu TỐI vì nền các màn của app đều sáng;
    /// app có màn nền tối thì đổi cờ này theo màn qua SystemChrome.
    private fun makeStatusBarTransparent() {
        window.statusBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // setDecorFitsSystemWindows(false) đã gọi trong hideNavigationBar.
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
            hideNavigationBar()
        }
    }

    // Ads fullscreen là một Activity khác đè lên — đóng ads có thể chỉ bắn
    // onResume mà không đổi window focus, nên ẩn lại ở đây nữa.
    override fun onResume() {
        super.onResume()
        hideNavigationBar()
    }

    /// Hai chỗ trên vẫn lọt lưới trường hợp BÀN PHÍM: IME kéo navigation bar
    /// hiện theo, lúc IME rút đi thì bar ở lại mà không có sự kiện focus nào.
    /// Nghe thẳng insets: cứ thấy bar hiện trong khi bàn phím KHÔNG mở là ẩn
    /// lại. (Không ẩn lúc IME đang mở — giật layout bàn phím, và bar sẽ bị
    /// xử ngay khi IME rút.)
    private fun installAutoReHide() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.setOnApplyWindowInsetsListener { view, insets ->
                val navVisible = insets.isVisible(WindowInsets.Type.navigationBars())
                val imeVisible = insets.isVisible(WindowInsets.Type.ime())
                if (navVisible && !imeVisible) {
                    // post: đổi insets ngay trong callback insets là re-entrant.
                    view.post { hideNavigationBar() }
                }
                view.onApplyWindowInsets(insets)
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.setOnSystemUiVisibilityChangeListener { visibility ->
                if (visibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION == 0) {
                    window.decorView.post { hideNavigationBar() }
                }
            }
        }
    }

    private fun hideNavigationBar() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.navigationBars())
                it.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            // Giữ 2 cờ status bar — dòng này ghi ĐÈ toàn bộ
                            // visibility, thiếu chúng là mỗi lần re-hide nav
                            // bar lại mất status bar trong suốt.
                            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                    )
        }
    }
}
