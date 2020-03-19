#!/bin/bash 

# ------------------------------------------------------------------------------
# Script to reboot an Xfinity SMCD3GNV cable modem if the Internet is down.
#
# The technique for the modem login and reboot is from here originally:
# https://github.com/stuffo/rebootHitronRouter/blob/master/rebootHitronRouter.sh
# I started with that example because it was written to work on a modem whose
# firmware is similar to mine. However, I still had to make additional tweaks
# and changes, required for my particular model of modem.
#
# Run this program on a scheduled timer so that it launches every five
# minutes. For example, you could create a Cron job for this task. For
# different time lengths, edit the loop and timer variables below, and set the
# timing of your Cron job to match.
#
# I'm running this on a scheduled timer on my Synology NAS, but it should
# theoretically work on any Linux or Mac system. Recommend running this only
# on a system which has a direct wired Ethernet connection to the cable modem,
# otherwise it might get false alarms if there is WiFi flakiness.
#
# Configuration:
#
# See the accompanying file "README.md" for detailed information. Here is a
# brief configuration overview for those who don't want to read it:
#
# Create an ASCII text file named "modem-creds", containing the username and
# password of your cable modem, on one line, separated by a space. Place it in
# the same folder as this script, and perform a "chmod 660 modem-creds" on it.
#
# Perform a "chmod 744 RebootCableModem.sh" on this script file.
# 
# Edit the modemIp variable, below, to your modem address on your LAN.
#
# Set up your Cron job or Synology Task Scheduler job to run this file every
# five minutes.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------------------

# Test mode. Set to true to run this program in test mode. Set to false or any
# other value to run this program normally. This should be always set to
# "false" unless you are debugging this program.
testMode=false

# Set the modem address on your network.
modemIp="10.0.0.1"

# Set number of loops, and the number of seconds, of the network test loop. By
# default, this program runs for about 4+ minutes total (there is no sleep
# after the last test). Configure this program so that it is launched on a
# scheduled timer which runs every 5 minutes.
NumberOfNetworkTests=4
SleepBetweenTestsSec=60

# Alternate speed for running this program in test mode.
if [ "$testMode" = true ]
then
    SleepBetweenTestsSec=1
fi

# The Internet site we will be pinging to determine if the network is up.
# 2020-01-19 - Trying to ping the google DNS server instead of a DNS name,
# to work around the problem where my cable modem (DHCP/DNS server) will
# often respond to pings when DNS does not resolve. It will insert its
# own page into the web request, making it look (to a tester program) like
# all is well when it really isn't. So changing the test site.
# TestSite="google.com"
TestSite="8.8.8.8"


# Program name used in log messages.
programname="Reboot Cable Modem"

# Logins will fail on this brand of modem without the referer strings being
# present in the headers to the requests. Set up those strings here.
loginRefererString="http://$modemIp/home_loggedout.asp"
webcheckRefererString="http://$modemIp/user/at_a_glance.asp"
rebootRefererString="http://$modemIp/user/restore_reboot.asp"


#------------------------------------------------------------------------------
# Function blocks
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Function: Log message to console and, if this script is running on a
# Synology NAS, also log to the Synology system log.
# 
# Parameters: $1 - "info"  - Log to console stderr and Synology log as info.
#                  "err"   - Log to console stderr and Synology log as error.
#                  "dbg"   - Log to console stderr, do not log to Synology.
#
#             $2 - The string to log. Do not end with a period, we will add it.
#
# Global Variable used: $programname - Prefix all log messages with this.
#
# NOTE: I'm logging to the STDERR channel (>&2) as a work-around to a problem
# where there doesn't appear to be a Bash-compatible way to combine console
# logging *and* capturing STDOUT from a function call. Because if I log to
# STDOUT, then if I call LogMessage from within any of my functions which
# return values to the caller, then the log message output becomes the return
# data, and messes everything up. TO DO: Learn the correct way of doing both at
# the same time in Bash.
#------------------------------------------------------------------------------
LogMessage()
{
  # Log message to shell console. Echo to STDERR on purpose, and add a period
  # on purpose, to mimic the behavior of the Synology log entry, which adds
  # its own period.
  echo "$programname - $2." >&2

  # Only log to synology if the log level is not "dbg"
  if ! [ "$1" = dbg ]
  then
    # Only log to Synology system log if we are running on a Synology NAS
    # with the correct logging command available. Test for the command
    # by using "command" to locate the command, and "if -x" to determine
    # if the file is present and executable.
    if  [ -x "$(command -v synologset1)" ]
    then 
      # Special command on Synology to write to its main log file. This uses
      # an existing log entry in the Synology log message table which allows
      # us to insert any message we want. The message in the Synology table
      # has a period appended to it, so we don't add a period here.
      synologset1 sys $1 0x11800000 "$programname - $2"
    fi
  fi
}


#------------------------------------------------------------------------------
# Main Program Code
#------------------------------------------------------------------------------

# Get the directory of the current script so that we can find files in the
# same folder as this script, regardless of the current working directory. The
# technique was learned here: https://stackoverflow.com/a/246128/3621748
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Get the cable modem's username and password out of an external file named
# "modem-creds". Note: You must create the external file yourself and type the
# username and password into the file, on one line, with a space between them.
# Place the file in the same folder as this script, and do
# "chmod 660 modem-creds" on the file.
modemcreds="$DIR/modem-creds"

# Validate that the credentials file exists on the disk next to this script.
if [ ! -e "$modemcreds" ]
then
  LogMessage "err" "Missing file $modemcreds"
  exit 1
fi

# Read the user name and password from the file, into two variables.
read username password < "$modemcreds"

# Assert that the username and password values retrieved from the file are
# non-blank. TO DO: Learn the correct linux-supported method for storing and
# retrieving a username and password in an encrypted way.
if [ -z "$username" ] || [ -z "$password" ]
then
  LogMessage "err" "Problem obtaining modem credentials from external file"
  exit 1
fi


# ------------------------------------------------------------------------------
# Check for Internet
# ------------------------------------------------------------------------------

# Set a variable to keep track of how many network test successes we got.
# This script will only reboot the cable modem if the network was down
# continuously for a long time, meaning that every single one of the
# network tests in this loop has to fail before it will reboot the
# cable modem.
numberOfNetworkFailures=0

for networkTestLoop in `seq 1 $NumberOfNetworkTests`
do
  thisTestSite="$TestSite"

  # Induce a deliberate network failure case when running in test mode.
  if [ "$testMode" = true ]
  then
    thisTestSite="asdfasdfasdfasdfjalskdjflahmcxh.com"
  fi

  # Ping the network and do the necessary steps depending on the result.
  if ping -q -c 1 -W 15 $thisTestSite >/dev/null
  then
    LogMessage "dbg" "Network is up on test loop $networkTestLoop of $NumberOfNetworkTests. Number of failures so far: $numberOfNetworkFailures"
  else
    ((numberOfNetworkFailures++))
    LogMessage "err" "Network is down on test loop $networkTestLoop of $NumberOfNetworkTests. Number of failures so far: $numberOfNetworkFailures"
  fi

  # Issue - on 2020-01-19 I encountered a situation where DNS was down and
  # web sites were not responding, though PING worked and responded
  # successfully to ping google.com. I think this was due to a combination of
  # factors, partially due to DNS resolver cache on the DHCP router being
  # still active, and the cable modem being in a state where it only partially
  # functioned. So I'm trying this alternative to actually check if the web
  # site is up using the "--spider" feature of WGet. This method was suggested
  # here: https://stackoverflow.com/a/26820300
  # UPDATE: This alternative test was not an accurate method, and it falsely
  # indicated that the network was up when it was in fact very down. Do not use.
  # wget -q --timeout=15 --spider $thisTestSite
  # if [ $? -eq 0 ]
  # then
  #   LogMessage "info" "Network is up on test loop $networkTestLoop of $NumberOfNetworkTests. Number of failures so far: $numberOfNetworkFailures"
  # else
  #   ((numberOfNetworkFailures++))
  #   LogMessage "err" "Network is down on test loop $networkTestLoop of $NumberOfNetworkTests. Number of failures so far: $numberOfNetworkFailures"
  # fi

  # Sleep between each network test (but not on the last loop).
  if [ "$networkTestLoop" -lt $NumberOfNetworkTests ]
  then
    sleep $SleepBetweenTestsSec
  fi
done

# Determine if the Internet was up for all or part of the loop. If it was up
# for any part of the loop, do not reboot yet. Only reboot if all of the
# network test loops failed, i.e., the network has been down continuously for
# the run of this program.
if [ "$numberOfNetworkFailures" -eq $NumberOfNetworkTests ]
then
  LogMessage "err" "Internet connection is down - rebooting $modemIp"
else
  LogMessage "dbg" "Internet connection is either up, or partially up - will not reboot $modemIp"
  exit 0
fi


# ------------------------------------------------------------------------------
# Login
# ------------------------------------------------------------------------------

# If we have reached this point in the code, the network has been continuously
# down for a little while, and it's now time to reboot the cable modem.

# First, perform the login to the cable modem. Note that the programmers of
# this modem's login page changed their username and password variable names
# to something different than the usual. Apparently they thought this was
# funny.
LogMessage "dbg" "curl -s -i -d \"usernamehaha=$username\" -d \"passwordhaha=........\" --referer \"$loginRefererString\" http://$modemIp/goform/login"
loginReturnData=$( curl -s -i -d "usernamehaha=$username" -d "passwordhaha=$password" --referer "$loginRefererString" http://$modemIp/goform/login )

# Get the cookie "userid" number that is returned from the login, by using
# grep and cut, to parse it out of the response string.
userIdCookie=$( echo "$loginReturnData" | grep 'userid=' | cut -f2 -d=|cut -f1 -d';' )

# Abort the script if the userid cookie is invalid.
if [ -z "$userIdCookie" ]
then
  LogMessage "err" "Failed to login to $modemIp"
  exit 1
fi

# Print login success to the console.
LogMessage "dbg" "Logged in to $modemIp. Userid: $userIdCookie"


# ------------------------------------------------------------------------------
# Retrieve webcheck number
# ------------------------------------------------------------------------------

# Get the "webcheck" value, which is a hidden number on the modem's reboot
# page which changes every time. Start by surfing to the modem's reboot page.
LogMessage "dbg" "curl -s -i -b \"userid=$userIdCookie;\" --referer \"$webcheckRefererString\" http://$modemIp/user/restore_reboot.asp"
webcheckReturn=$( curl -s -i -b "userid=$userIdCookie;" --referer "$webcheckRefererString" http://$modemIp/user/restore_reboot.asp )

# The webcheck number is located in a line that looks like this:
#       <input type="hidden" value="111111111111" name="webcheck">
# Use "grep" and "cut" to parse out the number from that line.
webcheckNumber=$( echo "$webcheckReturn" | grep -m 1 webcheck | cut -d '"' -f4 )

# Abort the script if the webcheck number is invalid.
if [ -z "$webcheckNumber" ]
then
  LogMessage "err" "Failed to retrieve webcheck number"
  exit 1
fi

# Print webcheck success to the console.
LogMessage "dbg" "Webcheck retrieved: $webcheckNumber"


# ------------------------------------------------------------------------------
# Reboot modem
# ------------------------------------------------------------------------------

# Now that we have the webcheck number, perform the actual reboot. First, echo
# to the console what the command will be that will perform the reboot.
LogMessage "dbg" "curl -i -s -b \"userid=$userIdCookie;\" -d \"reboot=1\" -d \"file=restore_reboot\" -d \"dir=user/\" -d \"webcheck=$webcheckNumber\" --referer \"$rebootRefererString\" http://$modemIp/gocusform/Reboot | head -1"

# Only reboot the cable modem if this script is not running in test mode.
if [ "$testMode" = true ]
then
    LogMessage "err" "TEST MODE: Not actually rebooting the modem at this time"
else
    # I am not sure how many of the weird little data values I need to
    # include, so I am including the logical-looking ones (from the diagnostic
    # data below). Use "-i" to see response headers, and then "head -1" to get
    # their first line.
    rebootReturn=$( curl -i -s -b "userid=$userIdCookie;" -d "reboot=1" -d "file=restore_reboot" -d "dir=user/" -d "webcheck=$webcheckNumber" --referer "$rebootRefererString" http://$modemIp/gocusform/Reboot | head -1 )
fi

# Check the return message from the modem web page from the reboot command
# (which is the first line of the response headers we got with "head -1").
if [ "$rebootReturn" == "HTTP/1.0 200 OK" ]
then
    LogMessage "info" "Reboot command successfully issued"
    exit 0
else 
    LogMessage "err" "Reboot command failed: $rebootReturn"
    exit 1
fi


# ------------------------------------------------------------------------------
# Reference information
# ------------------------------------------------------------------------------

# Modem reboot page diagnostic information for later reference. This was
# retrieved using the Chrome web browser and viewing the Chrome diagnostic
# info of the page after performing an actual reboot by hand. In particular,
# the data values at the bottom of the list are what is needed to successfully
# reboot the modem.

# Request URL: http://10.0.0.1/gocusform/Reboot
# Request Method: POST
# Status Code: 200 OK
# Remote Address: 10.0.0.1:80
# Referrer Policy: no-referrer-when-downgrade
# Cache-control: no-cache
# Content-Type: text/html
# Pragma: no-cache
# Server: GoAhead-Webs
# X-DNS-Prefetch-Control: off
# Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3
# Accept-Encoding: gzip, deflate
# Accept-Language: en-US,en;q=0.9
# Cache-Control: no-cache
# Connection: keep-alive
# Content-Length: 121
# Content-Type: application/x-www-form-urlencoded
# Cookie: userid=11111111111
# cookie-installing-permission: required
# Host: 10.0.0.1
# Origin: http://10.0.0.1
# Pragma: no-cache
# Referer: http://10.0.0.1/user/restore_reboot.asp
# Upgrade-Insecure-Requests: 1
# User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.97 Safari/537.36
# reboot: 1
# resetWiFiModule: 
# rebootWiFi: 
# restoreWiFi: 
# resetPw: 
# restoreDef: 
# file: restore_reboot
# dir: user/
# webcheck: 11111111111
