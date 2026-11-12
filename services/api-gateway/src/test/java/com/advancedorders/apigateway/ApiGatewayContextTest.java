package com.advancedorders.apigateway;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;
class ApiGatewayContextTest {
    @Test void applicationClassIsPresent() {
        assertThat(ApiGatewayApplication.class).isNotNull();
    }
}
