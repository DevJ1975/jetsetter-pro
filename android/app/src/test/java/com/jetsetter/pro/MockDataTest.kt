package com.jetsetter.pro

import com.jetsetter.pro.core.data.mock.MockData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Plain JVM unit tests over the seed data — runs in CI via `testDebugUnitTest`. */
class MockDataTest {

    @Test
    fun seedTripsArePresent() {
        assertTrue("Expected at least one seed trip", MockData.trips.isNotEmpty())
    }

    @Test
    fun everyTripHasItineraryItems() {
        assertTrue(MockData.trips.all { it.items.isNotEmpty() })
    }

    @Test
    fun expenseTotalIsCorrect() {
        val total = MockData.expenses.sumOf { it.amount }
        assertEquals(1812.75, total, 0.001)
    }
}
