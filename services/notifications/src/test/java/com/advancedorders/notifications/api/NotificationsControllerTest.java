package com.advancedorders.notifications.api;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class NotificationsControllerTest {
    @Test void providerOnlyReportsConfiguredState() {
        var ctrl = new NotificationsController("training-key","simulated");
        assertThat(ctrl.provider().credentialConfigured()).isTrue();
        assertThat(ctrl.provider().deliveryEnabled()).isFalse();
        assertThat(ctrl.preview("order-confirmed").channel()).isEqualTo("EMAIL");
    }
}
