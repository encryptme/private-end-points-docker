#!/bin/bash

CN_FILE="/tmp/common_names.txt"
touch $CN_FILE

# Stores the common_name from the client who has just disconnected
# This value will be used by private-end-point-docker-stats
# in order to avoid sending stats for this client
echo $common_name >> $CN_FILE

/usr/bin/send-metric.sh vpn_session

# Prune common_name from file or erase the file
grep -v $common_name $CN_FILE > tmp && \
	mv -f tmp $CN_FILE || \
	rm -f $CN_FILE