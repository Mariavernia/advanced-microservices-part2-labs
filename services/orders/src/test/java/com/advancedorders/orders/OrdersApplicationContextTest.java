package com.advancedorders.orders;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Regression for the missing RestClient.Builder auto-configuration:
 * unit tests mocking InventoryClient alone did not start Spring.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrdersApplicationContextTest {
    @Test
    void applicationContextStarts() {
        // The test fails if the Spring context or HTTP server cannot start.
    }
}
