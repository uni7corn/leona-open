plugins {
    `java-library`
    `maven-publish`
}

group = "io.leonasec"
version = "0.0.0-v0.4-skeleton"

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
    withSourcesJar()
    withJavadocJar()
}

publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            from(components["java"])
            artifactId = "leona-java-server-wrapper"
            pom {
                name.set("Leona Java Server Wrapper")
                description.set("Public-safe Leona server-side wrapper skeleton. Evidence only; customer backend owns business decisions.")
                url.set("https://github.com/zedbully/leona-open")
                licenses {
                    license {
                        name.set("Apache License, Version 2.0")
                        url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                    }
                }
                scm {
                    url.set("https://github.com/zedbully/leona-open")
                    connection.set("scm:git:https://github.com/zedbully/leona-open.git")
                    developerConnection.set("scm:git:https://github.com/zedbully/leona-open.git")
                }
            }
        }
    }
}

tasks.withType<Javadoc>().configureEach {
    (options as StandardJavadocDocletOptions).addStringOption("Xdoclint:none", "-quiet")
}
