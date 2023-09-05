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
  [ -z "${STARTUP_ITERATIONS}" ] && STARTUP_ITERATIONS=1
}

get_startup_time() {
  if [ ! -f ${APP_LOG_FILE} ]; then
    error "Application log file ${APP_LOG_FILE} not found."
    exit 1
  fi
  grep -o "Started PetClinicApplication in [[:digit:]]\+\.[[:digit:]]\+ seconds" ${APP_LOG_FILE} | cut -d ' ' -f 4 >> ${RESULTS_DIR}/startup
}

prereqs

source ./utils.sh

CONFIG="baseline"
RESULTS_DIR="${APP_NAME}/${CONFIG}/startup"
cleanup_dir ${RESULTS_DIR}
CONFIG="aot"
RESULTS_DIR="${APP_NAME}/${CONFIG}/startup"
cleanup_dir ${RESULTS_DIR}

for i in `seq 1 ${STARTUP_ITERATIONS}`; do
  #===============================
  # Baseline
  #===============================

  test_prereqs
  echo
  log "Baseline (iteration:${i})"
  CONFIG="baseline"
  RESULTS_DIR="${APP_NAME}/${CONFIG}/startup"
  APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}-${i}.log"
  JVM_OPTIONS="-Xlog:cds -XX:SharedArchiveFile=${BASELINE_DYNAMIC_CDS_NAME}"
  create_dir ${RESULTS_DIR}
  start_app
  stop_app
  get_startup_time

  #===============================
  # AOT run
  #===============================
  test_prereqs
  echo
  log "AOT (iteration:${i})"
  CONFIG="aot"
  RESULTS_DIR="${APP_NAME}/${CONFIG}/startup"
  APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}-${i}.log"
  JVM_OPTIONS="-Xlog:cds -XX:SharedArchiveFile=${TRAINING_DYNAMIC_CDS_NAME} -XX:+ReplayTraining -XX:+LoadCachedCode -XX:CachedCodeFile=${SCA_NAME}"
  create_dir ${RESULTS_DIR}
  start_app
  stop_app
  get_startup_time
done
