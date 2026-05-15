#!/bin/bash
#Version 1.0.0

######CONFIGURATION######

#Enter your streamers seperated by spaces.  If they have a space in their name, use quotes around their name.
twitchstreamers=(isthisrealvr Vrey Ikumi Miyunie__ MiruneMochi CatMomTM lilah sevy)
kickstreamers=(blu-haze VreyVrey MikaMoonlight roflgator itskxtlyn momocita zayi)

#Enter a list of games you want to monitor the streamers for seperated by spaces.  If there is a space in the name, use quotes around the name.
game=(VRChat ASMR)

#Destination path is where you'll save the recordings.
destpath="/Drobo/Hareis"
#authorizationfile stores credentials for both Twitch and Kick.
authorizationfile="/root/Mango/.streamcreds.conf"
#configfile stores access tokens for both Twitch and Kick.
configfile="/root/Mango/.streamtokens.conf"
#status_file is where we store the current status of each streamer for the dashboard to read from. It will be created automatically if it doesn't exist.
status_name="status.json"
#Set to 1 to enable the dashboard, or 0 to disable.  Dashboard will be available at http://localhost:8080 when enabled.
dashboard=1

#Do you only want to record if they are playing a specific game specified above? Set to 1 to enable game monitoring, or 0 to disable.
monitortwitchgame=1
monitorkickgame=1

#Do you want to stop recording if your streamer switches to a game not specified above?
stoptwitchrecord=1
stopkickrecord=1

# Do we want to enable logging?
logging=2 #Start/Stop/Errors/etc -- 0 = No Logging -- 1 = Standard Logging -- 2 = +Error Logging -- 3 = +Verbose Logging
debug=0 #Streamlink & ffmpeg output -- 0 = No Logging -- 1 = Streamlink & ffmpeg logging

######CONFIGURATION######

# Convert streamer names to lowercase for consistency with API responses
twitchstreamers=("${twitchstreamers[@],,}")
kickstreamers=("${kickstreamers[@],,}")

# Get the absolute path to the status file in the Dashboard directory relative to the script's location. This ensures that the script can be run from any working directory and still find the status file correctly.
status_file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/Dashboard/$status_name"

#DEFINE COLORS
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[96m'
NC='\e[0m'

fnLog(){
    # $1 = level (LOCAL,VERBOSE,INFO,SUCCESS,WARN,STOP,ERROR), $2 = message
    local level="$1" message="$2"
    local now="$(date)"
    case "$level" in
        LOCAL) echo -e "[${BLUE}*${NC}] ${BLUE}$now${NC} - $message" ;;
        VERBOSE)  (( logging >= 3 )) && echo -e "[${BLUE}*${NC}] ${BLUE}$now${NC} - $message" ;;
        INFO) (( logging >= 1 )) && echo -e "[${BLUE}*${NC}] ${BLUE}$now${NC} - $message" | tee -a "$destpath/logs/log.txt" ;;
        SUCCESS) (( logging >= 1 )) && echo -e "[${GREEN}+${NC}] ${BLUE}$now${NC} - $message" | tee -a "$destpath/logs/log.txt" ;;
        WARN) (( logging >= 1 )) && echo -e "[${YELLOW}/${NC}] ${BLUE}$now${NC} - $message" | tee -a "$destpath/logs/log.txt" ;;
        STOP) (( logging >= 1 )) && echo -e "[${RED}-${NC}] ${BLUE}$now${NC} - $message" | tee -a "$destpath/logs/log.txt" ;;
        ERROR)  (( logging >= 2 )) && echo -e "[${RED}*${NC}] ${BLUE}$now${NC} - $message" | tee -a "$destpath/logs/errlog.txt" ;;
    esac
}

fnDependencyCheck(){
    local missdep=0

    if [[ ! -d "$destpath" ]]; then
        fnLog "LOCAL" "Destination path \"$destpath\" does not exist or is inaccessible."
        exit 1
    fi
    if [[ -d "$destpath" && ! -d "$destpath/logs/debug" ]]; then
        mkdir -p "$destpath/logs/debug"
        fnLog "LOCAL" "Log directory does not exist... creating directory at \"$destpath/logs\""
    fi
    if [[ ! $(command -v jq) ]]; then
        fnLog "LOCAL" "${BLUE}jq${NC} not found!"
                missdep=1
    fi
    if [[ ! $(command -v curl) ]]; then
        fnLog "LOCAL" "${BLUE}curl${NC} not found!"
        missdep=1
    fi
    if [[ ! $(command -v cmp) ]]; then
        fnLog "LOCAL" "${BLUE}cmp${NC} not found!"
        missdep=1
    fi
    if [[ ! $(command -v screen) ]]; then
        fnLog "LOCAL" "${BLUE}screen${NC} not found!"
        missdep=1
    fi
    if [[ ! $(command -v ffmpeg) ]]; then
        fnLog "LOCAL" "${BLUE}ffmpeg${NC} not found!"
        missdep=1
    fi
    if [[ ! $(command -v streamlink) ]]; then
        fnLog "LOCAL" "${BLUE}streamlink${NC} not found!"
        missdep=1
    fi
    if [[ $missdep == 1 ]]; then
        echo -en "[${RED}-${NC}] "
        read -rsp "Dependencies missing... press ENTER key to continue or CTRL+C to exit."
    fi
}

#Run a batch request for Twitch streamers and a batch request for Kick streamers
fnStart(){
    fnPruneStatusFile
    fnStartDashboard
    if [[ -n "${twitchstreamers[*]}" ]]; then
        fnLog "LOCAL" "[${GREEN}---${NC}] Twitch: [${GREEN}---${NC}]"
        # Check authorization and get token before batch request
        if [[ ! -f "$authorizationfile" ]]; then
            fnLog "ERROR" "${RED}Twitch:${NC} Config file with authorization credentials missing!"
            touch "$authorizationfile"
            cat > "$authorizationfile" <<EOF
twitch_clientid=
twitch_clientsecret=
kick_clientid=
kick_clientsecret=
EOF
            exit
        else
            source "$authorizationfile"
        fi
        if [[ -f "$configfile" ]]; then
            source "$configfile"
        fi
        fnCheckAccessToken "Twitch" "$configfile" "$authorizationfile" "twitch_clientid" "twitch_clientsecret" "https://id.twitch.tv/oauth2/token" "twitch_access_token" "twitch_access_token_expires_at"
        fnRequestTwitchBatch
    fi
    if [[ -n "${kickstreamers[*]}" ]]; then
        fnLog "LOCAL" "[${GREEN}---${NC}] Kick: [${GREEN}---${NC}]"
        if [[ ! -f "$authorizationfile" ]]; then
            fnLog "ERROR" "${RED}Kick:${NC} Config file with authorization credentials missing!"
            touch "$authorizationfile"
            cat > "$authorizationfile" <<EOF
twitch_clientid=
twitch_clientsecret=
kick_clientid=
kick_clientsecret=
EOF
            exit
        else
            source "$authorizationfile"
        fi
        if [[ -f "$configfile" ]]; then
            source "$configfile"
        fi
        fnCheckAccessToken "Kick" "$configfile" "$authorizationfile" "kick_clientid" "kick_clientsecret" "https://id.kick.com/oauth/token" "kick_access_token" "kick_access_token_expires_at"
        fnRequestKickBatch
    fi
}

### Dashboard functions below, start functions above ###

fnCheckAccessToken(){
    local provider="$1"
    local configfile_path="$2"
    local authfile_path="$3"
    local client_id_var="$4"
    local client_secret_var="$5"
    local token_url="$6"
    local access_token_var="$7"
    local expires_at_var="$8"

	#Check that all required variable names are provided.
    if [[ -z "$client_id_var" || -z "$client_secret_var" || -z "$access_token_var" || -z "$expires_at_var" ]]; then
        fnLog "ERROR" "${RED}$provider:${NC} fnCheckAccessToken called with missing variable names"
        return
    fi

	#This uses indirect variable expansion to get the values of the client ID, client secret, access token, and expiration time based on the variable names passed in. This allows us to use the same function for both Twitch and Kick without hardcoding variable names.
    local client_id="${!client_id_var}"
    local client_secret="${!client_secret_var}"
    local access_token="${!access_token_var}"
    local access_token_expires_at="${!expires_at_var}"

	#Check if client ID and secret are set based on the above variable expansion. If not, log an error and return.
    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        fnLog "ERROR" "${RED}$provider:${NC} Missing $client_id_var or $client_secret_var in $authfile_path"
        return
    fi

	#Check if we have a valid access token that isn't close to expiring. If we do, we can just return and use the existing token. If not, we need to request a new one.
    if [[ -n "$access_token" && -n "$access_token_expires_at" ]] && (( $(date +%s) < access_token_expires_at )); then
        return
    fi

    local response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        "$token_url")

    access_token=$(echo "$response" | jq -r '.access_token // empty')
    local expires_in=$(echo "$response" | jq -r '.expires_in // 0')

    if [[ -n "$access_token" ]]; then
        local expires_at=$(( $(date +%s) + expires_in - 30 ))
        eval "$access_token_var=\"$access_token\""
        eval "$expires_at_var=$expires_at"
        cat > "$configfile_path" <<EOF
twitch_access_token="${twitch_access_token:-}"
twitch_access_token_expires_at=${twitch_access_token_expires_at:-0}
kick_access_token="${kick_access_token:-}"
kick_access_token_expires_at=${kick_access_token_expires_at:-0}
EOF
        fnLog "ERROR" "${GREEN}$provider:${NC} Pulled new access token!"
    else
        fnLog "ERROR" "${RED}$provider:${NC} Failed to obtain access token: $(echo "$response" | jq -r '.error_description // .error // "unknown error"')"
    fi
}

fnUpdateStreamerStatus(){
    local name="$1"
    local platform="$2"
    local is_live="$3"
    local game_name="$4"
    local title="$5"
    local viewer_count="$6"
    local recording="$7"
    local filename="$8"

    if [[ "$is_live" != "live" && "$is_live" != "true" ]]; then
        is_live="false"
        game_name=""
        title=""
        recording="false"
        filename=""
    else
        is_live="true"
    fi

    if [[ "$recording" != "true" ]]; then
        recording="false"
    fi

    local tmpfile
    tmpfile=$(mktemp)

    if jq --indent 2 \
        --arg name "$name" \
        --arg platform "$platform" \
        --argjson is_live "$is_live" \
        --arg viewer_count "$viewer_count" \
        --arg game_name "$game_name" \
        --arg title "$title" \
        --argjson recording "$recording" \
        --arg filename "$filename" \
        --arg last_updated "$(date --iso-8601=seconds)" \
        '
        def matches_target:
            (.name | ascii_downcase) == ($name | ascii_downcase) and .platform == $platform;
        def retained_string($incoming; $existing; $field):
            if $incoming != "" then $incoming else ($existing[$field] // "") end;
        def retained_number($incoming; $existing; $field):
            if $incoming != "" then ($incoming | tonumber? // 0) else ($existing[$field] // 0) end;
        def merged_entry($existing):
            {
                name:$name,
                platform:$platform,
                is_live:$is_live,
                viewer_count:retained_number($viewer_count; $existing; "viewer_count"),
                game_name:retained_string($game_name; $existing; "game_name"),
                title:retained_string($title; $existing; "title"),
                recording:$recording,
                filename:retained_string($filename; $existing; "filename"),
                last_updated:$last_updated
            };

        .streamers //= [] |
        if any(.streamers[]?; matches_target) then
            .streamers |= map(
                if matches_target then
                    merged_entry(.) as $candidate |
                    if (del(.last_updated) == ($candidate | del(.last_updated))) then . else $candidate end
                else
                    .
                end
            )
        else
            .streamers += [merged_entry({})]
        end
        ' "$status_file" > "$tmpfile"; then
        if ! cmp -s "$tmpfile" "$status_file"; then
            mv "$tmpfile" "$status_file"
        else
            rm "$tmpfile"
        fi
    else
        rm "$tmpfile"
        return 1
    fi
}

fnPruneStatusFile(){
    if [[ ! -f "$status_file" ]]; then
        mkdir -p "$(dirname "$status_file")"
        cat > "$status_file" <<EOF
{"streamers":[]}
EOF
    fi

    local valid_entries
    valid_entries=$(
        {
            for streamer in "${twitchstreamers[@]}"; do
                jq -nc --arg name "$streamer" --arg platform "Twitch" \
                    '{name:($name | ascii_downcase), platform:$platform}'
            done

            for streamer in "${kickstreamers[@]}"; do
                jq -nc --arg name "$streamer" --arg platform "Kick" \
                    '{name:($name | ascii_downcase), platform:$platform}'
            done
        } | jq -s '.'
    )

    local tmpfile
    tmpfile=$(mktemp)

    jq --indent 2 --argjson valid_entries "$valid_entries" '
        .streamers |= map(
            . as $streamer |
            select(
                any($valid_entries[];
                    .platform == $streamer.platform and
                    .name == ($streamer.name | ascii_downcase)
                )
            )
        )
    ' "$status_file" > "$tmpfile" && mv "$tmpfile" "$status_file"
}

fnStartDashboard(){
    if [[ "$dashboard" -eq 1 ]]; then
        if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then
            fnLog "INFO" "${GREEN}Dashboard:${NC} Starting dashboard server on port 8080."
            screen -dmS StreamCaptureDashboard bash -lc "cd "$(dirname "$status_file")" && python3 -m http.server 8080 > /dev/null 2>&1"
        else
            fnLog "LOCAL" "${GREEN}Dashboard:${NC} Dashboard server is running at http://localhost:8080."
        fi
    fi
}

### Dashboard functions above, recording functions below ###

fnRequestTwitchBatch(){
    #Make a single batch request to Twitch API for all streamers at once.
    if [[ -z "${twitchstreamers[*]}" ]]; then
        return
    fi

    screen_sessions=$(screen -list)
    local streamer_list="$(printf '&user_login=%s' "${twitchstreamers[@]}" | sed 's/^&//')"
    local batch_request=$(curl -s -H "Client-Id: $twitch_clientid" -H "Authorization: Bearer $twitch_access_token" -X GET "https://api.twitch.tv/helix/streams?$streamer_list")
    
    # Process each streamer's data from the batch response using JSON objects
    while IFS= read -r item; do
        local streamer=$(echo "$item" | jq -r '.user_login')
        if [[ -n "$streamer" ]]; then
            local is_live=$(echo "$item" | jq -r '.type')
            local game_name=$(echo "$item" | jq -r '.game_name // ""')
            local viewer_count=$(echo "$item" | jq -r '.viewer_count // 0')
            local title=$(echo "$item" | jq -r '.title')
            local id=$(echo "$item" | jq -r '.id')
            fnProcessTwitchStreamer "$streamer" "$is_live" "$game_name" "$title" "$id" "$viewer_count"
        fi
    done < <(echo "$batch_request" | jq -c '.data[]')
    
    # Also check for streamers that are offline (not in the response)
    for streamer in "${twitchstreamers[@]}"; do
        if ! echo "$batch_request" | jq -e ".data[] | select(.user_login == \"$streamer\")" > /dev/null 2>&1; then
            fnProcessTwitchStreamer "$streamer" "offline" "" "" "" ""
        fi
    done
}

fnProcessTwitchStreamer(){
    #Process a single streamer's status (called from batch request)
    local streamer="$1"
    local is_live="$2"
    local game_name="$3"
	local title="$4"
	local id="$5"
    local viewer_count="$6"
    local service="Twitch"
    local screen_session=$(grep -F -- ".$streamer-$service" <<< "$screen_sessions")

    # Check to see if there's a lock file and no screen session. If so, remove the lock file.
    if [[ -z "$screen_session" && -f "$destpath/logs/$streamer-$service.lock" ]]; then
        fnLog "INFO" "${GREEN}$service:${NC} Unlocking ${BLUE}$streamer${NC}."
        rm "$destpath/logs/$streamer-$service.lock"
    fi

    if [[ "$is_live" != "live" ]]; then
        #If the streamer is not live, we can skip the rest of the checks.
        fnLog "LOCAL" "${RED}Twitch:${NC} ${BLUE}$streamer${NC} is not live."
        fnUpdateStreamerStatus "$streamer" "$service" "$is_live" "" "" "" "false" ""
        return
    fi

    #Create streamer directory if it doesn't exist.
    if [[ ! -d "$destpath/$streamer" ]]; then
        mkdir "$destpath/$streamer"
    fi

    local already_recording=$(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink)
    if [[ -z "$already_recording" && -z "$screen_session" && "$is_live" == "live" ]] && [[ " ${game[*]} " == *"$game_name"* || "$monitortwitchgame" == 0 ]]; then
        #If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
        fnStartRecord "Twitch" "$streamer" "$game_name" "$title" "$id" "$viewer_count" "https://www.twitch.tv/$streamer"
    elif [[ -n "$already_recording" && -n "$screen_session" && "$is_live" == "live" && ! " ${game[*]} " == *"$game_name"* && "$stoptwitchrecord" == 1 && "$monitortwitchgame" == 1 ]]; then
        #If they change game and we have stop recording set, then stop recording.
        fnStopRecord "$streamer" "$game_name" "$service"
    elif [[ -n "$already_recording" ]]; then
        fnLog "LOCAL" "${GREEN}Twitch:${NC} ${BLUE}$streamer${NC} is live in ${YELLOW}$game_name${NC} and we're already recording."
        fnUpdateStreamerStatus "$streamer" "$service" "$is_live" "$game_name" "$title" "$viewer_count" "true" ""
    elif [[ "$is_live" == "live" ]]; then
        fnLog "LOCAL" "${YELLOW}Twitch:${NC} ${BLUE}$streamer${NC} is live in ${RED}$game_name${NC} which is not in ${YELLOW}${game[*]}${NC}."
		fnUpdateStreamerStatus "$streamer" "$service" "$is_live" "$game_name" "$title" "$viewer_count" "false" ""
    fi
}

fnRequestKickBatch(){
	#Make a single batch request to Kick API for all streamers at once.
    if [[ -z "${kickstreamers[*]}" ]]; then
        return
    fi

    screen_sessions=$(screen -list)
    local slug_list="$(printf '&slug=%s' "${kickstreamers[@]}" | sed 's/^&//')"
    local batch_request=$(curl -s -H "Authorization: Bearer $kick_access_token" "https://api.kick.com/public/v1/channels?$slug_list")

    # Process each streamer's data from the batch response using JSON objects
    while IFS= read -r item; do
        local streamer=$(echo "$item" | jq -r '.slug')
		if [[ -n "$streamer" ]]; then
			local is_live=$(echo "$item" | jq -r '.stream.is_live')
			local game_name=$(echo "$item" | jq -r '.category.name // ""')
			local title=$(echo "$item" | jq -r '.stream_title')
			local id=$(echo "$item" | jq -r '.broadcaster_user_id')
			local viewer_count=$(echo "$item" | jq -r '.stream.viewer_count // 0')
			fnProcessKickStreamer "$streamer" "$is_live" "$game_name" "$title" "$id" "$viewer_count"
		fi
	done < <(echo "$batch_request" | jq -c '.data[]')

    # Also check for streamers that are offline (not in the response)
    for streamer in "${kickstreamers[@]}"; do
        if ! echo "$batch_request" | jq -e ".data[] | select(.slug == \"$streamer\")" > /dev/null 2>&1; then
            fnProcessKickStreamer "$streamer" "offline" "" "" "" ""
        fi
    done
}

fnProcessKickStreamer(){
    local streamer="$1"
    local is_live="$2"
    local game_name="$3"
    local title="$4"
    local id="$5"
    local viewer_count="$6"
    local service="Kick"
    local screen_session=$(grep -F -- ".$streamer-$service" <<< "$screen_sessions")

    # Check to see if there's a lock file and no screen session. If so, remove the lock file.
    if [[ -z "$screen_session" && -f "$destpath/logs/$streamer-$service.lock" ]]; then
        if [[ $logging -ge 2 ]]; then
            fnLog "INFO" "${GREEN}$service:${NC} Unlocking ${BLUE}$streamer${NC}."
        fi
        rm "$destpath/logs/$streamer-$service.lock"
    fi

    if [[ "$is_live" != "true" ]]; then
        fnLog "LOCAL" "${RED}Kick:${NC} ${BLUE}$streamer${NC} is not live."
        fnUpdateStreamerStatus "$streamer" "$service" "$is_live" "" "" "" "false" ""
        return
    fi

    if [[ ! -d "$destpath/$streamer" ]]; then
        mkdir -p "$destpath/$streamer"
    fi

    local already_recording=$(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink)
    if [[ -z "$already_recording" && -z "$screen_session" && "$is_live" == "true" ]] && [[ " ${game[*]} " == *"$game_name"* || "$monitorkickgame" == 0 ]]; then
        fnStartRecord "Kick" "$streamer" "$game_name" "$title" "$id" "$viewer_count" "https://www.kick.com/$streamer"
    elif [[ -n "$already_recording" && -n "$screen_session" && "$is_live" == "true" && ! " ${game[*]} " == *"$game_name"* && "$stopkickrecord" == 1 && "$monitorkickgame" == 1 ]]; then
        fnStopRecord "$streamer" "$game_name" "$service"
    elif [[ -n "$already_recording" || -n "$screen_session" ]]; then
        fnLog "LOCAL" "${GREEN}Kick:${NC} ${BLUE}$streamer${NC} is live in ${YELLOW}$game_name${NC} and we're already recording."
        fnUpdateStreamerStatus "$streamer" "$service" "$is_live" "$game_name" "$title" "$viewer_count" "true" ""
    elif [[ "$is_live" == "true" ]]; then
        fnLog "LOCAL" "${YELLOW}Kick:${NC} ${BLUE}$streamer${NC} is live in ${RED}$game_name${NC} which is not in ${YELLOW}${game[*]}${NC}."
        fnUpdateStreamerStatus "$streamer" "$service" "$is_live" "$game_name" "$title" "$viewer_count" "false" ""
    fi
}

fnStartRecord(){
    # Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
    local service="$1"
    local streamer="$2"
    local game_name="$3"
	local title=$(echo "$4" | tr -dc '[:print:]' | tr -d '<>:"/\\|?*' | tr -s " ")
	local id="$5"
    local viewer_count="$6"
    local stream_url="$7"
	local outputname=$(echo "$streamer - S$(date +%y)E$(date +%j) - $title [$id$RANDOM]")
    local screen_opts=()
	local tmpfile="$destpath/$streamer/$outputname.tmp"
    fnLog "SUCCESS" "${GREEN}$service:${NC} Starting recording of ${BLUE}$streamer${NC} playing ${GREEN}$game_name${NC}. File name: ${YELLOW}$outputname.mp4${NC}"
    if [[ $debug -ge 1 ]]; then
        local screen_opts=(-L -Logfile "$destpath/logs/debug/$outputname.txt")
    fi
    screen -dmS "$streamer-$service" "${screen_opts[@]}" bash -lc "streamlink --output \"$tmpfile\" $stream_url best; rc=\$?; if [[ -s \"$tmpfile\" ]]; then ffmpeg -y -i \"$tmpfile\" -c copy -movflags faststart \"$destpath/$streamer/$outputname.mp4\"; fi; rm -f \"$tmpfile\""
	fnUpdateStreamerStatus "$streamer" "$service" "true" "$game_name" "$title" "$viewer_count" "true" "$outputname.mp4"
}

fnStopRecord(){
    #This sends a ctrl+c (SIGINT) to the screen to gracefully stop the recording.
    local streamer="$1"
    local game_name="$2"
    local service="$3"
    if [[ ! -f "$destpath/logs/$streamer-$service.lock" ]]; then
        fnLog "INFO" "${GREEN}$service:${NC} Locking ${BLUE}$streamer${NC}."
        touch "$destpath/logs/$streamer-$service.lock"
        fnLog "STOP" "${GREEN}$service:${NC} Stopping recording of ${BLUE}$streamer${NC}. ${RED}$game_name${NC} not in ${GREEN}${game[*]}${NC}."
        screen -S "$streamer-$service" -X stuff $'\003'
    else
        fnLog "INFO" "${GREEN}$service:${NC} ${YELLOW}Locked${NC}: Waiting for processing to finish for ${BLUE}$streamer${NC}."
    fi
}

fnDependencyCheck
fnStart
