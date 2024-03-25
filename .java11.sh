#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
echo "JAVA_HOME is now $JAVA_HOME"
export PATH=$JAVA_HOME/bin:$PATH
cat ~/.gradle/gradle.properties.shared > ~/.gradle/gradle.properties
cat ~/.gradle/gradle.properties.java11 >> ~/.gradle/gradle.properties

