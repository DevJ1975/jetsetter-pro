package com.jetsetter.pro.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.rememberNavController
import com.jetsetter.pro.ui.navigation.JetBottomBar
import com.jetsetter.pro.ui.navigation.JetNavHost

/** Root app shell: a 5-tab bottom-navigation Scaffold hosting the feature screens. */
@Composable
fun JetSetterApp() {
    val navController = rememberNavController()
    Scaffold(
        bottomBar = { JetBottomBar(navController) },
    ) { innerPadding ->
        JetNavHost(navController = navController, modifier = Modifier.padding(innerPadding))
    }
}
