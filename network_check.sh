#!/bin/bash
# Author:
# https://github.com/ltpitt
#
# Please check README.md for install / usage instructions

###
# Configuration variables, customize if needed
###
# enable logging to logfile
logging=true

# Set gateway_ips to one or more ips that you want to check to declare network working or not.
# If any of the ips responds, the network is considered functional.
# A minimum of one ip is required, in the example below it shows how to check two different
# gateways using a space character as delimiter.
gateway_ips='192.168.0.1 8.8.8.8'
# Set nic to your Network card name, as seen in ip output.
# If you have multiple interfaces and are currently online, you can find which is in use with:
# ip route get 1.1.1.1 | head -n1 | cut -d' ' -f5
nic='wlan0'
# Set network_check_threshold to the maximum number of failed checks that must fail
# before declaring the network as non functional.
network_check_threshold=20

# Number of network restarts before server is rebooted.
restart_threshold=10

# Set reboot_server to true if you want to reboot the system as a last
# option to fix wifi in case the normal restore procedure fails.
reboot_server=true
# Set reboot_server to the desired amount of minutes, it is used to
# prevent reboot loops in case network is down for long time and reboot_server
# is enabled.
reboot_cycle=60

# log_file for logging when logging is enabled
log_file=/tmp/netcheck.log

# Lock file to prevent multiple instances to run
lock_file=/tmp/netcheck.lock

###
# Script logic
###

# Initializing the network check counter to zero.
network_check_tries=0

# This function is a simple logger, just adding datetime to messages.
function date_log {
    $logging && echo "$(date +'%Y-%m-%d %T') $1" >> ${log_file}
}

# This function checks connectivity to gateway_ips
function check_gateways {
    for ip in $gateway_ips; do
        ping -c 1 "${ip}"  > /dev/null 2>&1
        if [[ $? == 0 ]]; then
            return 0
        fi
    done
    return 1
}

function restart_wlan {
    date_log "Network was not working for the previous ${network_check_tries} checks."
    date_log "Restarting $nic"

    # Trying wlan restart using ip command.
    /sbin/ip link set "$nic" down
    sleep 5
    /sbin/ip link set "$nic" up
    sleep 20
}

function restart_server {
    # If the gateway checks are NOT successful.
    if ! check_gateways; then
        if [ "$reboot_server" = true ]; then
            # If there's no last boot file or it's older than reboot_cycle.
            if [[ ! -f $last_bootfile || $(find $last_bootfile -mmin +$reboot_cycle -print) ]]; then
                touch $last_bootfile
                date_log "Network is still not working, rebooting"
                /sbin/reboot
            else
                date_log "Last auto reboot was less than $reboot_cycle minutes old"
            fi
        fi
    fi
}

function check_lock {
# Check if Lock File exists, if not create it and set trap on exit
    if [ -f ${lock_file} ]; then
        echo "Script already running, exiting."
        exit
    else
        touch ${lock_file}
        trap "rm -f ${lock_file}" EXIT
    fi
}

# Main script
# Exit if already running
check_lock

while (( restart_threshold )); do
# This loop will run restart_threshold times. 
# If not network is up after restart_threshold, the server will be rebooted

    # This loop will run for network_check_tries times, in case there are
    # network_check_threshold failures the network will be declared as
    # not functional and the restart_wlan function will be triggered.
    while [ $network_check_tries -lt $network_check_threshold ]; do
        # Increasing network_check_tries by 1
        network_check_tries=$((network_check_tries+1))

        if check_gateways; then
            date_log "Network is working correctly" && exit 0
        else
            date_log "Network is down, failed check number $network_check_tries of $network_check_threshold"
        fi

        # Once the network_check_threshold is reached call restart_wlan.
        if [ $network_check_tries -ge $network_check_threshold ]; then
            restart_wlan
        fi
        sleep 5
    done
    date_log "${restart_threshold} network restarts before reboot"
    restart_threshold=$((restart_threshold-1))
done

date_log "server will reboot"
/sbin/reboot