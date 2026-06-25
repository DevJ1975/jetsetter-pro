package com.jetsetter.pro.core.model

import java.util.UUID

/** A travel expense (iOS `ExpenseModel.Expense`). */
data class Expense(
    val id: String = UUID.randomUUID().toString(),
    val amount: Double,
    val currency: String = "USD",
    val category: ExpenseCategory,
    val merchant: String,
    val date: String,        // ISO-8601 date
    val notes: String? = null,
)

enum class ExpenseCategory(val label: String) {
    FOOD("Food"),
    TRANSPORT("Transport"),
    ACCOMMODATION("Accommodation"),
    ENTERTAINMENT("Entertainment"),
    BUSINESS("Business"),
    SHOPPING("Shopping"),
    MEDICAL("Medical"),
    MILEAGE("Mileage"),
    OTHER("Other"),
}
