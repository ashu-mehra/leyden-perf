#!/bin/bash

prereqs() {
  if [ -z "$JAVA_HOME" ]; then
    echo "env var JAVA_HOME must be set"
    exit 1
  fi
  if [ -z "$APP_JAR" ]; then
    echo "env var APP_JAR must be set"
    exit 1
  fi
}

prereqs

source ./utils.sh

#===============================
# Define all the variables here
#===============================

RESULTS_DIR="${CDS_ARTIFACT}"
cleanup_dir ${RESULTS_DIR}
create_dir ${RESULTS_DIR}

#==============================
# Steps for creating the cds and shared-code archives
#==============================

log "Step 1: Dump classlist"
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.s1.log"
JVM_OPTIONS="-Xshare:off -XX:DumpLoadedClassList=${CDS_ARTIFACT}/${APP_NAME}.classlist"
start_app
stop_app

sleep 1s

log "Step 2: Create Static archive"
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.s2.log"
JVM_OPTIONS="-Xshare:dump -XX:SharedArchiveFile=${STATIC_CDS_NAME} -XX:SharedClassListFile=${CDS_ARTIFACT}/${APP_NAME}.classlist -Xlog:cds=debug,cds+class=debug,cds+resolve=debug:file=${CDS_ARTIFACT}/${APP_NAME}-static.dump.log::filesize=0"
launch_app ${JAVA_HOME}/bin/java ${JVM_OPTIONS} -jar ${APP_JAR}

sleep 5s

log "Step 3: Create Dynamic archive without training data for baseline"
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.s3.log"
JVM_OPTIONS="-XX:SharedArchiveFile=${STATIC_CDS_NAME} -XX:ArchiveClassesAtExit=${BASELINE_DYNAMIC_CDS_NAME} -Xlog:cds=debug,cds+class=debug:file=${CDS_ARTIFACT}/${APP_NAME}-dynamic-baseline.dump.log::filesize=0"
start_app
stop_app

sleep 5s

log "Step 4: Create Dynamic archive with training data running with static archive"
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.s4.log"
JVM_OPTIONS="-XX:SharedArchiveFile=${STATIC_CDS_NAME} -XX:ArchiveClassesAtExit=${TRAINING_DYNAMIC_CDS_NAME} -XX:+RecordTraining -Xlog:cds=debug,cds+class=debug:file=${CDS_ARTIFACT}/${APP_NAME}-dynamic-training.dump.log::filesize=0"
start_app
stop_app

sleep 5s

log "Step 5: Generate Shared Code archive"
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.s5.log"
JVM_OPTIONS="-XX:SharedArchiveFile=${TRAINING_DYNAMIC_CDS_NAME} -XX:CachedCodeFile=${SCA_NAME} -XX:+ReplayTraining -XX:+StoreCachedCode -Xlog:scc*=trace:file=${CDS_ARTIFACT}/${APP_NAME}-store-sc.log::filesize=0"
start_app
stop_app

sleep 5s
