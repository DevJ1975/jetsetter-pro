package com.jetsetter.pro.feature.expenses

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.jetsetter.pro.core.data.mock.MockData
import com.jetsetter.pro.core.model.Expense
import com.jetsetter.pro.ui.components.JetCard
import com.jetsetter.pro.ui.components.ScaffoldNotice
import com.jetsetter.pro.ui.theme.JetTheme
import java.util.Locale

@Composable
fun ExpensesScreen() {
    val colors = JetTheme.colors
    val spacing = JetTheme.spacing
    val expenses = MockData.expenses
    val total = expenses.sumOf { it.amount }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = spacing.medium)
            .padding(top = spacing.large, bottom = spacing.xlarge),
        verticalArrangement = Arrangement.spacedBy(spacing.medium),
    ) {
        Text("Expenses", style = JetTheme.typography.displayTitle, color = colors.textPrimary)

        JetCard(modifier = Modifier.fillMaxWidth()) {
            Text("TRIP TOTAL", style = JetTheme.typography.caption, color = colors.textSecondary)
            Text(money(total), style = JetTheme.typography.metric, color = colors.textPrimary)
        }

        ScaffoldNotice(
            "Expense tracking is stubbed here — receipt OCR (Google Vision) and accounting exports " +
                "(Brex / Ramp / Divvy / Expensify) are documented in docs/FEATURE_PARITY.md.",
        )

        expenses.forEach { ExpenseRow(it) }
    }
}

@Composable
private fun ExpenseRow(expense: Expense) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Text(expense.merchant, style = typography.bodyMedium, color = colors.textPrimary)
            Text("${expense.category.label} · ${expense.date}", style = typography.caption, color = colors.textSecondary)
        }
        Text(money(expense.amount), style = typography.cardTitle, color = colors.textPrimary)
    }
}

private fun money(amount: Double): String = "$" + String.format(Locale.US, "%,.2f", amount)
