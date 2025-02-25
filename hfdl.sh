#!/bin/bash

# shows the date and time this script ran
currentDate=`date`
echo $currentDate

trap 'echo "[ERROR] Error in line $LINENO when executing: $BASH_COMMAND"' ERR

##############################################################

#finds the most-active frequencies currently in use by aircraft then runs dumphfdl using them. dumphfdl version 1.2.1 or higher is required

#this script is written for use with an sdrplay sdr on a computer with a fast #multicore processor running linux. At least a Raspberry Pi 4 or a mini PC recommended. Modify the script as needed for use with an airspy hf+ discovery sdr (consult your sdr's documentation for sampling rate, gain and other settings information.)

#you must specify the testing duration for each array of frequencies from the command line when you run the script, for example ./hfdl.sh 2m or ./hfdl.sh 90s. Choose the lowest duration that still gives you a good representative sample of current activity on the frequencies.

#the script may be automatically run at intervals as a cron job if you wish. Example: run crontab -e and at the end of the file add 0 * * * * /home/seth/radio/dumphfdl/hfdl.sh 2m  > home/seth/hflog/cron.log 2>&1 (which will also log the output of the script plus any error messages)

#to close dumphfdl after running the script, run pkill dumphfdl in another terminal window

###############################################################	


LOGFILE="/home/seth/radio/hfdl.log"
ERRORLOG="/home/seth/radio/hfdl.error.log"

# rotates the hfdl log daily
currentTime=`date +%H:%M`
currentDate=`date +%F`
if [ $currentTime == "00:00" ] && [ -f "$LOGFILE" ];
then
			pkill dumphfdl;
			sleep 5
			mv "$LOGFILE" "/home/seth/hflog/hfdl_${currentDate}.log"
fi
sleep 5

# use tail -f home/seth/hflog/hfdl.log to follow the output when the decoder is running

#name for the frequency group
fname=()

#frequency group. frequencies below 5MHz are not included due to very low activity.
# For less-powerful processors or 8-bit sdrs add more frequency groups containing a lower frequency spread in each group
freq=()

#use the smallest sampling rate that is greater than 80% of the difference between the highest and lowest frequency in each group to allow a hiher bitrate in the SDR for higher dynamic range and better weak signal reception. The lower the sampling rate the better.
samp=()

#different gain reduction settings for each frequency group to allow optimizing performance 
gain=()

#include an optimal sampling rate, gain settings, a count 0 and a friendly name for each frequency group if you have changed them to add more groups

# group 1
fname+=("11M13M")
freq+=("11306 11312 11318 11321 11327 11348 11354 11384 11387 11184 11306 13264 13270 13276 13303 13312 13315 13321 13324 13342 13351 13354")
samp+=("3000000")
gain+=("IFGR=53,RFGR=2")

# group 2
fname+=("5M6M")
freq+=("5451 5502 5508 5514 5529 5538 5544 5547 5583 5589 5622 5652 5655 5720 6529 6535 6559 6565 6589 6619 6661")
samp+=("2000000")
gain+=("IFGR=45,RFGR=4")

# group 3
fname+=("8M10M")
freq+=("8825 8834 8843 8851 8885 8886 8894 8912 8921 8927 8936 8939 8942 8948 8957 8977 10027 10060 10063 10066 10075 10081 10084 10087 10093")
samp+=("2000000")
gain+=("IFGR=53,RFGR=2")

# group 4
fname+=("17M")
freq+=("17901 17912 17916 17919 17922 17928 17934 17958 17967")
samp+=("2000000")
gain+=("IFGR=40,RFGR=2")

# group 5
fname+=("21M")
freq+=("21928 21931 21934 21937 21949 21955 21982 21990 21995 21997")
samp+=("2000000")
gain+=("IFGR=40,RFGR=2")

# build the command line for dumphfdl
dumpcmd=( /usr/local/bin/dumphfdl )

# output data into experimental adsbexchange aggregation (not shown on main page for the moment)
dumpcmd+=( --station-id SF-KCJR-HFDL --output decoded:json:tcp:address=feed.airframes.io,port=5556 )

# change the LOGFILE variable at the top to modify where the more permanent logfile is
dumpcmd+=( --output "decoded:text:file:path=$LOGFILE")

# edit the IP / port number of stats or add a # in front of the line to not use statsd
#dumpcmd+=(--statsd 192.168.1.156:8125 )

# edit the soapysdr driver as reuired
dumpcmd+=( --soapysdr driver=sdrplay )
#dumpcmd+=( --freq-as-squawk )

# edit the systable path in the next two lines:
#dumpcmd+=( --system-table /home/seth/radio/dumphfdl/etc/systable.conf )
#dumpcmd+=( --system-table-save /home/seth/radio/dumphfdl/etc/systable-new.conf )

# output data into combine1090, add # in front of the line to deactivate
#dumpcmd+=( --output decoded:basestation:tcp:mode=server,address=127.0.0.1,port=29109 )

# output data into VRS, add # in front of the line to deactivate
#dumpcmd+=( --output decoded:basestation:tcp:mode=server,address=127.0.0.1,port=20005 )

# use your local basestation database to look up aircraft details or add a # in front of the line to not use a basestation database
#dumpcmd+=( --bs-db /home/seth/radio/dumphfdl/Basestation.sqb --ac-details verbose )

# adjust scoring weigths
WEIGHT_POSITIONS=40
WEIGHT_AIRCRAFT=10
WEIGHT_GROUNDSTATION=1

trap 'echo "[ERROR] Error in line $LINENO when executing: $BASH_COMMAND"' ERR

#this kills any currently-running tail tasks. (If you tail or multitail the hfdl.log, not killing tail tasks will leave several zombie tail processes running which could impact your computer's performance.)
echo "Stopping dumphfdl tasks"
pkill dumphfdl || true
pkill tail || true
sleep 5

# if the sdrplay api sometimes becomes unresponsive remove the # from the front of the next two lines. You will be prompted to enter your password unless you have modifed /etc/sudoers.
sudo systemctl restart sdrplay
sleep 5



TIMEOUT="$1"
if [[ -z "$TIMEOUT" ]]; then
    TIMEOUT=90
fi

# this shouldn't need changing
TMPLOG="/tmp/hfdl.sh.log.tmp"

aircraftMessages=()
positions=()
stationMessages=()
score=()

echo --------
i=0
for x in "${freq[@]}"
do
    aircraftMessages+=(0)
    stationMessages+=(0)
    positions+=(0)
    score+=(0)
    rm -f "$TMPLOG"
    timeoutcmd=( timeout "$TIMEOUT" "${dumpcmd[@]}" --gain-elements ${gain[$i]} --sample-rate ${samp[$i]} ${freq[$i]} --output "decoded:text:file:path=$TMPLOG" )
    echo "running: ${timeoutcmd[@]}"
    "${timeoutcmd[@]}" || true
    if [[ -f "$TMPLOG" ]]; then
        stationMessages[$i]=$(grep -c "Src GS" "$TMPLOG" || true)
        aircraftMessages[$i]=$(grep -c "Src AC" "$TMPLOG" || true)
        positions[$i]=$(grep -c "Lat:" "$TMPLOG" || true)
        score[$i]=$(( WEIGHT_POSITIONS * positions[$i]  + WEIGHT_AIRCRAFT * aircraftMessages[$i] + WEIGHT_GROUNDSTATION * stationMessages[$i] ))
    fi
    echo --------
    printf "%-20s%-15s%-25s%-26s%-18s\n" "${fname[$i]}" "score: ${score[$i]}" "stationMessages: ${stationMessages[$i]}" "aircraftMessages: ${aircraftMessages[$i]}" "positions: ${positions[$i]}"
    echo --------
    (( i += 1 ))
    sleep 10
done


echo --------
echo Summary:
echo --------
i=0
k=0
for x in "${freq[@]}"
do
    printf "%-20s%-15s%-25s%-26s%-18s\n" "${fname[$i]}" "score: ${score[$i]}" "stationMessages: ${stationMessages[$i]}" "aircraftMessages: ${aircraftMessages[$i]}" "positions: ${positions[$i]}"
    if (( ${score[$i]} > ${score[$k]} ))
    then
        k=$i
    fi
    (( i += 1 ))
done
echo --------
echo "${fname[$k]} wins"
printf "%-20s%-15s%-25s%-26s%-18s\n" "${fname[$k]}" "score: ${score[$k]}" "stationMessages: ${stationMessages[$k]}" "aircraftMessages: ${aircraftMessages[$k]}" "positions: ${positions[$k]}"
echo --------

#Display the friendly name, gain elements, sample rate and active frequencies chosen by the script when running it manually in a terminal
echo "Using ${fname[$k]}: gain-elements ${gain[$k]}, sample-rate ${samp[$k]}, frequencies ${freq[$k]}"

#this ends the script and runs dumphfdl using the above parameters and the most-acive frequency array using its gain reduction settings and sampling rate

#NOTE: if something is wrong with your script or if no messages were received it will always default to using the first frequency array

longcmd=( "${dumpcmd[@]}" --gain-elements ${gain[$k]} --sample-rate ${samp[$k]} ${freq[$k]} )

echo "------"
echo "Running: ${longcmd[@]}"
nohup "${longcmd[@]}" 2>"$ERRORLOG" >/dev/null &
echo "------"

echo "you can follow decoder startup and error messages using tail -f $ERRORLOG"
echo "you can follow what is being decoded using tail -f $LOGFILE"
echo "------"
