#!/bin/bash

#set -x

#####    sudo apt -y install jq bc
#####    sudo apt -y install curl dirmngr apt-transport-https lsb-release ca-certificates && curl -sL https://deb.nodesource.com/setup_current.x | sudo -E bash -
#####    sudo apt update && sudo apt -y install nodejs
#####    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add - && echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
#####    sudo apt update && sudo apt install yarn
#####    sudo yarn global add @polkadot/api-cli

#####    CONFIG    ##################################################################################################
validatoraddress=""   # if left empty no validator checks are performed
socket="default"      # websocket for js-api, either 'default' or like 'ws://127.0.0.1:9944'
cli="polkadot-js-api" # js-api command
nodeip="auto"         # nodeip of the node for verifying heartbeat message, set to 'auto' autodiscovered for local ip,'off' for no checks
heartbeatoffset="8"   # the block interval following the expected heartbeat height after that a heartbeat must be received
logname=""            # a custom log file name can be chosen, if left empty default is nmon-<username>.log
logpath="$(pwd)"      # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200           # the max number of lines after that the log will be trimmed to reduce its size
sleep1=30s            # polls every sleep1 sec
colorI='\033[0;32m'   # black 30, red 31, green 32, yellow 33, blue 34, magenta 35, cyan 36, white 37
colorD='\033[0;90m'   # for light color 9 instead of 3
colorE='\033[0;31m'   #
colorW='\033[0;33m'   #
noColor='\033[0m'     # no color
#####  END CONFIG  ##################################################################################################

cli="timeout --kill-after=6 5 $cli" #using timeout for preventing deadlocks of the script
if [ "$socket" != "default" ]; then cli="$cli --ws $socket"; fi

apiversion=$($cli --version)
if [ -z $apiversion ]; then
   echo "please install the Polkadot JS-API"
   exit 1
fi

if [ "$nodeip" == "auto" ]; then myip=$(curl -s4 checkip.amazonaws.com); fi

chainid=$($cli rpc.system.chain | jq -r '.chain')
specVersion=$($cli query.system.lastRuntimeUpgrade | jq -r '.lastRuntimeUpgrade.specVersion')
localListenAddresses=$($cli rpc.system.localListenAddresses | jq -r '.localListenAddresses | @tsv')
#nextKeys=$($cli query.session.nextKeys $validatoraddress | jq -r '.nextKeys | @tsv' )

if [ -z $logname ]; then logname="nmon-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "js-api version: ${apiversion}"
echo "runtime version: ${specVersion}"
echo "websocket: ${socket}"
echo "validator address: ${validatoraddress}"
echo "listen addresses: ${localListenAddresses}"
echo "local ip: ${myip}"
echo "chain id: ${chainid}"
#echo "next keys: ${nextKeys}"

epochDuration=$($cli consts.babe.epochDuration | jq -r '.epochDuration')
expectedBlockTime=$($cli consts.babe.expectedBlockTime | jq -r '.expectedBlockTime')
expectedBlockTime=$(expr $(sed 's/,//g' <<<$expectedBlockTime) / 1000)
sessionsPerEra=$($cli consts.staking.sessionsPerEra | jq -r '.sessionsPerEra')

echo "epoch duration: ${epochDuration}"
echo "sessions per era: ${sessionsPerEra}"
echo "expected block time: ${expectedBlockTime}s"
echo ""

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(expr $nloglines - $logsize)d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=seconds)
echo "[${date}] status=scriptstarted chainid=$chainid" >>$logfile

while true; do
   logentry=""
   health=$($cli rpc.system.health)
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
      heightfromnow=$($cli query.timestamp.now | jq -r '.now')
      #heightHash=$($cli rpc.chain.getBlockHash $height | jq -r '.getBlockHash')
      #getBlock=$($cli rpc.chain.getBlock $heightHash | jq -r '.getBlock')
      #heightfromnow=$(jq -r '.block.extrinsics[0].method.args[0]' <<<$getBlock)
      heightfromnow=$(sed 's/,//g' <<<$heightfromnow)
      heightfromnow=$(echo "scale=0 ; $heightfromnow / 1000" | bc)
      syncState=$($cli rpc.system.syncState)
      height=$(jq -r '.syncState.currentBlock' <<<$syncState)
      height=$(sed 's/,//g' <<<$height)
      highestBlock=$(jq -r '.syncState.highestBlock' <<<$syncState)
      highestBlock=$(sed 's/,//g' <<<$highestBlock)
      behind=$(expr $highestBlock - $height)
      now=$(date --rfc-3339=seconds)
      elapsed=$(expr $(date +%s -d "$now") - $heightfromnow)
      if [ -n "$validatoraddress" ]; then
         sessionIndex=$($cli query.session.currentIndex | jq -r '.currentIndex')
         sessionIndex=$(sed 's/,//g' <<<$sessionIndex)
         activeEra=$($cli query.staking.activeEra | jq -r '.activeEra')
         currentEra=$(jq -r '.index' <<<$activeEra)
         currentEra=$(sed 's/,//g' <<<$currentEra)
         startEra=$(jq -r '.start' <<<$activeEra)
         startEra=$(sed 's/,//g' <<<$startEra)
         startEra=$(echo "scale=0 ; $startEra / 1000" | bc)
         pctEraElapsed=$(echo "scale=2 ; 100 * ($(date +%s) - $startEra) / ($epochDuration * $expectedBlockTime * $sessionsPerEra)" | bc)
         pctSessionElapsed=$(echo "scale=2 ; 100 * ($(date +%s) - $startEra) / ($epochDuration * $expectedBlockTime)" | bc)
         pctSessionElapsed=$(echo "scale=0 ; $pctSessionElapsed % 100" | bc)
         #keys=$(jq -r 'to_entries | map_values(.value + { index: .key })' <<<$(polkadot-js-api query.imOnline.keys | jq -r 'map({key: .[]})'))
         keys=$(jq -r 'to_entries | map_values(.value + { index: .key })' <<<$($cli query.session.validators | jq -r 'map({key: .[]})'))
         validatorInKeys=$(grep -c $validatoraddress <<<$keys)
         if [ "$validatorInKeys" == 0 ]; then
            isValidator="no"
            logentry="session=$sessionIndex isValidator=$isValidator pctSessionElapsed=$pctSessionElapsed era=$currentEra pctEraElapsed=$pctEraElapsed"
         else
            isValidator="yes"
            validatorKey=$(jq -r '.[] | select(.key == '\"$validatoraddress\"')' <<<$keys)
            validatorIndex=$(jq -r '.index' <<<$validatorKey)
            authoredBlocks=$($cli query.imOnline.authoredBlocks $sessionIndex $validatoraddress | jq -r '.authoredBlocks')
            heartbeatAfter_=$($cli query.imOnline.heartbeatAfter)
            if [ -n "$heartbeatAfter_" ]; then
               heartbeatAfter=$(jq -r '.heartbeatAfter' <<<$heartbeatAfter_)
               heartbeatAfter=$(sed 's/,//g' <<<$heartbeatAfter)
            fi
            heartbeatDelta=$(expr $highestBlock - $heartbeatAfter)
            if [ "$heartbeatDelta" -gt "$heartbeatoffset" ]; then
               heartbeat=missing
               receivedHeartbeats=$($cli query.imOnline.receivedHeartbeats $sessionIndex $validatorIndex | jq -r '.receivedHeartbeats')
               if [ "$receivedHeartbeats" != "null" ]; then
                  heartbeat=ok
                  receivedHeartbeats="$(echo $receivedHeartbeats | xxd -r -p | tr -d '\0')"
               fi
               if [ "$nodeip" != "off" ]; then
                  test=$(grep -c $myip <<<$receivedHeartbeats)
                  if [ "$test" == "0" ]; then heartbeat=missing_ip; fi
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
      logentry="[$now] status=$status height=$height elapsed=$elapsed behind=$behind peers=$peers $logentry"
      echo "$logentry" >>$logfile
   else
      now=$(date --rfc-3339=seconds)
      status=error
      logentry="[$now] status=$status"
      echo "$logentry" >>$logfile
   fi

   nloglines=$(wc -l <$logfile)
   if [ $nloglines -gt $logsize ]; then sed -i '1d' $logfile; fi

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
   if [ $behind -gt 0 ]; then lagging=yes; else lagging=no; fi
   case $lagging in
   yes)
      color=$colorW
      ;;
   esac
   case $heartbeat in
   missing | missing_ip)
      color=$colorW
      ;;
   esac

   logentry="$(sed 's/[^ ]*[\=]/'\\${color}'&'\\${noColor}'/g' <<<$logentry)"
   echo -e $logentry
   echo -e "${colorD}sleep ${sleep1}${noColor}"
   sleep $sleep1
done
