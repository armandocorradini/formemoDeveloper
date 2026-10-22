//
//  ForMemoWidgetBundle.swift
//  ForMemoWidget
//
//  Created by Armando Corradini on 18/10/2026.
//

import WidgetKit
import SwiftUI

@main
struct ForMemoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ForMemoWidget()
        ForMemoAgendaWidget()
        ForMemoCalendarTasksWidget()
    }
}
