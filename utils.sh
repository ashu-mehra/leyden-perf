#!/bin/bash

log() {
  ts=`date +%T`
  echo "$ts::$*"
}

error() {
  ts=`date +%T`
  echo "$ts::ERROR::$*"
}

cleanup_dir() {
  local dir=$1
  log "Removing ${dir}"
  rm -fr ${dir}
}

create_dir() {
  local dir=$1
  if [ ! -d ${dir} ]; then
    log "Creating directory ${dir}"
    mkdir -p ${dir}
  fi
}

clear_os_caches() {
  # clear OS caches
  sync && sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
}

test_prereqs() {
  clear_os_caches
}

check_app_started() {
  local counter=0
  local max_iterations=${STARTUP_TIMEOUT}
  while [ "${counter}" -lt "${max_iterations}" ];
  do
    grep "${STARTUP_KEYWORD}" ${APP_LOG_FILE} &> /dev/null
    if [ $? -eq "0" ]; then
      return 0
    fi
    sleep 1s
    counter=$(( $counter+1 ))
  done
  return 1
}

check_existing_app() {
  pid=`${JAVA_HOME}/bin/jcmd | grep "${APP_JAR}" | awk '{ print $1 }'`
  if [ ! -z ${pid} ]; then
    error "App (pid: ${pid}) is already running. Stop it first."
    exit 1
  fi
}

launch_app() {
  log "Command: $@"
  taskset -c "${APP_CPUS}" $@ &> ${APP_LOG_FILE} &
}

start_app() {
  check_existing_app
  log "Launching application now"
  launch_app ${JAVA_HOME}/bin/java ${JVM_OPTIONS} -jar ${APP_JAR}
  sleep 1s
  APP_PID=`${JAVA_HOME}/bin/jcmd | grep "${APP_JAR}" | awk '{ print $1 }'`
  if [ ! -z "${STARTUP_KEYWORD}" ]; then
    check_app_started
    local rc=$?
    if [ ${rc} -ne "0" ];
    then
      error "Application is taking too long to startup...Exiting"
      exit 1
    fi
  fi
  grep "The shared archive file was created by a different version or build of HotSpot" ${APP_LOG_FILE} &> /dev/null
  if [ $? -eq "0" ]; then
    # Unable to use specified CDS archive file
    error "Failed to use CDS archive file"
    stop_app
    exit 1
  fi
}

stop_app() {
  if [ "${STOP_COMMAND}" = "kill" ]; then
    log "Stopping app: kill ${APP_PID}"
    kill ${APP_PID} &> /dev/null
  else
    log "Stopping app: ${STOP_COMMAND}"
    ${STOP_COMMAND} &> /dev/null
  fi
  sleep 5s
}

generate_load() {
  if [ ! -f ${TEST_PLAN} ]; then
    error "Test plan ${TEST_PLAN} not found."
    exit 1
  fi
  log "Starting load for ${LOAD_DURATION} seconds with ${JMETER_THREADS} threads"
  taskset -c ${LOAD_GENERATOR_CPUS} ${JMETER_HOME}/bin/jmeter -JDURATION=${LOAD_DURATION} -JTHREADS=${JMETER_THREADS} -Dsummariser.interval=6 -n -t ${TEST_PLAN} | tee ${JMETER_LOG_FILE}
}

warmup() {
  if [ ! -f ${TEST_PLAN} ]; then
    error "Test plan ${TEST_PLAN} not found."
    exit 1
  fi
  WARMUP_JMETER_THREADS=1
  WARMUP_LOAD_DURATION=180
  log "Starting warmup for ${WARMUP_LOAD_DURATION} seconds with ${WARMUP_JMETER_THREADS} threads"
  taskset -c ${LOAD_GENERATOR_CPUS} ${JMETER_HOME}/bin/jmeter -JDURATION=${WARMUP_LOAD_DURATION} -JTHREADS=${WARMUP_JMETER_THREADS} -Dsummariser.interval=6 -n -t ${TEST_PLAN} | tee ${JMETER_WARMUP_LOG_FILE}
}

# $1=jmeter log file that stores throughput
# $2=directory for storing stats files generated by this function
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

APP_NAME="spring"
CDS_ARTIFACT="archives/${APP_NAME}"
STATIC_CDS_NAME="${CDS_ARTIFACT}/${APP_NAME}-static.jsa"
BASELINE_DYNAMIC_CDS_NAME="${CDS_ARTIFACT}/${APP_NAME}-dynamic-baseline.jsa"
TRAINING_DYNAMIC_CDS_NAME="${CDS_ARTIFACT}/${APP_NAME}-dynamic-training.jsa"
SCA_NAME="${CDS_ARTIFACT}/${APP_NAME}-dynamic.jsa-sc"

STARTUP_TIMEOUT=60
STARTUP_KEYWORD="Started PetClinicApplication"
STOP_COMMAND="curl -X POST localhost:8080/actuator/shutdown"

TEST_PLAN="petclinic_test_plan.jmx"

APP_CPUS="18,19" # eg 0-4 or 0,1
LOAD_GENERATOR_CPUS="16,17" # eg 0-4 or 0,1

if [ -z "${APP_CPUS}" ]; then
  echo "APP_CPUS should not be empty. Set it in utils.sh"
  exit 1;
fi
if [ -z "${LOAD_GENERATOR_CPUS}" ]; then
  echo "LOAD_GENERATOR_CPUS should not be empty. Set it in utils.sh"
  exit 1;
fi

