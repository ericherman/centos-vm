#!/bin/bash

retry_count=$1
shift

sleep_time=$1
shift

exit_code=1
while [ $retry_count -ge 0 ]; do
	$@
	exit_code=$?
	if [ $exit_code -eq 0 ]; then
		exit 0;
	fi
	retry_count=$(($retry_count - 1))
	if [ $retry_count -ge 0 ]; then
		echo "will retry ($retry_count) in $sleep_time second(s)"
		sleep $sleep_time
	else
		echo "will not retry"
	fi
done
exit $exit_code;
