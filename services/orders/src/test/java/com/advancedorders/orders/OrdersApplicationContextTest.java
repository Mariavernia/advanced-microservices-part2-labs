package com.advancedorders.orders;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Exercises complete Spring application startup, including RestClient.Builder
 * auto-configuration. Mock-based unit tests did not catch the missing starter.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrdersApplicationContextTest {

    @Test
    void applicationContextStarts() {
        // The Spring TestContext framework fails the test if bean injection
        // or server startup fails before this method runs.
    }
}
