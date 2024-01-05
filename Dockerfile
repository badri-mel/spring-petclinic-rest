FROM --platform=linux/amd64 eclipse-temurin:17-jdk-jammy

WORKDIR /app

COPY .mvn/ .mvn
COPY mvnw pom.xml ./
RUN ./mvnw dependency:resolve

COPY src ./src
EXPOSE 9966
CMD ["./mvnw", "spring-boot:run"]
