package com.advancedorders.apigateway.security;

import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CourseRateLimiterTest {
    @Test
    void rejectsFourthRequestAndResetsAtWindowBoundary() {
        AtomicLong now = new AtomicLong();
        var limiter = new CourseRateLimiter(3, 10, now::get);
        for (int i = 0; i < 3; i++) {
            assertThat(limiter.acquire("reader").allowed()).isTrue();
        }
        var rejected = limiter.acquire("reader");
        assertThat(rejected.allowed()).isFalse();
        assertThat(rejected.retryAfterSeconds()).isEqualTo(10);
        assertThat(limiter.acquire("admin").allowed()).isTrue();
        now.set(9_500_000_000L);
        assertThat(limiter.acquire("reader").retryAfterSeconds()).isEqualTo(1);
        now.set(10_000_000_000L);
        assertThat(limiter.acquire("reader").allowed()).isTrue();
    }

    @Test
    void boundsCardinalityWithoutResettingExistingSubjects() {
        AtomicLong now = new AtomicLong();
        var limiter = new CourseRateLimiter(2, 10, now::get);
        for (int i = 0; i < 128; i++) {
            assertThat(limiter.acquire("subject-" + i).allowed()).isTrue();
        }
        assertThat(limiter.acquire("extra").allowed()).isFalse();
        assertThat(limiter.acquire("subject-0").allowed()).isTrue();
        assertThat(limiter.acquire("subject-0").allowed()).isFalse();
        now.set(10_000_000_000L);
        assertThat(limiter.acquire("extra").allowed()).isTrue();
    }

    @Test
    void rejectsInvalidConfiguration() {
        assertThatThrownBy(() -> new CourseRateLimiter(0, 10, System::nanoTime))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CourseRateLimiter(3, 61, System::nanoTime))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
