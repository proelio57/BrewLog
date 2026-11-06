package com.brewlog.app

import androidx.compose.ui.window.ComposeUIViewController
import platform.UIKit.UIViewController
import com.brewlog.app.ui.theme.BrewLogTheme

/**
 * iOS Entry point for Compose Multiplatform.
 * In SwiftUI, wrap this via UIViewControllerRepresentable:
 *
 * ```swift
 * struct ComposeView: UIViewControllerRepresentable {
 *     func makeUIViewController(context: Context) -> UIViewController {
 *         MainViewControllerKt.MainViewController()
 *     }
 *     func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
 * }
 * ```
 */
fun MainViewController(): UIViewController = ComposeUIViewController {
    BrewLogTheme {
        // Shared Compose root can be called here
    }
}
