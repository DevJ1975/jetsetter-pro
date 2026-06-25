package com.jetsetter.pro.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.ui.graphics.vector.ImageVector

/** The five bottom-navigation tabs (parallels the iOS `ContentView` TabView). */
enum class JetDestination(
    val route: String,
    val label: String,
    val icon: ImageVector,
) {
    HOME("home", "Home", Icons.Filled.Home),
    ITINERARY("itinerary", "Itinerary", Icons.Filled.Flight),
    IRIS("iris", "IRIS", Icons.Filled.AutoAwesome),
    EXPENSES("expenses", "Expenses", Icons.Filled.AttachMoney),
    MORE("more", "More", Icons.Filled.MoreHoriz),
}
