#!/bin/bash
######CONFIGURATION######

#Enter your streamers seperated by spaces.  If they have a space in their name, use quotes around their name.
twitchstreamers=(crazymango_vr aeriytheneko isthisrealvr Vrey blu_haze Ikumi)
kickstreamers=(CrazyMangoVR blu-haze VreyVrey MikaMoonlight roflgator)

#Enter a list of games you want to monitor the streamers for seperated by spaces.  If there is a space in the name, use quotes around the name.
monitortwitchgame=1
monitorkickgame=0
game=(VRChat ASMR)

#Do you want to stop recording if your streamer switches games?
stoptwitchrecord=1
stopkickrecord=0

#Destination path is where you'll save the recordings.  The authorization file is for your Twitch API credentials, and the configfile is where it'll save your bearer token once it authenticates.
destpath="/Drobo/Hareis"
authorizationfile="/root/Mango/.twitchcreds.conf"
configfile="/root/Mango/.twitchrecord.conf"

# Do we want to use the kick "API".  If so, we need curl-impersonate. Otherwise fall back to legacy mode. Having this enabled allows better episode naming.
kickapi=1
curlimp="/opt/curl-impersonate/curl_ff109"

# Do we want to enable logging?
logging=1
debug=0

######CONFIGURATION######

#DEFINE COLORS
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[96m'
NC='\e[0m'

fnDependencyCheck(){
	if [[ $kickapi = 1 && ! -f $curlimp ]]; then
		echo -e "[${RED}-${NC}] ${BLUE}curl-impersonate${NC} not found at ${RED}$curlimp${NC}"
		missdep=1
	fi
	if [[ ! -f $(which jq) ]]; then
		echo -e "[${RED}-${NC}] ${BLUE}jq${NC} not found!"
                missdep=1
        fi
	if [[ $(streamlink --can-handle-url https://www.kick.com/test) && $? == 1 ]]; then
	        echo -e "[${RED}-${NC}] streamlink ${BLUE}kick plugin${NC} not found!"
        	missdep=1
        fi
	if [[ ! -d $destpath ]]; then
		echo -e "[${RED}-${NC}] Destination path \"$destpath\" does not exist or is inaccessible."
		missdep=1
	fi
	if [[ ! -d $destpath/logs ]]; then
		echo -e "[${YELLOW}/${NC}] Log directory does not exist... creating directory at \"$destpath/logs\""
		mkdir $destpath/logs
	fi
	if [[ $missdep == 1 ]]; then
		echo -en "[${RED}-${NC}] "
		read -p "Dependencies missing... press any key to continue or ctrl+c to exit."
	fi
}

#Run a for loop on the streamers array so we can use multiple names to record.
fnStart(){
	if [[ -n ${twitchstreamers[@]} ]]; then
		echo -e "[${GREEN}---${NC}] Twitch: [${GREEN}---${NC}]"
		for streamer in "${twitchstreamers[@]}"; do
			unset kick
			twitch=1
			fnConfig
		done
	fi
	if [[ -n ${kickstreamers[@]} ]]; then
		echo -e "[${GREEN}---${NC}] Kick: [${GREEN}---${NC}]"
		for streamer in "${kickstreamers[@]}"; do
			unset twitch
			kick=1
			fnConfig
		done
	fi
}

#Check to see if the config file exists. If there are issues with it, the fnRequestTwitch will delete it and start over.
fnConfig(){
	if [[ ! -d $destpath/$streamer ]]; then
		mkdir $destpath/$streamer
	fi
	if [[ $twitch == 1 ]]; then
		if [[ ! -f $authorizationfile ]]; then
			echo -e "[${RED}-${NC}] ${BLUE}$(date)${NC} - ${RED}Twitch:${NC} Config file with authorization credentials missing!" |  tee -a $destpath/logs/log.txt
			touch $authorizationfile
			echo "clientid=" >> $authorizationfile
			echo "clientsecret=" >> $authorizationfile
			exit
		else
			source $authorizationfile
		fi
		if [[ -f $configfile ]]; then
			source $configfile
			fnRequestTwitch
		else
			fnAccessToken
		fi
	fi
	if [[ $kick == 1 && $kickapi == 1 ]]; then
		request=$($curlimp -s "https://kick.com/kick-token-provider" | jq -r '.enabled')
		if [[ $request == "true" ]]; then
			fnRequestKick
		else
			echo -e "[${RED}-${NC}] ${BLUE}$(date)${NC} - ${RED}Kick:${NC} Unable to make API connection to Kick... falling back to legacy recording." | tee -a $destpath/logs/log.txt
			kickapi=0
			fnKickRecordLegacy
		fi
	elif [[ $kick == 1 ]]; then
		fnKickRecordLegacy
	fi
}

#Request a new access token if the one from the config file can't be loaded or is expired.
fnAccessToken(){
	if [[ -z $request || $(echo $request | jq -r '.error') != "null" || -z $access_token ]]; then
		#This is doing the oauth authentication and saving the bearer token that we receive to the config file.
		access_token=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$clientid&client_secret=$clientsecret" https://id.twitch.tv/oauth2/token | jq -r '.access_token')
		if [[ $(echo $access_token | wc -c) == 31 ]]; then
			echo "access_token=$access_token" > $configfile
			echo -e "[${GREEN}+${NC}] ${BLUE}$(date)${NC} - ${GREEN}Twitch:${NC} Pulled new access token!" | tee -a $destpath/logs/log.txt
		else
			echo -e "[${RED}-${NC}] ${BLUE}$(date)${NC} - ${RED}Twitch:${NC} Error pulling new access token. Check your API credentials! Token response: $access_token" | tee -a $destpath/logs/log.txt
		fi
	fi
}

#Make a request to the Twitch API for the streamers information.
fnRequestTwitch(){
	request=$(curl -s -H "Client-Id: $clientid" -H "Authorization: Bearer $access_token" -X GET "https://api.twitch.tv/helix/streams?user_login=$streamer")
	if [[ $(echo $request | jq -r '.error') != "null" || -z $access_token ]]; then
		#echo "Token Error: $(echo $request | jq -r '.error') ---- $access_token"
		unset access_token
		rm $configfile
		fnConfig
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink)  && $(echo $request | jq -r '.data[].type') == "live" ]] && [[ " ${game[@]} " =~ " $(echo $request | jq -r '.data[]?.game_name // null') " || $monitortwitchgame == 0 ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartTwitchRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) && $(echo $request | jq -r '.data[].type') == "live" && ! " ${game[@]} " =~ " $(echo $request | jq -r '.data[]?.game_name // null') " && $stoptwitchrecord == 1 && $monitortwitchgame == 1 ]]; then
		#If they change game and we have stop recording set, then stop recording.
		stopgame=$(echo $request | jq -r '.data[]?.game_name // null')
		fnStopRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) ]]; then
		echo -e "[${GREEN}+${NC}] ${GREEN}Twitch:${NC} ${BLUE}$streamer${NC} is live in ${YELLOW}$(echo $request | jq -r '.data[]?.game_name // null')${NC} and we're already recording."
	elif [[ $(echo $request | jq -r '.data[].type') == "live" ]]; then
		echo -e "[${YELLOW}/${NC}] ${YELLOW}Twitch:${NC} ${BLUE}$streamer${NC} is live in ${RED}$(echo $request | jq -r '.data[]?.game_name // null')${NC} which is not in ${YELLOW}${game[@]}${NC}."
	else
		echo -e "[${RED}-${NC}] ${RED}Twitch:${NC} ${BLUE}$streamer${NC} is not live."
	fi
	unset twitch
}

fnRequestKick(){
	request=$($curlimp -s "https://kick.com/api/v2/channels/$streamer")
	if [[ ! $(echo $request | grep "user_id" ) ]]; then
		echo -e "[${RED}-${NC}] ${BLUE}$(date)${NC} - ${RED}Kick:${NC} ${BLUE}$streamer${NC}: Something happened to your streamer... they don't exist or the site is blocking your requests.  Falling back to legacy recording to see if they're live." | tee -a $destpath/logs/log.txt
		fnKickRecordLegacy
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) && $(echo $request | jq -r '.livestream.is_live') == "true" ]] && [[ " ${game[@]} " =~ " $(echo $request | jq -r '.livestream.categories[]?.name // null') " || $monitorkickgame == 0 ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartKickRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) && $(echo $request | jq -r '.livestream.is_live') == "true" && ! " ${game[@]} " =~ " $(echo $request | jq -r '.livestream.categories[]?.name // null') " && $stopkickrecord == 1 && $monitorkickgame == 1 ]]; then
		#If they change game and we have stop recording set, then stop recording.
		stopgame=$(echo $request | jq -r '.livestream.categories[]?.name // null')
		fnStopRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) ]]; then
		echo -e "[${GREEN}+${NC}] ${GREEN}Kick:${NC} ${BLUE}$streamer${NC} is live in ${YELLOW}$(echo $request | jq -r '.livestream.categories[]?.name // null')${NC} and we're already recording."
	elif [[ $(echo $request | jq -r '.livestream.is_live') == "true" ]]; then
		echo -e "[${YELLOW}/${NC}] ${YELLOW}Kick:${NC} ${BLUE}$streamer${NC} is live in ${RED}$(echo $request | jq -r '.livestream.categories[]?.name // null')${NC} which is not in ${YELLOW}${game[@]}${NC}."
	else
		echo -e "[${RED}-${NC}] ${RED}Kick:${NC} ${BLUE}$streamer${NC} is not live."
	fi
	unset kick
}

fnStartTwitchRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo $request | jq -j --arg jdate $(date +"%j") --arg ydate $(date +"%y") --arg random $RANDOM '.data[].user_login," - S",$ydate,"E",$jdate," - ",.data[].title," [",.data[].id + $random,"]"' | tr -dc '[:print:]' | tr -d '<>:"/\\|?*' | tr -s " ")
	if [[ $logging = 1 ]]; then
		echo -e "[${GREEN}+${NC}] ${BLUE}$(date)${NC} - ${GREEN}Twitch:${NC} Starting recording of ${BLUE}$streamer${NC} playing ${GREEN}$(echo $request | jq -r '.data[]?.game_name // null')${NC}. File name: ${YELLOW}$outputname.mp4${NC}" | tee -a $destpath/logs/log.txt
		screen -dmS $streamer -L -Logfile "$destpath/logs/$outputname.txt" bash -c "streamlink --stdout https://www.twitch.tv/$streamer best | ffmpeg -i - -c copy \"$destpath/$streamer/$outputname.mp4\""
	else
		screen -dmS $streamer bash -c "streamlink --stdout https://www.twitch.tv/$streamer best | ffmpeg -i - -c copy \"$destpath/$streamer/$outputname.mp4\""
	fi
}

fnStartKickRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo $request | jq -j --arg jdate $(date +"%j") --arg ydate $(date +"%y") --arg random $RANDOM '.user.username," - S",$ydate,"E",$jdate," - ",.livestream.session_title," [",(.livestream.id|tostring) + $random,"]"' | tr -dc '[:print:]' | tr -d '<>:"/\\|?*' | tr -s " " )
        if [[ $logging = 1 ]]; then
		echo -e "[${GREEN}+${NC}] ${BLUE}$(date)${NC} - ${GREEN}Kick:${NC} Starting recording of ${BLUE}$streamer${NC} playing ${GREEN}$(echo $request | jq -r '.livestream.categories[]?.name // null')${NC}. File name: ${YELLOW}$outputname.mp4${NC}" | tee -a $destpath/logs/log.txt
		screen -dmS $streamer -L -Logfile "$destpath/logs/$outputname.txt" bash -c "streamlink --stdout https://www.kick.com/$streamer best | ffmpeg -i - -c copy \"$destpath/$streamer/$outputname.mp4\""
	else
		screen -dmS $streamer bash -c "streamlink --stdout https://www.kick.com/$streamer best | ffmpeg -i - -c copy \"$destpath/$streamer/$outputname.mp4\""
	fi
}

fnKickRecordLegacy(){
	# We're basically skipping all checks of if someone is online or not and just brute forcing trying to record.  If they're not online it'll just error out.
	outputname="$streamer - S$(date +"%y")E$(date +"%j") - $RANDOM"
	if [[ -z $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) ]]; then
		echo -e "[${YELLOW}/${NC}] ${YELLOW}Kick:${NC} Legacy Mode - ${BLUE}$streamer${NC}"
		if [[ $debug = 1 ]]; then
			screen -dmS $streamer -L -Logfile "$destpath/logs/$outputname.txt" bash -c "streamlink --output \"$destpath/{author}/{title} {id}.mp4\" https://www.kick.com/$streamer best"
		else
			screen -dmS $streamer bash -c "streamlink --output \"$destpath/{author}/{title} {id}.mp4\" https://www.kick.com/$streamer best"
		fi
	fi
}

fnStopRecord(){
	#This sends a ctrl+c (SIGINT) to the screen to gracefully stop the recording.
        if [[ $logging = 1 ]]; then
		echo -e "[${RED}-${NC}] ${BLUE}$(date)${NC} - Stopping recording of ${BLUE}$streamer${NC}. ${RED}$stopgame${NC} not in ${GREEN}${game[@]}${NC}." | tee -a $destpath/logs/log.txt
	fi
	screen -S $streamer -X stuff $'\003'
}

fnDependencyCheck
fnStart
