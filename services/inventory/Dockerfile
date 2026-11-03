# Build from repository root:
# docker build -f services/inventory/Dockerfile -t advancedorders/inventory:0.1.0 .
FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./pom.xml
COPY services/inventory/pom.xml services/inventory/pom.xml
COPY services/orders/pom.xml services/orders/pom.xml
COPY services/inventory/src services/inventory/src
RUN mvn -pl services/inventory -am package -DskipTests

FROM eclipse-temurin:21-jre
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 appuser
WORKDIR /app
COPY --from=build /workspace/services/inventory/target/inventory-*.jar /app/app.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
