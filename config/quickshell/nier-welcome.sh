#!/bin/bash
INK='\033[38;2;70;63;46m'
ACC='\033[38;2;110;42;42m'
DIM='\033[38;2;50;45;36m'
RESET='\033[0m'

NOW=$(date "+%Y · %m · %d")
HOUR=$(date "+%H:%M:%S")
KERN=$(uname -r | cut -d'-' -f1)

echo ""
# ASCII figlet slant coloré ligne par ligne
while IFS= read -r line; do
    printf "${ACC}    %s${RESET}\n" "$line"
done < <(figlet -f slant "Unit - 3")

echo ""
printf "${DIM}    ─────────────────────────────────────${RESET}\n"
printf "    ${DIM}node  ${RESET}${INK}${USER}@$HOSTNAME${RESET}\n"
printf "    ${DIM}kern  ${RESET}${INK}${KERN}${RESET}\n"
printf "    ${DIM}time  ${RESET}${INK}${HOUR}  ${NOW}${RESET}\n"
printf "${DIM}    ─────────────────────────────────────${RESET}\n"
printf "    ${DIM}ヨルハ二号B型  ·  glory to mankind${RESET}\n"
printf "${DIM}    ─────────────────────────────────────${RESET}\n"
echo ""
