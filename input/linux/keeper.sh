#!/bin/bash
KEEPER_UID=keeper.uid
AGGREGATE=300
INTERVAL=1
URL=https://keeper.sofialondonmoskva.com
declare -A DATA

function send_data() {
        json=()
        for app in "${!DATA[@]}"; do
                seconds="${DATA[$app]}"
                json+="\"$app\":$seconds"
                unset DATA["$app"]
        done
        x=$(printf ",%s" "${json[@]}")
        encoded="{${x:1}}"
        curl -X POST -k -d "$encoded" $URL/$(cat $KEEPER_UID)/input/$(date +%s) 2>/dev/null
}
test -f $KEEPER_UID || {
        curl -k $URL/generate/uid/ > $KEEPER_UID 2>/dev/null || { 
                echo "failed to generate UID" && exit 1
        }
}

echo productivity report url: $URL/$(cat $KEEPER_UID)/report/
i=0
while :; do
        i=$(($i + 1))
        if [ $(($i % AGGREGATE)) -eq 0 ]; then
                send_data
        fi
        key=$(cat /proc/$(xprop -id $(xprop -root _NET_ACTIVE_WINDOW | cut -d ' ' -f 5) _NET_WM_PID | cut -f 3 -d ' ')/comm | tr '[A-Z]' '[a-z]')
	#key=$(cat /proc/$(xdotool getwindowpid $(xdotool getwindowfocus))/comm | tr '[A-Z]' '[a-z]')
        if [ ${#key} -gt 1 ]; then
                test ${DATA[$key]+_} || DATA[$key]=0
                DATA[$key]=$((${DATA[$key]} + $INTERVAL))
        fi
        sleep $INTERVAL
done
