FROM amazoncorretto:25 AS build
RUN yum install -y tar gzip && yum clean all
WORKDIR /app
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline -q
COPY src/ src/
RUN ./mvnw package -DskipTests -q

FROM amazoncorretto:25
WORKDIR /app
COPY --from=build /app/target/external-service-*.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "app.jar"]
