#!/bin/sh

# set -x

ACTION=$1
PROJECT_DIR=$PWD

. setup.config

echo "TIER: ${TIER}"
echo "TF_VERSION: ${TF_VERSION}"


# For Toggling Color when Echo
HIGHLIGHT='\033[1;33m' # Yellow
HIGHLIGHT_B='\033[1;44m' # Blue
HIGHLIGHT_G='\033[1;32m' # Green
HIGHLIGHT_R='\033[1;31m' # Red
NC='\033[0m'

# Find all workspaces with specified tier
WORKSPACES=$(find workspaces -maxdepth $TIER -mindepth $TIER)

# Fetch the main branch (or replace 'main' with your default branch name)  
git fetch origin main || { echo "Failed to fetch main branch"; exit 1; }  

# Iterate over all workspaces  
for WS in ${WORKSPACES}; do  
    export AWS_PROFILE=$(echo "${WS}" | cut -d / -f 2)  
    if git diff --quiet HEAD origin/main -- "$WS"; then  
        echo -e "${HIGHLIGHT_B}No changes in workspace: $WS ${NC}"  
    else  
        echo  -e "${HIGHLIGHT_B}Changes detected in workspace: $WS ${NC}"  
        cd "$WS" || { echo "Failed to change directory to $WS"; exit 1; }  

        suffix=$(echo "${workspace}" | sed -r 's/\//-/g')
        echo "===> Tofu init"
        tofu init  
        echo "----"

        # This is what we are interested 
        echo -e "${HIGHLIGHT}==========> Tofu workspace ${ACTION} ${WS} ${NC}" 
        if [ "$ACTION" = "apply" ]; then
            echo -e "${HIGHLIGHT_G}"
            tofu apply -auto-approve
            echo -e "${NC}"    
        fi
        if [ "$ACTION" = "plan" ]; then 
            tofu plan > /tmp/plan.out.${suffix}
            echo -e "${HIGHLIGHT_G}"
            cat /tmp/plan.out.${suffix}
            echo -e "${NC}"
        fi  
        if [ $? -ne 0 ]; then  
            echo -e "${HIGHLIGHT_R}Tofu went bad...$WS ${NC}"  
            exit 1  
        fi
        echo  -e "${HIGHLIGHT} ---------- ${NC}"
        cd "$PROJECT_DIR" 
    fi  
done

if [ "$ACTION" = "plan" ]; then
    echo -e "${HIGHLIGHT} Summary ${NC}"
    echo -e "${HIGHLIGHT}========= ${NC}"
    for file in $(ls /tmp/plan.out.*); do
        echo -e "${HIGHLIGHT}$file: ${workspace}${NC}"
        grep "Plan:" $file
    done
fi

exit 0