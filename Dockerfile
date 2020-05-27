# JDK 8 + Maven 3.3.9
FROM maven:3.3.9-jdk-8

RUN mkdir -p /app
COPY target/*.jar /app
WORKDIR /app

RUN ls -la
# Http port
ENV PORT 9000
EXPOSE $PORT

# Executes spring boot's jar
CMD ["java", "-jar", "vulnerablejavawebapp-0.0.1-SNAPSHOT.jar"]
