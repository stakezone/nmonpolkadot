#!/bin/bash

#set -x # for debugging

###    if suppressing error messages is preferred, run as './nmon.sh 2> /dev/null'
###    when using Zabbix please use LOGROTATION option 1 or 2

###    sudo apt -y install jq bc
###    sudo apt -y install curl dirmngr apt-transport-https lsb-release ca-certificates && curl -sL https://deb.nodesource.com/setup_current.x | sudo -E bash -
###    sudo apt update && sudo apt -y install nodejs
###    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add - && echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
###    sudo apt update && sudo apt install yarn
###    sudo yarn global add @polkadot/api-cli

###    CONFIG    ##################################################################################################
VALIDATORADDRESS=""   # if left empty no validator checks are performed
SOCKET="default"      # websocket for js-api, either 'default' or like 'ws://127.0.0.1:9944'
CLI="polkadot-js-api" # js-api command
SLEEP1="30s"          # polls every SLEEP1 sec
IP="auto"             # configured ip for verifying heartbeat message, can also be 'auto' for local ip,'off' for no checks
HEARTBEATOFFSET="8"   # the block interval following the expected heartbeat height after that a heartbeat must be received
LAGBEHIND="1"         # threshold lag for behind for printing output in colorW
LAGFINALIZATION="4"   # threshold lag for finalization for printing output in colorW
LOGNAME=""            # a custom log file name can be chosen, if left empty default is 'nmon-<username>.log'
LOGPATH="$(pwd)"      # the directory where the log file is stored, for customization insert path like: '/my/path'
LOGSIZE="200"         # the max number of lines after that the log gets rotated or truncated to reduce its size
LOGROTATION="1"       # options for log rotation: (1) rotate to $LOGNAME.1 every $LOGSIZE lines;  (2) append to $LOGNAME.1 every $LOGSIZE lines; (3) truncate $logfile to $LOGSIZE every iteration
### internal:         #
colorI='\033[0;32m'   # black 30, red 31, green 32, yellow 33, blue 34, magenta 35, cyan 36, white 37
colorD='\033[0;90m'   # for light color 9 instead of 3
colorE='\033[0;31m'   #
colorW='\033[0;33m'   #
noColor='\033[0m'     # no color
###  END CONFIG  ##################################################################################################

CLI="timeout -k 6 5 $CLI" # using timeout for preventing deadlocks of the script

if [ "$SOCKET" != "default" ]; then CLI="$CLI --ws $SOCKET"; fi

apiversion=$($CLI --version)
if [ -z "$apiversion" ]; then
    echo "please install the Polkadot JS-API"
    exit 1
fi

if [ "$IP" == "auto" ]; then
    myip=$(curl -s4 checkip.amazonaws.com)
    if [ -z "$myip" ]; then
        echo "auto discovery of ip failed, try again or configure manually..."
        exit 1
    fi
fi

chainid=$($CLI rpc.system.chain | jq -r '.chain')
#specVersion=$($CLI query.system.lastRuntimeUpgrade | jq -r '.lastRuntimeUpgrade.specVersion')
version=$($CLI rpc.system.version | jq -r '.version')
localListenAddresses=$($CLI rpc.system.localListenAddresses | jq -r '.localListenAddresses | @tsv')
#nextKeys=$($CLI query.session.nextKeys $VALIDATORADDRESS | jq -r '.nextKeys | @tsv' )

if [ -z "$LOGNAME" ]; then LOGNAME="nmon-${USER}.log"; fi
logfile="${LOGPATH}/${LOGNAME}"
touch $logfile

echo "log file: ${logfile}"
echo "js-api version: ${apiversion}"
#echo "runtime version: ${specVersion}"
echo "implementation: ${version}"
echo "websocket: ${SOCKET}"
echo "validator address: ${VALIDATORADDRESS}"
echo "listen addresses: ${localListenAddresses}"
echo "configured ip: ${myip}"
echo "chain id: ${chainid}"
#echo "next keys: ${nextKeys}"

epochDuration=$($CLI consts.babe.epochDuration | jq -r '.epochDuration')
epochDuration=$(sed 's/,//g' <<<$epochDuration)
expectedBlockTime=$($CLI consts.babe.expectedBlockTime | jq -r '.expectedBlockTime')
expectedBlockTime=$(expr $(sed 's/,//g' <<<$expectedBlockTime) / 1000)
sessionsPerEra=$($CLI consts.staking.sessionsPerEra | jq -r '.sessionsPerEra')

echo "epoch duration: ${epochDuration}"
echo "sessions per era: ${sessionsPerEra}"
echo "expected block time: ${expectedBlockTime}s"
echo ""

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $LOGSIZE ]; then sed -i "1,$(expr $nloglines - $LOGSIZE)d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=seconds)
echo "[${date}] status=scriptstarted chainid=$chainid" >>$logfile

while true; do
    logentry=""
    health=$($CLI rpc.system.health)
    peers=$(jq -r '.health.peers' <<<$health)
    isSyncing=$(jq -r '.health.isSyncing' <<<$health)
    shouldHavePeers=$(jq -r '.health.shouldHavePeers' <<<$health)
    if [[ $shouldHavePeers = true ]]; then
        if [[ $peers -gt 0 ]] && [[ $isSyncing = false ]]; then status="synced"; fi
        if [[ $isSyncing = true ]]; then status="catchingup"; fi
    else
        status="error"
    fi
    if [ "$status" != "error" ]; then
        elapsed=$($CLI query.timestamp.now | jq -r '.now')
        #heightHash=$($CLI rpc.chain.getBlockHash $height | jq -r '.getBlockHash')
        #getBlock=$($CLI rpc.chain.getBlock $heightHash | jq -r '.getBlock')
        #elapsed=$(jq -r '.block.extrinsics[0].method.args[0]' <<<$getBlock)
        elapsed=$(sed 's/,//g' <<<$elapsed)
        elapsed=$(echo "scale=0 ; $elapsed / 1000" | bc)
        sessionIndex=$($CLI query.session.currentIndex | jq -r '.currentIndex')
        sessionIndex=$(sed 's/,//g' <<<$sessionIndex)
        finalizedHead=$($CLI rpc.chain.getFinalizedHead | jq -r '.getFinalizedHead')
        finalized=$($CLI rpc.chain.getBlock $finalizedHead | jq -r '.getBlock')
        finalized=$(jq -r '.block.header.number' <<<$finalized)
        finalized=$(sed 's/,//g' <<<$finalized)
        finalization=$(expr $highestBlock - $finalized)
        syncState=$($CLI rpc.system.syncState)
        height=$(jq -r '.syncState.currentBlock' <<<$syncState)
        height=$(sed 's/,//g' <<<$height)
        highestBlock=$(jq -r '.syncState.highestBlock' <<<$syncState)
        highestBlock=$(sed 's/,//g' <<<$highestBlock)
        behind=$(expr $highestBlock - $height)
        now=$(date --rfc-3339=seconds)
        elapsed=$(expr $(date +%s -d "$now") - $elapsed)
        if [ -n "$VALIDATORADDRESS" ]; then
            activeEra=$($CLI query.staking.activeEra | jq -r '.activeEra')
            currentEra=$(jq -r '.index' <<<$activeEra)
            currentEra=$(sed 's/,//g' <<<$currentEra)
            startEra=$(jq -r '.start' <<<$activeEra)
            startEra=$(sed 's/,//g' <<<$startEra)
            startEra=$(echo "scale=0 ; $startEra / 1000" | bc)
            pctEraElapsed=$(echo "scale=2 ; 100 * ($(date +%s) - $startEra) / ($epochDuration * $expectedBlockTime * $sessionsPerEra)" | bc)
            pctSessionElapsed=$(echo "scale=2 ; 100 * ($(date +%s) - $startEra) / ($epochDuration * $expectedBlockTime)" | bc)
            pctSessionElapsed=$(echo "scale=0 ; $pctSessionElapsed % 100" | bc)
            #keys=$(jq -r 'to_entries | map_values(.value + { index: .key })' <<<$(polkadot-js-api query.imOnline.keys | jq -r 'map({key: .[]})'))
            keys=$(jq -r 'to_entries | map_values(.value + { index: .key })' <<<$($CLI query.session.validators | jq -r 'map({key: .[]})'))
            validatorInKeys=$(grep -c $VALIDATORADDRESS <<<$keys)
            if [ "$validatorInKeys" == 0 ]; then
                isValidator="no"
                logentry="isValidator=$isValidator pctSessionElapsed=$pctSessionElapsed era=$currentEra pctEraElapsed=$pctEraElapsed"
            else
                isValidator="yes"
                validatorKey=$(jq -r '.[] | select(.key == '\"$VALIDATORADDRESS\"')' <<<$keys)
                validatorIndex=$(jq -r '.index' <<<$validatorKey)
                authoredBlocks=$($CLI query.imOnline.authoredBlocks $sessionIndex $VALIDATORADDRESS | jq -r '.authoredBlocks')
                heartbeatAfter_=$($CLI query.imOnline.heartbeatAfter)
                if [ -n "$heartbeatAfter_" ]; then
                    heartbeatAfter=$(jq -r '.heartbeatAfter' <<<$heartbeatAfter_)
                    heartbeatAfter=$(sed 's/,//g' <<<$heartbeatAfter)
                fi
                heartbeatDelta=$(expr $highestBlock - $heartbeatAfter)
                if [ "$heartbeatDelta" -gt "$HEARTBEATOFFSET" ]; then
                    heartbeat=missing
                    receivedHeartbeats=$($CLI query.imOnline.receivedHeartbeats $sessionIndex $validatorIndex | jq -r '.receivedHeartbeats')
                    if [ "$receivedHeartbeats" != "null" ]; then
                        heartbeat=ok
                        receivedHeartbeats="$(echo $receivedHeartbeats | xxd -r -p | tr -d '\0')"
                        if [ "$IP" != "off" ]; then
                            test=$(grep -c $myip <<<$receivedHeartbeats)
                            if [ "$test" == "0" ]; then heartbeat=ipmissing; fi
                        fi
                    fi
                    if [ "$authoredBlocks" -gt "0" ]; then
                        heartbeat=ok
                    fi
                else
                    heartbeat="waiting"
                fi
                logentry="session=$sessionIndex isValidator=$isValidator authoredBlocks=$authoredBlocks heartbeat=$heartbeat pctSessionElapsed=$pctSessionElapsed era=$currentEra pctEraElapsed=$pctEraElapsed"
            fi
        fi
        variables="status=$status height=$height elapsed=$elapsed behind=$behind finalization=$finalization peers=$peers session=$sessionIndex $logentry"
    else
        now=$(date --rfc-3339=seconds)
        status="error"
        variables="status=$status"
    fi

    logentry="[$now] $variables"
    echo "$logentry" >>$logfile

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $LOGSIZE ]; then
        case $LOGROTATION in
        1)
            mv $logfile "${logfile}.1"
            touch $logfile
            ;;
        2)
            echo "$(cat $logfile)" >>${logfile}.1
            >$logfile
            ;;
        3)
            sed -i '1d' $logfile
            if [ -f ${logfile}.1 ]; then rm ${logfile}.1; fi # no log rotation with option (3)
            ;;
        *) ;;

        esac
    fi

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $LOGSIZE ]; then sed -i '1d' $logfile; fi

    case $status in
    synced)
        color=$colorI
        ;;
    error)
        color=$colorE
        ;;
    catchingup)
        color=$colorW
        ;;
    *)
        color=$noColor
        ;;
    esac

    if [[ $behind -ge $LAGBEHIND ]] || [[ $finalization -ge $LAGFINALIZATION ]]; then lagging=yes; else lagging=no; fi
    case $lagging in
    yes)
        color=$colorW
        ;;
    esac

    case $heartbeat in
    missing | ipmissing)
        color=$colorW
        ;;
    esac

    logentry="$(sed 's/[^ ]*[\=]/'\\${color}'&'\\${noColor}'/g' <<<$logentry)"
    echo -e $logentry
    echo -e "${colorD}sleep ${SLEEP1}${noColor}"

    variables_=""
    for var in $variables; do
        var_=$(grep -Po '^[0-9a-zA-Z_-]*' <<<$var)
        var_="$var_=\"\""
        variables_="$var_; $variables_"
    done
    #echo $variables_
    eval $variables_

    sleep $SLEEP1
done
