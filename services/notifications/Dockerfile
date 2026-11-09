# Build context: repository root
FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./pom.xml
COPY services/inventory/pom.xml services/inventory/pom.xml
COPY services/orders/pom.xml services/orders/pom.xml
COPY services/payments/pom.xml services/payments/pom.xml
COPY services/shipping/pom.xml services/shipping/pom.xml
COPY services/notifications/pom.xml services/notifications/pom.xml
COPY services/api-gateway/pom.xml services/api-gateway/pom.xml
COPY services/notifications/src services/notifications/src
RUN mvn -B -pl services/notifications -am package -DskipTests

FROM eclipse-temurin:21-jre
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 appuser
WORKDIR /app
COPY --from=build /workspace/services/notifications/target/notifications-*.jar /app/app.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70.0", "-jar", "/app/app.jar"]
