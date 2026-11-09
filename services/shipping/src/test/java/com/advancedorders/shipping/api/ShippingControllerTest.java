package com.advancedorders.shipping.api;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class ShippingControllerTest {
    @Test void calculatesDeterministicDomesticQuote() {
        var quote = new ShippingController().quote("ES",500);
        assertThat(quote.priceCents()).isEqualTo(499);
        assertThat(quote.provider()).isEqualTo("SIMULATED");
    }
    @Test void rejectsImpossibleWeights() {
        assertThatThrownBy(() -> new ShippingController().quote("ES",-1))
            .isInstanceOf(org.springframework.web.server.ResponseStatusException.class);
    }
}
