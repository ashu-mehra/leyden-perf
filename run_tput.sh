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

get_tput_results() {
  local tput_log_file=$1
  local stats_dir=$2
  if [ ! -f ${tput_log_file} ]; then
    error "jmeter throughput file ${tput_log_file} not found."
    exit 1
  fi
  create_dir ${stats_dir}

  awk '/summary \+/' ${tput_log_file} > ${stats_dir}/tputlines
  awk '{ print $5 }' ${stats_dir}/tputlines > ${stats_dir}/jmeter.time
  awk -F ":" 'BEGIN { total=0 } { total += $3; print total }' ${stats_dir}/jmeter.time > ${stats_dir}/time.tmp
  awk '{ print $7 }' ${stats_dir}/tputlines | cut -d '/' -f 1 > ${stats_dir}/rampup
  tail -n 20 ${stats_dir}/rampup > ${stats_dir}/rampup.last2mins

  echo "time,tput" > ${stats_dir}/rampup.csv
  paste -d "," ${stats_dir}/time.tmp ${stats_dir}/rampup >> ${stats_dir}/rampup.csv
  rm -f ${stats_dir}/jmeter.time ${stats_dir}/time.tmp

  avg_tput=`awk '/summary =/{ print $7 }' ${tput_log_file} | tail -n 1 | cut -d '/' -f 1`
  avg_tput_last2min=`cat ${stats_dir}/rampup.last2mins | awk 'BEGIN{sum=0}{sum += $1}END{print sum/NR}'`
  peak_tput=`cat ${stats_dir}/rampup | sort -n | tail -n 1`
  peak_tput_last2min=`cat ${stats_dir}/rampup.last2mins | sort -n | tail -n 1`

  echo "Overall Avg tput: ${avg_tput}" | tee -a ${stats_file}
  echo "Overall Peak tput: ${peak_tput}" | tee -a ${stats_file}
  echo "Avg tput (last 2 mins): ${avg_tput_last2min}" | tee  -a ${stats_file}
  echo "Peak tput (last 2 mins): ${peak_tput_last2min}" | tee  -a ${stats_file}
}

prereqs

source ./utils.sh

#===============================
# Baseline run with 1 jmeter thread
#===============================
test_prereqs
echo
log "Baseline run with 1 jmeter thread"
CONFIG="baseline"
RESULTS_DIR="${APP_NAME}/${CONFIG}/tput-t1"
cleanup_dir ${RESULTS_DIR}
create_dir ${RESULTS_DIR}
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.log"
JVM_OPTIONS="-Xlog:cds -XX:SharedArchiveFile=${BASELINE_DYNAMIC_CDS_NAME}"
start_app
JMETER_THREADS=1
LOAD_DURATION=300
JMETER_LOG_FILE="${RESULTS_DIR}/jmeter.log"
generate_load
stop_app
get_tput_results "${JMETER_LOG_FILE}" "${RESULTS_DIR}/tput"

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
# AOT run with 1 jmeter thread
#===============================
test_prereqs
echo
log "AOT run with 1 jmeter thread"
CONFIG="aot"
RESULTS_DIR="${APP_NAME}/${CONFIG}/tput-t1"
cleanup_dir ${RESULTS_DIR}
create_dir ${RESULTS_DIR}
APP_LOG_FILE="${RESULTS_DIR}/${APP_NAME}.log"
JVM_OPTIONS="-Xlog:cds -XX:SharedArchiveFile=${TRAINING_DYNAMIC_CDS_NAME} -XX:+ReplayTraining -XX:+LoadCachedCode -XX:CachedCodeFile=${SCA_NAME}"
start_app
JMETER_THREADS=1
LOAD_DURATION=300
JMETER_LOG_FILE="${RESULTS_DIR}/jmeter.log"
generate_load
stop_app
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

