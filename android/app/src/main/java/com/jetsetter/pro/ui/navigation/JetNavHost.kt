package com.jetsetter.pro.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.jetsetter.pro.feature.expenses.ExpensesScreen
import com.jetsetter.pro.feature.home.HomeScreen
import com.jetsetter.pro.feature.iris.IrisChatScreen
import com.jetsetter.pro.feature.itinerary.ItineraryScreen
import com.jetsetter.pro.feature.more.MoreScreen

@Composable
fun JetNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    NavHost(
        navController = navController,
        startDestination = JetDestination.HOME.route,
        modifier = modifier,
    ) {
        composable(JetDestination.HOME.route) { HomeScreen() }
        composable(JetDestination.ITINERARY.route) { ItineraryScreen() }
        composable(JetDestination.IRIS.route) { IrisChatScreen() }
        composable(JetDestination.EXPENSES.route) { ExpensesScreen() }
        composable(JetDestination.MORE.route) { MoreScreen() }
    }
}
