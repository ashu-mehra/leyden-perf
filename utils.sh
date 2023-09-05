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

