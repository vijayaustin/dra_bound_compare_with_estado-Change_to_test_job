#!/bin/bash

#********************************************************************************
# Copyright 2014 IBM
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#********************************************************************************

#############
# Colors    #
#############
export green='\e[0;32m'
export red='\e[0;31m'
export label_color='\e[0;33m'
export no_color='\e[0m' # No Color

##################################################
# Simple function to only run command if DEBUG=1 # 
### ###############################################
debugme() {
  [[ $DEBUG = 1 ]] && "$@" || :
}

set +e
set +x 

function dra_logger {

	if [ -z "$TOOLCHAIN_TOKEN" ]; then
        export CF_TOKEN=$(sed -e 's/^.*"AccessToken":"\([^"]*\)".*$/\1/' ~/.cf/config.json)
    else
        export CF_TOKEN=$TOOLCHAIN_TOKEN
    fi
    
    
    OUTPUT_FILE='draserver.txt'
	chmod 777 ${EXT_DIR}/*.py
    ${EXT_DIR}/is_dra_there.py ${PIPELINE_TOOLCHAIN_ID} "${CF_TOKEN}" "${IDS_PROJECT_NAME}" "${OUTPUT_FILE}"
	IS_DRA_RESULT=$?
    
    
	
	if [ $IS_DRA_RESULT -eq 0 ]; then
		#echo "DRA is present";
        export DRA_SERVER=`cat ${OUTPUT_FILE}`
        rm ${OUTPUT_FILE}

        debugme echo "DRA_SERVER: ${DRA_SERVER}"
        
        
		dra_commands "${DRA_SERVICE_LIST}"
	else
		#echo "DRA is not present";
		return 0
	fi
}

function dra_commands {

	npm install grunt
    npm install grunt-cli
	npm install grunt-idra2
    dra_grunt_command=""
	
		event_variable='{"CF_ORG":"'
		event_variable+=${CF_ORG}
		event_variable+='","CF_SPACE":"'
		event_variable+=${CF_SPACE}
		event_variable+='","CF_APP":"'
		event_variable+=${CF_APP}
		event_variable+='","CF_TARGET_URL":"'
		event_variable+=${CF_TARGET_URL}
		event_variable+='","CF_ORG_ID":"'
		event_variable+=${CF_ORGANIZATION_ID}
		event_variable+='","CF_SPACE_ID":"'
		event_variable+=${CF_SPACE_ID}
		event_variable+='"}'
		#echo -e "\nEvent Variable: $event_variable"

		event_to_file='echo $event_variable > deployInfo.json'
		eval $event_to_file
		#echo -e "\nEvent file created:"
		#cat deployInfo.json
		
		send_event='grunt --gruntfile=node_modules/grunt-idra2/idra.js -eventType=deployInfo -file=deployInfo.json --no-color'
		#echo -e "Sending deployInfo event to iDRA ..."
		echo -e "${no_color}"
		#eval $send_event
		echo -e "${no_color}"
		
		if [ ${DRA_MODE} == true ]; then
			mode='advisory'
		else
			mode='decision'
		fi
		
		# Move default current deployment event sent regardless of DRA_ENABLE_COMPARE_APPS is checked or not
		event1_name='deployInfo_'
		event1_name+=${DRA_APP_DESTINATION}
		event1_file=$event1_name
		event1_file+='.json'
		event1_to_file='echo $event_variable > $event1_file'
		eval $event1_to_file
		
		send_event1='grunt --gruntfile=node_modules/grunt-idra2/idra.js -eventType='
		send_event1+=$event1_name
		send_event1+=' -file='
		send_event1+=${DRA_MANIFEST_FILE}
		send_event1+=' --no-color'
		echo -e "Event to send manifest file: $send_event1"
		echo -e "Sending $event1_name event to iDRA ..."
		echo -e "${no_color}"
		eval $send_event1
		echo -e "${no_color}"
		# Move default current deployment event sent regardless of DRA_ENABLE_COMPARE_APPS is checked or not
		
		if [ ${DRA_ENABLE_BOUND_SERVICE} == true ]; then
		
			echo -e "Checking status of services bound to this application ...\n"
			
			bound_criteria_variable='{ "name": "DRADeploy_BOUND_COMPARE", "revision": 2, "project": "key", "mode": "'
			bound_criteria_variable+=$mode
			bound_criteria_variable+='", "rules": [ { "name": "Check for bound services", "conditions": [ { "eval": "_areApplicationBoundServicesAvailable", "op": "=", "value": true, "forEventType": "'
			bound_criteria_variable+=$event1_name
			bound_criteria_variable+='" } ] } ] }'
			#echo -e "\nCriteria Variable: $bound_criteria_variable"
			
			bound_criteria_to_file='echo $bound_criteria_variable > boundcriteriafile.json'
			eval $bound_criteria_to_file
			#echo -e "\nCriteria created:\n"
			#cat boundcriteriafile.json
			
			get_bound_decision='grunt --gruntfile=node_modules/grunt-idra2/idra.js -decision=dynamic -criteriafile=boundcriteriafile.json --no-color'
			echo -e "Requesting decision from DRA..."
			echo -e "${no_color}"
			eval $get_bound_decision
			RESULT2=$?
			echo -e "${no_color}"
		else
			RESULT2=0
			echo -e "Skipping 'Bound Services' check ...\n"
        fi
		
		if [ ${DRA_ENABLE_COMPARE_APPS} == true ]; then
			#echo -e "Comparing applications ..."	
			event2_name='deployInfo_'
			event2_name+=${DRA_APP_NOTDESTINATION}
			event2_file=$event2_name
			event2_file+='.json'

			compare_criteria_variable='{ "name": "DRADeploy_COMPARE_APPS", "revision": 2, "project": "key", "mode": "'
			compare_criteria_variable+=$mode
			compare_criteria_variable+='", "rules": [ { "name": "Compare applications", "conditions": [ { "eval": "_compareDeployments('
			compare_criteria_variable+=$event1_name
			compare_criteria_variable+=','
			compare_criteria_variable+=$event2_name
			compare_criteria_variable+=')", "op": "=", "value": true } ] } ] }'
			compare_criteria_to_file='echo $compare_criteria_variable > comparecriteriafile.json'
			eval $compare_criteria_to_file
			#echo -e "\nCriteria created:"
			#cat comparecriteriafile.json
			
			get_compare_decision='grunt --gruntfile=node_modules/grunt-idra2/idra.js -decision=dynamic -criteriafile=comparecriteriafile.json --no-color'
			#echo -e "Requesting decision from DRA..."
			echo -e "${no_color}"
			eval $get_compare_decision
			RESULT3=$?
			echo -e "${no_color}"
			
		else
			RESULT3=0
			echo -e "Skipping 'Compare deployments' check ...\n"
        fi
		
		if [ -n "$1" ] && [ "$1" != " " ]; then
			#echo -e "Estado service list: $1 is defined and not empty"
			estado_criteria_variable='{ "name": "DRADeploy_ESTADO_CHECK", "revision": 2, "project": "key", "mode": "'
			estado_criteria_variable+=$mode
			estado_criteria_variable+='", "rules": [ { "name": "Check for Estado Services", "conditions": [ { "eval": "_isEnvironmentListPassing('
			estado_criteria_variable+=$1
			estado_criteria_variable+=')", "op": "=", "value": true } ] } ] }'
			
			estado_criteria_to_file='echo $estado_criteria_variable > estadocriteriafile.json'
			eval $estado_criteria_to_file
			#echo -e "Estado criteria file:"
			#cat estadocriteriafile.json
			
			#dra_grunt_command='grunt --gruntfile=node_modules/grunt-idra2/idra.js -statusCheck="'
			#dra_grunt_command+=$1
			#dra_grunt_command+='"'
			dra_grunt_command='grunt --gruntfile=node_modules/grunt-idra2/idra.js -decision=dynamic -criteriafile=estadocriteriafile.json --no-color'
			#echo -e "Final command sent to grunt-iDRA to check Estado Services: "
			#echo -e $dra_grunt_command
			
			#echo -e "Requesting decision from DRA..."
			echo -e "${no_color}"
			eval $dra_grunt_command
			RESULT1=$?
			echo -e "${no_color}"
			
			#echo -e "Result of check Estado services: $RESULT1"
			
			DRA_ATTEMPT_MAX=3
			if [[ $RESULT1 != 0 && $DRA_ATTEMPT_MAX -ge 1 ]]; then 
				echo -e "\nTRYING MULTIPLE ATTEMPTS TO CHECK FOR SERVICE STATUS ...\n"
				ATTEMPT=1
			fi
			while [[ $RESULT1 -ne 0 && $ATTEMPT -ge 1 && $ATTEMPT -le $DRA_ATTEMPT_MAX ]]
			do
				sleep 9
				echo -e "${no_color}"
				eval $dra_grunt_command
				RESULT1=$?
				echo -e "${no_color}"
				
				echo -e "Result of attempt #$ATTEMPT: $RESULT1"
				ATTEMPT=`expr $ATTEMPT + 1`
			done
		else
			RESULT1=0
			echo -e "Service List is not defined or is empty .. proceeding with deployment ..."
		fi
		
		if [[ $RESULT1 != 0 || $RESULT2 != 0 || $RESULT3 != 0 ]]; then
			return 1
		else
			return 0
		fi
}

dra_logger

#custom_cmd