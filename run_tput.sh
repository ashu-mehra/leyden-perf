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
  if [ -z "${JMETER_HOME}" ]; then
    echo "env var JMETER_HOME must be set"
    exit 1
  fi
}

prereqs

source ./utils.sh

#===============================
# Baseline run with a warmup phase and 10 jmeter threads
#===============================
test_prereqs
echo
log "Baseline run with a warmup phase and 10 jmeter threads"
CONFIG="baseline"
RESULTS_DIR="${APP_NAME}/${CONFIG}/tput-t10"
cleanup_dir ${RESULTS_DIR}
create_dir ${RESULTS_DIR}
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.log"
JVM_OPTIONS="-Xlog:cds -XX:SharedArchiveFile=${BASELINE_DYNAMIC_CDS_NAME}"
start_app
JMETER_WARMUP_LOG_FILE="${RESULTS_DIR}/jmeter.warmup.log"
warmup
JMETER_THREADS=10
LOAD_DURATION=300
JMETER_LOG_FILE="${RESULTS_DIR}/jmeter.log"
generate_load
stop_app
get_tput_results "${JMETER_WARMUP_LOG_FILE}" "${RESULTS_DIR}/warmup"
get_tput_results "${JMETER_LOG_FILE}" "${RESULTS_DIR}/tput"

#===============================
# AOT run with a warmup phase and 10 jmeter threads
#===============================
test_prereqs
echo
log "AOT run with a warmup phase and 10 jmeter threads"
CONFIG="aot"
RESULTS_DIR="${APP_NAME}/${CONFIG}/tput-t10"
cleanup_dir ${RESULTS_DIR}
create_dir ${RESULTS_DIR}
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.log"
JVM_OPTIONS="-Xlog:cds -XX:SharedArchiveFile=${TRAINING_DYNAMIC_CDS_NAME} -XX:+ReplayTraining -XX:+LoadCachedCode -XX:CachedCodeFile=${SCA_NAME}"
start_app
JMETER_WARMUP_LOG_FILE="${RESULTS_DIR}/jmeter.warmup.log"
warmup
JMETER_THREADS=10
LOAD_DURATION=300
JMETER_LOG_FILE="${RESULTS_DIR}/jmeter.log"
generate_load
stop_app
get_tput_results "${JMETER_WARMUP_LOG_FILE}" "${RESULTS_DIR}/warmup"
get_tput_results "${JMETER_LOG_FILE}" "${RESULTS_DIR}/tput"

