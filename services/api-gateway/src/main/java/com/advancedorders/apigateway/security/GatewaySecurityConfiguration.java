package com.advancedorders.apigateway.security;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.convert.converter.Converter;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.security.oauth2.server.resource.authentication.ReactiveJwtAuthenticationConverter;
import org.springframework.security.web.server.SecurityWebFilterChain;
import reactor.core.publisher.Flux;

@Configuration
@EnableWebFluxSecurity
public class GatewaySecurityConfiguration {

    /**
     * P00–P04 are unchanged when the security profile is not enabled.
     * Do not treat this baseline configuration as production security.
     */
    @Bean
    @ConditionalOnProperty(prefix = "course.security", name = "enabled",
            havingValue = "false", matchIfMissing = true)
    SecurityWebFilterChain baselineSecurity(ServerHttpSecurity http) {
        return http.csrf(ServerHttpSecurity.CsrfSpec::disable)
                .authorizeExchange(exchanges -> exchanges.anyExchange().permitAll())
                .build();
    }

    /**
     * P05 validates the JWT signature, issuer, timestamps and required audience
     * via Spring Security's resource server configuration. HTTP routes are then
     * authorized by Keycloak realm roles, not by blindly decoding JWT payloads.
     */
    @Bean
    @ConditionalOnProperty(prefix = "course.security", name = "enabled",
            havingValue = "true")
    SecurityWebFilterChain p05Security(ServerHttpSecurity http) {
        ReactiveJwtAuthenticationConverter converter = new ReactiveJwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(GatewaySecurityConfiguration::realmAndScopeAuthorities);

        return http.csrf(ServerHttpSecurity.CsrfSpec::disable)
                .authorizeExchange(exchanges -> exchanges
                        .pathMatchers(HttpMethod.GET, "/actuator/health/**").permitAll()
                        .pathMatchers(HttpMethod.GET, "/api/orders/preview")
                            .hasAnyAuthority("ROLE_orders-reader", "ROLE_platform-admin")
                        .pathMatchers(HttpMethod.GET, "/api/payments/methods")
                            .hasAuthority("ROLE_platform-admin")
                        .pathMatchers(HttpMethod.GET, "/api/shipping/**")
                            .hasAnyAuthority("ROLE_orders-reader", "ROLE_platform-admin")
                        .pathMatchers(HttpMethod.GET, "/api/inventory/**")
                            .hasAnyAuthority("ROLE_orders-reader", "ROLE_platform-admin")
                        .pathMatchers(HttpMethod.GET, "/api/notifications/**")
                            .hasAuthority("ROLE_platform-admin")
                        .anyExchange().denyAll())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt ->
                        jwt.jwtAuthenticationConverter(converter)))
                .build();
    }

    static Flux<GrantedAuthority> realmAndScopeAuthorities(Jwt jwt) {
        List<GrantedAuthority> grants = new ArrayList<>();
        JwtGrantedAuthoritiesConverter scopes = new JwtGrantedAuthoritiesConverter();
        Collection<GrantedAuthority> scopeGrants = scopes.convert(jwt);
        if (scopeGrants != null) {
            grants.addAll(scopeGrants);
        }

        Map<String, Object> realm = jwt.getClaimAsMap("realm_access");
        if (realm != null && realm.get("roles") instanceof Collection<?> roles) {
            for (Object role : roles) {
                if (role instanceof String name && !name.isBlank()) {
                    grants.add(new SimpleGrantedAuthority("ROLE_" + name));
                }
            }
        }
        return Flux.fromIterable(grants);
    }
}
