#!/bin/sh

openssl x509 -outform der -in /app/cassandrapem -out /app/cassandra.der

openssl genrsa -des3 -passout pass:x -out server.pass.key 2048
openssl rsa -passin pass:x -in server.pass.key -out server.key
rm server.pass.key
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/ST=California/L=Mountain View/O=Intuit/OU=QBSE/CN=intuit.com"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

keytool -import -alias CassandraSSL -keystore /usr/java/latest/jre/lib/security/cacerts -file /app/cassandra.der -noprompt -storepass changeit

mv /tmp/truststore /dev/shm/truststore/truststore
mv /tmp/Intuit.sbg.qbse.aws.jks /dev/shm/Intuit.sbg.qbse.aws.jks
mv /tmp/Intuit.cto.gateway.aws.jks /dev/shm/Intuit.cto.gateway.aws.jks

mv /tmp/stunnel.conf /etc/stunnel/stunnel.conf
mv /tmp/stunnel.pem /etc/stunnel/stunnel.pem




if [ -f /etc/secrets/application.properties ]; then
  JAVA_OPTS="${JAVA_OPTS} -Dspring.config.location=/etc/secrets/application.properties"
fi

if [ -n "${APP_ENV}" ]; then
  JAVA_OPTS="${JAVA_OPTS} -Dspring.profiles.active=${APP_ENV} -DenableConsoleAppender=TRUE -DdeployType=iks -Denv=${APP_ENV}"
fi

JAVA_OPTS="${JAVA_OPTS} -XX:+UnlockExperimentalVMOptions \
  -XX:+UseG1GC -XX:+UseStringDeduplication \
  -XX:+UseCGroupMemoryLimitForHeap \
  -XX:MaxRAMFraction=2 \
  -XshowSettings:vm"

# Is contrast enabled, yes or no
contrastassess_enabled=no
# ENV for controst assessment
contrastassess_env=qal
contrastassess_jar="/app/contrast/javaagent/contrast.jar"
if [ "${contrastassess_enabled}" = "yes" ] && [ "${APP_ENV}" = "${contrastassess_env}" ]; then
  JAVA_OPTS="${JAVA_OPTS} -javaagent:${contrastassess_jar}"
  JAVA_OPTS="${JAVA_OPTS} -Dcontrast.dir=/app/contrast/agents"
  JAVA_OPTS="${JAVA_OPTS} -Dcontrast.properties=/app/contrast/javaagent/contrast.conf"
fi

appdynamics_jar="/app/appdynamics/javaagent.jar"
if [[ -r ${appdynamics_jar} && -f /etc/secrets/appd-account-access-key ]]; then

    export APPDYNAMICS_CONTROLLER_PORT=443
    export APPDYNAMICS_CONTROLLER_SSL_ENABLED=true

    export APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY=`cat /etc/secrets/appd-account-access-key`

    JAVA_OPTS="$JAVA_OPTS -javaagent:${appdynamics_jar}"
    JAVA_OPTS="$JAVA_OPTS -Dappdynamics.agent.applicationName=${L1}-${L2}-${APP_NAME}-${APP_ENV}"
    JAVA_OPTS="$JAVA_OPTS -Dappdynamics.agent.tierName=${APPDYNAMICS_AGENT_TIER_NAME}"
    JAVA_OPTS="$JAVA_OPTS -Dappdynamics.agent.nodeName=${APPDYNAMICS_AGENT_TIER_NAME}_${HOSTNAME}"
fi

java $JAVA_OPTS -jar /app/sbg-integrations-app.jar
