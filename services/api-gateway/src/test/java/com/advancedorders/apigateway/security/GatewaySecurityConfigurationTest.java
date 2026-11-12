package com.advancedorders.apigateway.security;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import static org.assertj.core.api.Assertions.assertThat;

class GatewaySecurityConfigurationTest {
    @Test
    void mapsKeycloakRealmRolesAndScopesToDistinctAuthorities() {
        Jwt jwt = Jwt.withTokenValue("synthetic-test-token")
                .header("alg", "RS256")
                .subject("demo-user")
                .claim("realm_access", Map.of("roles", List.of("orders-reader", "platform-admin")))
                .claim("scope", "openid orders.read")
                .build();
        List<String> authorities = GatewaySecurityConfiguration.realmAndScopeAuthorities(jwt)
                .map(GrantedAuthority::getAuthority)
                .collectList().block();
        assertThat(authorities)
                .contains("ROLE_orders-reader", "ROLE_platform-admin", "SCOPE_orders.read");
    }

    @Test
    void missingRolesDoNotGrantPrivilegedAccess() {
        Jwt jwt = Jwt.withTokenValue("synthetic-test-token")
                .header("alg", "RS256")
                .subject("demo-user")
                .claim("scope", "openid")
                .build();
        List<String> authorities = GatewaySecurityConfiguration.realmAndScopeAuthorities(jwt)
                .map(GrantedAuthority::getAuthority)
                .collectList().block();
        assertThat(authorities).doesNotContain("ROLE_platform-admin", "ROLE_orders-reader");
    }
}
