#!/bin/bash

max_retry_count=$1
shift

sleep_time=$1
shift

retry_count=$max_retry_count
exit_code=1

# ensure log file exists
touch .retry.log

while [ $retry_count -ge 0 ]; do
	# keep only the most recent ~1000 lines
	tail --lines=1000 .retry.log > .retry.log
	$@ >> .retry.log 2>&1
	exit_code=$?
	if [ $exit_code -eq 0 ]; then
		exit 0;
	fi
	retry_count=$(($retry_count - 1))
	if [ $retry_count -ge 0 ]; then
		printf "\rretrying failed command in $sleep_time second(s) "
		printf "($retry_count of $max_retry_count retries left)...   "
		sleep $sleep_time
	else
		echo "will not retry"
	fi
done
exit $exit_code;
