package com.advancedorders.payments.api;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;
class PaymentsControllerTest {
    @Test void methodsAreNonCharging() {
        var response = new PaymentsController().methods();
        assertThat(response.currency()).isEqualTo("EUR");
        assertThat(response.chargingEnabled()).isFalse();
        assertThat(response.methods()).contains("CARD_TEST");
    }
}
