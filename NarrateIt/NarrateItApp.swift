//
//  NarrateItApp.swift
//  NarrateIt
//
//  Created by Vetrichelvan Jeyapalpandy on 07/09/24.
//

import SwiftUI

@main
struct NarrateItApp: App {
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                themeBackgroundColor.edgesIgnoringSafeArea(.all)
                ContentView()
                    .environmentObject(themeManager)
            }
            .preferredColorScheme(colorScheme)
        }
    }

    private var themeBackgroundColor: Color {
        switch themeManager.appTheme {
        case .system:
            return Color(.windowBackgroundColor)
        case .light:
            return Color.white
        case .dark:
            return Color.black
        }
    }

    private var colorScheme: ColorScheme? {
        switch themeManager.appTheme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
