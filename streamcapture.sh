#!/bin/bash
######CONFIGURATION######

#Enter your streamers seperated by spaces.  If they have a space in their name, use quotes around their name.
twitchstreamers=(isthisrealvr Vrey Ikumi Ebiko sevy Miyunie__ MiruneMochi)
kickstreamers=(blu-haze VreyVrey MikaMoonlight roflgator itskxtlyn momocita zayi)

#Enter a list of games you want to monitor the streamers for seperated by spaces.  If there is a space in the name, use quotes around the name.
game=(VRChat ASMR)

#Do you only want to record if they are playing a specific game specified above? Set to 1 to enable game monitoring, or 0 to disable.
monitortwitchgame=1
monitorkickgame=1

#Do you want to stop recording if your streamer switches to a game not specified above?
stoptwitchrecord=1
stopkickrecord=1

#Destination path is where you'll save the recordings.  The authorization file is for your Twitch API credentials, and the configfile is where it'll save your bearer token once it authenticates.
destpath="/Drobo/Hareis"
authorizationfile="/root/Mango/.twitchcreds.conf"
configfile="/root/Mango/.twitchrecord.conf"

# We need curl-impersonate. Otherwise we fall back to legacy mode which is not ideal. Having this allows better episode naming.
curlimp="/opt/curl-impersonate/curl_chrome116"

# Do we want to enable logging?
logging=2 #Start/Stop/Errors/etc -- 0 = No Logging -- 1 = Standard Logging -- 2 = +Error Logging
debug=0 #Streamlink & ffmpeg output -- 0 = No Logging -- 1 = Streamlink & ffmpeg logging

######CONFIGURATION######

#DEFINE COLORS
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[96m'
NC='\e[0m'

fnLog(){
    # $1 = level (LOCAL,INFO,SUCCESS,WARN,STOP,ERROR), $2 = message
    local lvl="$1" msg="$2"
    local now; now="$(date)"
    case "$lvl" in
		LOCAL) echo -e "[${BLUE}*${NC}] ${BLUE}$now${NC} - $msg" ;;
		INFO) [ "${logging:-0}" -ge 1 ] && echo -e "[${BLUE}*${NC}] ${BLUE}$now${NC} - $msg" | tee -a "$destpath/logs/log.txt" ;;
        SUCCESS) [ "${logging:-0}" -ge 1 ] && echo -e "[${GREEN}+${NC}] ${BLUE}$now${NC} - $msg" | tee -a "$destpath/logs/log.txt" ;;
        WARN) [ "${logging:-0}" -ge 1 ] && echo -e "[${YELLOW}/${NC}] ${BLUE}$now${NC} - $msg" | tee -a "$destpath/logs/log.txt" ;;
        STOP) [ "${logging:-0}" -ge 1 ] && echo -e "[${RED}-${NC}] ${BLUE}$now${NC} - $msg" | tee -a "$destpath/logs/log.txt" ;;
        ERROR)  [ "${logging:-0}" -ge 2 ] && echo -e "[${RED}*${NC}] ${BLUE}$now${NC} - $msg"| tee -a "$destpath/logs/errlog.txt" ;;
    esac
}

fnDependencyCheck(){
	local missdep=0

	if [[ ! -d "$destpath" ]]; then
		fnLog "ERROR" "Destination path \"$destpath\" does not exist or is inaccessible."
		exit 1
	fi
	if [[ -d "$destpath" && ! -d "$destpath/logs" ]]; then
        mkdir "$destpath/logs"
		fnLog "ERROR" "Log directory does not exist... creating directory at \"$destpath/logs\""
	fi
	if [[ ! -x "$curlimp" ]]; then
		fnLog "ERROR" "${BLUE}curl-impersonate${NC} not found at ${RED}$curlimp${NC}"
		missdep=1
	fi
	if [[ ! $(command -v jq) ]]; then
		fnLog "ERROR" "${BLUE}jq${NC} not found!"
                missdep=1
    fi
	if [[ ! $(command -v screen) ]]; then
		fnLog "ERROR" "${BLUE}screen${NC} not found!"
		missdep=1
	fi
	if [[ ! $(command -v ffmpeg) ]]; then
		fnLog "ERROR" "${BLUE}ffmpeg${NC} not found!"
		missdep=1
    fi
	if [[ $(streamlink --can-handle-url https://www.kick.com/test) && ! $? == 0 ]]; then
		fnLog "ERROR" "streamlink ${BLUE}kick plugin${NC} not found!"
		missdep=1
	fi
	if [[ $missdep == 1 ]]; then
		echo -en "[${RED}-${NC}] "
		read -p "Dependencies missing... press any key to continue or ctrl+c to exit."
	fi
}

#Run a for loop on the streamers array so we can use multiple names to record.
fnStart(){
	if [[ -n "${twitchstreamers[*]}" ]]; then
		fnLog "LOCAL" "[${GREEN}---${NC}] Twitch: [${GREEN}---${NC}]"
		for streamer in "${twitchstreamers[@]}"; do
			unset kick
			twitch=1
			fnConfig
		done
	fi
	if [[ -n "${kickstreamers[*]}" ]]; then
		fnLog "LOCAL" "[${GREEN}---${NC}] Kick: [${GREEN}---${NC}]"
		for streamer in "${kickstreamers[@]}"; do
			unset twitch
			retry=0
			kick=1
			fnConfig
		done
	fi
}

#Check to see if the config file exists. If there are issues with it, the fnRequestTwitch will delete it and start over.
fnConfig(){
	if [[ ! -d "$destpath/$streamer" ]]; then
		mkdir "$destpath/$streamer"
	fi
	if [[ "$twitch" == 1 ]]; then
		service=Twitch
		if [[ -z $(screen -list | grep "$streamer-$service") && -f "$destpath/logs/$streamer-$service.lock" ]]; then
			fnLog "INFO" "${GREEN}$service:${NC} Unlocking ${BLUE}$streamer${NC}."
			rm "$destpath/logs/$streamer-$service.lock"
		fi
		if [[ ! -f "$authorizationfile" ]]; then
			fnLog "ERROR" "${RED}Twitch:${NC} Config file with authorization credentials missing!"
			touch "$authorizationfile"
			echo "clientid=" >> "$authorizationfile"
			echo "clientsecret=" >> "$authorizationfile"
			exit
		else
			source "$authorizationfile"
		fi
		if [[ -f "$configfile" ]]; then
			source "$configfile"
			fnRequestTwitch
		else
			fnAccessToken
		fi
	fi
	if [[ "$kick" == 1 ]]; then
		service=Kick
		if [[ -z $(screen -list | grep "$streamer-$service") && -f "$destpath/logs/$streamer-$service.lock" ]]; then
			if [[ $logging -ge 2 ]]; then
					fnLog "INFO" "${GREEN}$service:${NC} Unlocking ${BLUE}$streamer${NC}."
					fi
					rm "$destpath/logs/$streamer-$service.lock"
			fi
		fnRequestKick
	fi
}

#Request a new access token if the one from the config file can't be loaded or is expired.
fnAccessToken(){
	if [[ $(echo "$request" | jq -r .message) == "Malformed query params." ]]; then
		fnLog "ERROR" "${RED}Twitch:${NC} Streamer does not exist or another error has occured: $streamer"
		return
	fi
	if [[ -z "$request" || $(echo "$request" | jq -r '.error') != "null" || -z "$access_token" ]]; then
		#This is doing the oauth authentication and saving the bearer token that we receive to the config file.
		access_token=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$clientid&client_secret=$clientsecret" https://id.twitch.tv/oauth2/token | jq -r '.access_token')
		if [[ ${#access_token} == 30 ]]; then
			echo "access_token=$access_token" > "$configfile"
			fnLog "ERROR" "${RED}Twitch:${NC} Pulled new access token!"
		else
			fnLog "ERROR" "${RED}Twitch:${NC} Error pulling new access token. Check your API credentials! Token response: $access_token"
		fi
	fi
}

#Make a request to the Twitch API for the streamers information.
fnRequestTwitch(){
	request=$(curl -s -H "Client-Id: $clientid" -H "Authorization: Bearer $access_token" -X GET "https://api.twitch.tv/helix/streams?user_login=$streamer")
	if [[ $(echo "$request" | jq -r .message) == "Malformed query params." ]]; then
		fnLog "ERROR" "${RED}Twitch:${NC} Streamer does not exist or another error has occured: $streamer"
		return
	fi
	if [[ $(echo "$request" | jq -r '.error') != "null" || -z "$access_token" ]]; then
		#echo "Token Error: $(echo $request | jq -r '.error') ---- $access_token"
		unset access_token
		rm "$configfile"
		fnConfig
	elif [[ $(echo "$request" | jq -r .data[0].type) != "live" ]]; then
		#If the streamer is not live, we can skip the rest of the checks.
		fnLog "LOCAL" "${RED}Twitch:${NC} ${BLUE}$streamer${NC} is not live."
		unset twitch
		return
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink)  && $(echo "$request" | jq -r '.data[].type') == "live" ]] && [[ " ${game[*]} " =~ " $(echo "$request" | jq -r '.data[]?.game_name // null') " || "$monitortwitchgame" == 0 ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartTwitchRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) && $(echo "$request" | jq -r '.data[].type') == "live" && ! " ${game[*]} " =~ " $(echo "$request" | jq -r '.data[]?.game_name // null') " && "$stoptwitchrecord" == 1 && "$monitortwitchgame" == 1 ]]; then
		#If they change game and we have stop recording set, then stop recording.
		stopgame=$(echo "$request" | jq -r '.data[]?.game_name // null')
		fnStopRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) ]]; then
		fnLog "LOCAL" "${GREEN}Twitch:${NC} ${BLUE}$streamer${NC} is live in ${YELLOW}$(echo "$request" | jq -r '.data[]?.game_name // null')${NC} and we're already recording."
	elif [[ $(echo "$request" | jq -r '.data[].type') == "live" ]]; then
		fnLog "LOCAL" "${YELLOW}Twitch:${NC} ${BLUE}$streamer${NC} is live in ${RED}$(echo "$request" | jq -r '.data[]?.game_name // null')${NC} which is not in ${YELLOW}${game[*]}${NC}."
	else
		fnLog "LOCAL" "${RED}Twitch:${NC} ${BLUE}$streamer${NC} we shouldn't be here..."
	fi
	unset twitch
}

fnRequestKick(){
	request=$("$curlimp" -s "https://kick.com/api/v2/channels/$streamer")
	while [[ "$request" =~ "Just a moment..." && "${retry:-0}" -le 5 ]]; do
		fnLog "LOCAL" "${RED}Kick:${NC} ${BLUE}$streamer${NC}: Got CloudFlare response... trying again... $retry."
		request=$("$curlimp" -s "https://kick.com/api/v2/channels/$streamer")
		((retry++))
		sleep 1
		if [[ "$request" =~ "Just a moment..." && "${retry:-0}" -ge 5 ]]; then
			fnLog "ERROR" "${RED}Kick:${NC} ${BLUE}$streamer${NC}: Got CloudFlare response we're unable to bypass..."
			return
		fi
	done
	if [[ $(echo "$request" | jq -r '.livestream.is_live') != "true" ]]; then
		#If the streamer is not live, we can skip the rest of the checks.
		fnLog "LOCAL" "${RED}Kick:${NC} ${BLUE}$streamer${NC} is not live."
		unset kick
		return
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) && -z $(screen -list | grep "$streamer-$service") && $(echo "$request" | jq -r '.livestream.is_live') == "true" && -z $(streamlink --stream-url "https://kick.com/$streamer" | grep error) ]] && [[ " ${game[*]} " =~ " $(echo "$request" | jq -r '.livestream.categories[]?.name // null') " || "$monitorkickgame" == 0 ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartKickRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) && -n $(screen -list | grep "$streamer-$service") && $(echo "$request" | jq -r '.livestream.is_live') == "true" && ! " ${game[*]} " =~ " $(echo "$request" | jq -r '.livestream.categories[]?.name // null') " && "$stopkickrecord" == 1 && "$monitorkickgame" == 1 ]]; then
		#If they change game and we have stop recording set, then stop recording.
		stopgame=$(echo "$request" | jq -r '.livestream.categories[]?.name // null')
		fnStopRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) || -n $(screen -list | grep "$streamer-$service") ]]; then
		fnLog "LOCAL" "${GREEN}Kick:${NC} ${BLUE}$streamer${NC} is live in ${YELLOW}$(echo "$request" | jq -r '.livestream.categories[]?.name // null')${NC} and we're already recording."
	elif [[ $(echo "$request" | jq -r '.livestream.is_live') == "true" ]]; then
		fnLog "LOCAL" "${YELLOW}Kick:${NC} ${BLUE}$streamer${NC} is live in ${RED}$(echo "$request" | jq -r '.livestream.categories[]?.name // null')${NC} which is not in ${YELLOW}${game[*]}${NC}."
	else
		fnLog "LOCAL" "${RED}Kick:${NC} ${BLUE}$streamer${NC} we shouldn't be here..."
	fi
	unset kick
}

fnStartTwitchRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo "$request" | jq -j --arg jdate "$(date +%j)" --arg ydate "$(date +%y)" --arg random "$RANDOM" '.data[].user_login," - S",$ydate,"E",$jdate," - ",.data[].title," [",.data[].id + $random,"]"' | tr -dc '[:print:]' | tr -d '<>:"/\\|?*' | tr -s " ")
	fnLog "SUCCESS" "${GREEN}Twitch:${NC} Starting recording of ${BLUE}$streamer${NC} playing ${GREEN}$(echo "$request" | jq -r '.data[]?.game_name // null')${NC}. File name: ${YELLOW}$outputname.mp4${NC}"
	if [[ $debug -ge 1 ]]; then
		screen -dmS "$streamer-$service" -L -Logfile "$destpath/logs/$outputname.txt" bash -c "streamlink --stdout https://www.twitch.tv/$streamer best | ffmpeg -i - -movflags faststart -c copy \"$destpath/$streamer/$outputname.mp4\""
	else
		screen -dmS "$streamer-$service" bash -c "streamlink --stdout https://www.twitch.tv/$streamer best | ffmpeg -i - -movflags faststart -c copy \"$destpath/$streamer/$outputname.mp4\""
	fi
}

fnStartKickRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo "$request" | jq -j --arg jdate "$(date +%j)" --arg ydate "$(date +%y)" --arg random "$RANDOM" '.user.username," - S",$ydate,"E",$jdate," - ",.livestream.session_title," [",(.livestream.id|tostring) + $random,"]"' | tr -dc '[:print:]' | tr -d '<>:"/\\|?*' | tr -s " " )
	fnLog "SUCCESS" "${GREEN}Kick:${NC} Starting recording of ${BLUE}$streamer${NC} playing ${GREEN}$(echo "$request" | jq -r '.livestream.categories[]?.name // null')${NC}. File name: ${YELLOW}$outputname.mp4${NC}"
	if [[ $debug -ge 1 ]]; then
		screen -dmS "$streamer-$service" -L -Logfile "$destpath/logs/$outputname.txt" bash -c "streamlink --stdout https://www.kick.com/$streamer best | ffmpeg -i - -movflags faststart -c copy \"$destpath/$streamer/$outputname.mp4\""
	else
		screen -dmS "$streamer-$service" bash -c "streamlink --stdout https://www.kick.com/$streamer best | ffmpeg -i - -movflags faststart -c copy \"$destpath/$streamer/$outputname.mp4\""
	fi
}

fnStopRecord(){
	#This sends a ctrl+c (SIGINT) to the screen to gracefully stop the recording.
	if [[ ! -f "$destpath/logs/$streamer-$service.lock" ]]; then
		fnLog "INFO" "${GREEN}$service:${NC} Locking ${BLUE}$streamer${NC}."
		touch "$destpath/logs/$streamer-$service.lock"
		fnLog "STOP" "${GREEN}$service:${NC} Stopping recording of ${BLUE}$streamer${NC}. ${RED}$stopgame${NC} not in ${GREEN}${game[*]}${NC}."
		screen -S "$streamer-$service" -X stuff $'\003'
	else
		fnLog "INFO" "${GREEN}$service:${NC} ${YELLOW}Locked${NC}: Waiting for processing to finish for ${BLUE}$streamer${NC}."
	fi
}

fnDependencyCheck
fnStart
