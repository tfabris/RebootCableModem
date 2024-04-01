#!/bin/bash 

# ------------------------------------------------------------------------------
# Script to reboot a cable modem if the Internet is down.
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
# Perform a "chmod 744 *.sh" on this script file.
# 
# Edit the modemIp variable, below, to your modem address on your LAN.
#
# Edit the modemType variable, below (only a few models are available).
#
# Set up your Cron job or Synology Task Scheduler job to run this file every
# five minutes.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------------------

# Test mode. Set to true to run this program in test mode. Set to false or any
# other value to run this program normally. This should be always set to
# "false" unless you are debugging this program. Test mode will fake a network
# failure, and speed up the loops for checking the network failures, so that
# you get a faster result. It will also not actually reboot the cable modem,
# it will just print out what command it would have issued.
testMode=false

# Set the modem address on your network.
modemIp="192.168.100.1"

# Type of modem. Current available types are:
#     DPC3941T
#     SMCD3GNV
#     CM1150V
#     C5500XK
modemType="C5500XK"

# Set number of loops, and the number of seconds, of the network test loop. By
# default, this program runs for about 4 minutes total and then exits. It
# performs 5 tests with a 60-second pause between each test. There is no pause
# after the last test, the program just exits after the last test, so the
# total runtime is about 4 minutes by default. Configure this program so that
# it is launched on a scheduled timer which runs every x minutes, where x is
# the proper multiple of number of loops times the time between each loop. For
# example, if you leave this at its default setting of 5 test loops at 60
# seconds each, it means you get a test at minutes 0, 1, 2, 3, and 4 on the
# clock, and then the script ends. In that case, configure the scheduled job
# to launch this script every 5 minutes, so that the loop starts over again at
# the 5th minute, AKA the 0 minute of the next run of the script.
NumberOfNetworkTests=5
SleepBetweenTestsSec=60

# Cable modems have a very long recovery time after a reboot. Make this script
# sleep several minutes after rebooting, so that it blocks a subsequent re-run
# of itself in the Synology Task Manager while it waits for the reboot to
# complete. After this timer is done, the script will exit and the next timed
# run of the script will go back to rechecking if the Internet came back up.
SleepAfterReboot=420

# Daily reboot. Set to true in order to perform a "self-healing" reboot of the
# modem once per day. Normally, this script will reboot the modem if the
# Internet is down for several minutes in a row. Setting this to true will
# make the script also reboot it once per day, even without any problems.
dailyReboot=true

# Daily reboot time. The time of day to reboot the modem. Format: 24-hour
# HH:MM format. Set these two values to a range of the same time period that
# you have configured this script to run for, plus two minutes. For example,
# if you run this script every five minutes, then set these values to a range
# of seven minutes. The idea is that, if this script normally runs once every
# five minutes (but is not perfectly accurate to that five minutes), then at
# some point during one of its script runs, it will hit this time window.
# Though if the script is set to run every five minutes, then setting this
# window to 7 minutes could theoretically cause the script to hit this time
# window twice, this script also has a "pause" after executing the reboot
# itself, so the script will still be running (pausing) for longer than those
# five minutes, so there won't be a second retrigger of this window.
#
# Note: Make sure that other timed tasks on your network will synergize with the
# modem reboot time. For example, I have a timed reboot of my Synology NAS at
# 3:30 AM so that it will happen shortly after the modem reboot is complete,
# and it will run a DDNS update at that time. Since the reboot of the modem
# might change its external IP address, then the DDNS update will occur shortly
# after the modem has finished rebooting.
dailyRebootTimeStart=03:20
dailyRebootTimeEnd=03:27

# Alternate speed for running this program in test mode.
if [ "$testMode" = true ]
then
    SleepBetweenTestsSec=1
    SleepAfterReboot=1
fi

# The Internet site we will be pinging to determine if the network is up.
# Note: Ping the google DNS server instead of a DNS name, to work around the
# problem where my network router (DHCP/DNS server) will often respond to
# pings when DNS does not resolve. It will insert its own page into the web
# request, making it look (to a tester program) like all is well when it
# really isn't. So changing the test site.
# TestSite="google.com"
TestSite="8.8.8.8"

# Program name used in log messages.
programname="Reboot Cable Modem"


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
# Function: Reboot a modem based on the type of modem.
# 
# Type of modem is defined by global variable $modemType.
#------------------------------------------------------------------------------
RebootModem()
{
  if [ "$modemType" = "DPC3941T" ]
  then
    RebootDPC3941T
    return 0
  fi

  if [ "$modemType" = "SMCD3GNV" ]
  then
    RebootSMCD3GNV
    return 0
  fi

  if [ "$modemType" = "CM1150V" ]
  then
    RebootCM1150V
    return 0
  fi

  if [ "$modemType" = "C5500XK" ]
  then
    RebootC5500XK
    return 0
  fi


  # At this point, one of the modem reboots above should have exited and this
  # function should no longer be running. The code below is never expected to
  # be hit unless there is a problem with the $modemType variable.
  LogMessage "err" "Error in script - modem type $modemType is not found"
  exit 1
}


#------------------------------------------------------------------------------
# Function: Reboot a Quantum Fiber C5500XK fiber router.
#------------------------------------------------------------------------------
RebootC5500XK()
{
  # Referer strings - not sure if these are needed. Other modems need them, I'm
  # just doing them here and didn't even bother to check if this modem needs
  # them too.
  loginRefererString="https://$modemIp/login.html"
  rebootRefererString="https://$modemIp/utilities_reboot.html"

  # Use curl to login and retrieve the session ID cookie.
  # NOTE: This modem requires HTTPS in its URL (it will 301-redirect you to
  # HTTPS if you happen to try HTTP). But if you add "--insecure" to the curl
  # command when using HTTPS then it will work and it won't redirect you.
  loginReturnData=$( curl -s -i -d "username=$username" -d "password=$password" --referer "$loginRefererString" https://$modemIp/cgi/cgi_action --insecure )

  # Parse the session ID cookie out of the returned output, and abort the script
  # if the cookie is invalid.
  sessionIdCookie=$( echo "$loginReturnData" | grep 'Session-Id=' | cut -f2 -d=|cut -f1 -d';' )
  if [ -z "$sessionIdCookie" ]
  then
    LogMessage "err" "Failed to login to $modemIp"
    exit 1
  fi
  LogMessage "dbg" "Logged in to $modemIp. Session ID Cookie: $sessionIdCookie"

  # ------------------------------------------------------------------------------
  # Reboot modem
  # ------------------------------------------------------------------------------
  # First, echo to the console the command we're going to use.
  LogMessage "dbg" "curl -s -i -b \"Session-Id=$sessionIdCookie;\" -d \"Action=Reboot\" --referer \"$rebootRefererString\" https://$modemIp/cgi/cgi_action --insecure"

  # Only reboot if this script is not running in test mode.
  if [ "$testMode" = true ]
  then
      LogMessage "err" "TEST MODE: Not actually rebooting at this time"
  else
      # Actually perform the reboot. NOTE: Use "head -1" so that only the first
      # line of the data is returned so that we can check if it simply returns
      # an OK result, that's all we care about.
      rebootReturn=$( curl -s -i -b "Session-Id=$sessionIdCookie;" -d "Action=Reboot" --referer "$rebootRefererString" https://$modemIp/cgi/cgi_action --insecure | head -1)
  fi

  # Strip out an extra carriage return that happens to exist in the return
  # value. The other modems just have linefeeds in their outputs, this one has
  # CRLFs in the output and the "head -1" above returns something with a CR at
  # the end because "head" splits on just linefeeds.
  rebootReturn=$(echo $rebootReturn | tr -d '\r')

  # Check the return message from the modem web page from the reboot command
  # (which is the first line of the response headers we got with "head -1").
  if [ "$rebootReturn" == "HTTP/1.1 200 OK" ]
  then
      LogMessage "info" "Reboot command successfully issued: $rebootReturn"

      # Must sleep a long time after rebooting the modem, or else it would just
      # try to reboot the thing again, since the network will still be down for
      # a long time while the modem is rebooting.
      sleep $SleepAfterReboot
      exit 0
  else 
      LogMessage "err" "Reboot command failed: $rebootReturn"
      exit 1
  fi
}


#------------------------------------------------------------------------------
# Function: Reboot an Xfinity SMC SMCD3GNV cable modem.
#
# The technique for the modem login and reboot is from here originally:
# https://github.com/stuffo/rebootHitronRouter/blob/master/rebootHitronRouter.sh
# I started with that example because it was written to work on a modem whose
# firmware is similar to mine. However, I still had to make additional tweaks
# and changes, required for my particular model of modem.
#------------------------------------------------------------------------------
RebootSMCD3GNV()
{
  # Logins will fail on this brand of modem without the referer strings being
  # present in the headers to the requests. Set up those strings here.
  loginRefererString="http://$modemIp/home_loggedout.asp"
  webcheckRefererString="http://$modemIp/user/at_a_glance.asp"
  rebootRefererString="http://$modemIp/user/restore_reboot.asp"

  # ------------------------------------------------------------------------------
  # Login
  # ------------------------------------------------------------------------------

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

      # Must sleep a long time after rebooting the modem, or else it would just
      # try to reboot the thing again, since the network will still be down for
      # a long time while the modem is rebooting.
      sleep $SleepAfterReboot
      exit 0
  else 
      LogMessage "err" "Reboot command failed: $rebootReturn"
      exit 1
  fi

    # ------------------------------------------------------------------------------
    # Reference information
    # ------------------------------------------------------------------------------

    # Modem reboot page diagnostic information for SMCD3GNV for later
    # reference. This was retrieved using the Chrome web browser and viewing
    # the Chrome diagnostic info of the page after performing an actual reboot
    # by hand. In particular, the data values at the bottom of the list are
    # what is needed to successfully reboot the modem.

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
}


#------------------------------------------------------------------------------
# Function: Reboot an Xfinity Cisco DPC3941T cable modem.
#------------------------------------------------------------------------------
RebootDPC3941T()
{
  # Logins will fail on this brand of modem without the referer string being
  # present in the headers to the requests. Set up the string here.
  loginRefererString="http://$modemIp/index.php"

  # ------------------------------------------------------------------------------
  # Login
  # ------------------------------------------------------------------------------

  # First, perform the login to the cable modem. Use curl's -L (location)
  # parameter to allow it to redirect to a new page when the login occurs. This
  # allows the second, redirected page, to return the csrfp_token cookie, which
  # is not returned on the first page of the request, only the second. I've
  # noticed that the second redirected page doesn't come through fully unless
  # I'm using a cookie file for Curl, but, that doesn't seem to be necessary.
  # The user cookie and the CSRFP token still work even if I don't have an
  # explicit cookie file and even if the full second page doesn't come through.
  # Still, the -L parameter seems to be needed in order for the cookie and the
  # CSRFP token to be retrieved and to work.

  # Set the parameters for the Curl call that will log into the modem. This
  # technique works as long as none of the parameters contain spaces.
  # https://stackoverflow.com/a/27928302
  curlParameters=(
                   -s -i -L
                   -d "username=$username"
                   -d "password=$password"
                   --referer "$loginRefererString"
                   http://$modemIp/check.php
                  )

  # Create a string for printing the parameters for debugging purposes.
  # https://superuser.com/a/462400
  curlParametersPrintable=$( IFS=$' '; echo "${curlParameters[*]}" )

  # Log into the modem.
  LogMessage "dbg" "Logging into cable modem"

  # Do not print the login string in normal circumstances, since the username
  # and password are part of the printout. Leave this commented out unless
  # debugging.
  # LogMessage "dbg" "curl $curlParametersPrintable"
  loginReturnData=$( curl ${curlParameters[@]} )

  # Get the cookie "PHPSESSID" number (essentially the user login cookie) that
  # is returned from the login, as well as the all-important crsfp token which
  # is used by the modem's CRSF prevention features. Do this by using grep and
  # cut to parse it out of the curl response string. Also use "tail -1" to get
  # only the last match of any given one of these. For instance if the curl "-L"
  # parameter allows it to return two pages (the second page occurring from a
  # redirect from the first page), then, only grep the result for the second of
  # the two pages.
  userIdCookie=$( echo "$loginReturnData" | grep 'PHPSESSID=' | tail -1 | cut -f2 -d=|cut -f1 -d';')
  csrfpToken=$( echo "$loginReturnData" | grep 'csrfp_token=' | tail -1 | cut -f2 -d=|cut -f1 -d';')

  # Abort the script if the userid cookie is invalid.
  if [ -z "$userIdCookie" ]
  then
    LogMessage "err" "Failed to login to $modemIp - userIdCookie invalid"
    LogMessage "dbg" "Login return data:"
    LogMessage "dbg" "---------------------------------------------------"
    LogMessage "dbg" "$loginReturnData"
    LogMessage "dbg" "---------------------------------------------------"
    exit 1
  fi

  # Abort the script if the csrfp token cookie is invalid.
  if [ -z "$csrfpToken" ]
  then
    LogMessage "err" "Failed to login to $modemIp - csrfpToken invalid"
    LogMessage "dbg" "Login return data:"
    LogMessage "dbg" "---------------------------------------------------"
    LogMessage "dbg" "$loginReturnData"
    LogMessage "dbg" "---------------------------------------------------"
    exit 1
  fi

  # Print login success to the console.
  LogMessage "dbg" "Logged into $modemIp. PHPSESSID: $userIdCookie csrfp_token: $csrfpToken"


  # ------------------------------------------------------------------------------
  # Reboot modem
  # ------------------------------------------------------------------------------

  # Decide which part of the modem we are rebooting. When looking at the modem's
  # "Reset-Restore" page, the first two buttons (btn1 and btn2 in its code) will
  # reboot either the entire modem, or just its Wifi radio, respectively. This
  # is determined by two variables in the Javascript, which are passed on to a
  # PHP page via an AJAX/JSON data header, which then reboots the modem. I'm
  # taking advantage of this, and rebooting only the Wifi when in "test" mode.
  buttonName=""
  rebootDevice=""
  if [ "$testMode" = true ]
  then
    LogMessage "dbg" "TEST MODE: Rebooting only the WiFi radio at this time"
    buttonName="btn2"
    rebootDevice="Wifi"
  else
    LogMessage "dbg" "Full mode: Rebooting the entire cable modem device."
    buttonName="btn1"
    rebootDevice="Device"
  fi

  # Set the parameters for the Curl call that will reboot the modem. This
  # technique works as long as none of the parameters contain spaces.
  # https://stackoverflow.com/a/27928302
  curlParameters=(
                  -i -s

                  # In order to reboot the modem, you need both the user's
                  # session cookie, as well as the "csrfp_token" which is part
                  # of the cookie information retrieved at login time. See
                  # https://github.com/mebjas/CSRF-Protector-PHP and
                  # http://10.0.0.1/CSRF-Protector-PHP/js/csrfprotector.js for
                  # the details of how its CSRF protection feature works.
                  # Note: I am using an alternative way to send the two cookies
                  # directly in the curl call, without having to resort to a
                  # cookie file on the hard disk.
                  -b "PHPSESSID=$userIdCookie;csrfp_token=$csrfpToken"

                  # Note: "X-CSRF-Token" does not work. You must format the
                  # header "their way" which is "csrfp_token:$csrfpToken"
                  -H "csrfp_token:$csrfpToken"

                  # The modem's Javascript code uses the JQuery library to do
                  # its business. This is the default content-type sent by
                  # JQuery's "ajax()", command, according to my research.
                  -H "Content-Type:application/x-www-form-urlencoded;charset=UTF-8"

                  # Note: all variations of sending the AJAX/JSON information
                  # which uses curly brackets and colons were incorrect. Though
                  # there were many examples on the web which showed the AJAX as
                  # having curly brackets, this did not work. For instance it
                  # cannot be -d "{\"resetInfo\":[\"btn1\",\"Device\",\"admin\"]}"

                  # This is the actual AJAX data string that is sent by jquery
                  # 1.9.1, which I determined by duplicating the router's
                  # javascript in a localhost installation and then debugging
                  # it. This is how I found that the curly brackets were wrong.
                  # -d "resetInfo=%5B%22btn1%22%2C%22Device%22%2C%22admin%22%5D"

                  # Alternative, more-readable way of doing the above, which
                  # results in identical output to the above:
                  --data-urlencode "resetInfo=[\"$buttonName\",\"$rebootDevice\",\"admin\"]"

                  # URL of the PHP file on the modem which performs the actual
                  # reboot, based on the data in the JSON "resetInfo" array.
                  http://$modemIp/actionHandler/ajaxSet_Reset_Restore.php
                 )

  # Create a string for printing the parameters for debugging purposes.
  # https://superuser.com/a/462400
  curlParametersPrintable=$( IFS=$' '; echo "${curlParameters[*]}" )

  # Finally reboot the modem.
  LogMessage "dbg" "curl $curlParametersPrintable"
  rebootReturn=$( curl ${curlParameters[@]})

  # Check the return message from the modem web page from the reboot command,
  # which is the first line of the response headers, gotten with "head -1", and
  # the newlines and carriage returns removed with tr -d.
  checkReturnMessage=`echo "${rebootReturn}" | head -1 | tr -d '\r' | tr -d '\n'`

  if [ "$checkReturnMessage" == "HTTP/1.1 200 OK" ]
  then
      LogMessage "info" "Reboot command successfully issued"

      # Must sleep a long time after rebooting the modem, or else it would just
      # try to reboot the thing again, since the network will still be down for
      # a long time while the modem is rebooting.
      sleep $SleepAfterReboot
      exit 0
  else 
      LogMessage "err" "Reboot command failed: $checkReturnMessage"
      LogMessage "dbg" "Reboot return data:"
      LogMessage "dbg" "---------------------------------------------------"
      LogMessage "dbg" "$rebootReturn"
      LogMessage "dbg" "---------------------------------------------------"
      exit 1
  fi

    # ------------------------------------------------------------------------------
    # Reference information
    # ------------------------------------------------------------------------------

    # Information about the CRSF protection features employed by the Cisco
    # DPC3941T cable modem, which made it initially very difficult to make this
    # script work successfully: https://github.com/mebjas/CSRF-Protector-PHP

    # The modem uses a Javacript AJAX/JSON call to a different embedded PHP page
    # within the modem when you click on the buttons on the reset/restore page.
    # The code is at http://10.0.0.1/actionHandler/ajaxSet_Reset_Restore.php on
    # the modem itself, but this same code has also been posted on GitHub here if
    # you want to browse the entire code tree: https://github.com/Gowthami10/webui

    # Some ideas about posting JSON with a CSRF token. This turned out to be wrong
    # because the CRSF protector on this modem does not use the "X-CRSF-Token"
    # header: https://stackoverflow.com/a/30257128

    # Some ideas about posting JSON to a site in general. This turned out to be
    # wrong because the curly brackets are an incorrect syntax for the parser that
    # this modem uses: https://stackoverflow.com/a/4315155

    # Another idea about using a totally different format to post AJAX to the URL.
    # It turns out that I did not need the "X-Requested-With" header, but it had
    # some good ideas about the JSON format: https://stackoverflow.com/q/44532922

    # Modem reboot page diagnostic information for later reference. This was
    # retrieved using the Chrome web browser and viewing the Chrome diagnostic
    # info of the page after performing an actual reboot by hand. (Login to the
    # page, and in the Network tab, select the filename that got loaded and then
    # look at the right-hand pane and click on Headers.) 

    # Request URL: http://10.0.0.1/check.php
    # Request Method: POST
    # Status Code: 302 Found
    # Remote Address: 10.0.0.1:80
    # Referrer Policy: no-referrer-when-downgrade
    # Cache-Control: no-store, no-cache, must-revalidate
    # Content-Length: 638
    # Content-Security-Policy: default-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' 'unsafe-eval'; frame-src 'self' 'unsafe-inline' 'unsafe-eval'; font-src 'self' 'unsafe-inline' 'unsafe-eval'; form-action 'self' 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; img-src 'self'; connect-src 'self'; object-src 'none'; media-src 'none'; script-nonce 'none'; plugin-types 'none'; reflected-xss 'none'; report-uri 'none';
    # Content-type: text/html; charset=UTF-8
    # Date: Fri, 06 Mar 2020 19:00:28 GMT
    # Expires: Thu, 19 Nov 1981 08:52:00 GMT
    # location: at_a_glance.php
    # Pragma: no-cache
    # Server: Xfinity Broadband Router Server
    # X-Content-Type-Options: nosniff
    # X-DNS-Prefetch-Control: off
    # X-Frame-Options: deny
    # X-robots-tag: noindex,nofollow
    # X-XSS-Protection: 1; mode=block
    # Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9
    # Accept-Encoding: gzip, deflate
    # Accept-Language: en-US,en;q=0.9
    # Cache-Control: no-cache
    # Connection: keep-alive
    # Content-Length: 32
    # Content-Type: application/x-www-form-urlencoded
    # Cookie: PHPSESSID=xxxxxxxxxxx; csrfp_token=xxxxxxxxxx
    # Host: 10.0.0.1
    # Origin: http://10.0.0.1
    # Pragma: no-cache
    # Referer: http://10.0.0.1/index.php
    # Upgrade-Insecure-Requests: 1
    # User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.132 Safari/537.36
    # username: xxxxxxxx
    # password: xxxxxxxx
}


#------------------------------------------------------------------------------
# Function: Reboot a Netgear CM1150V cable modem.
#------------------------------------------------------------------------------
RebootCM1150V()
{
  # ------------------------------------------------------------------------------
  # Login
  # ------------------------------------------------------------------------------

  # Log into the modem.
  LogMessage "dbg" "Logging into cable modem"

  # Perform a first attempt at login, just to get an XSRF token. This login
  # attempt will fail, but will return a valid XSRF token that I can parse
  # out. Normally the token is written as a cookie, but I wanted to avoid
  # using a cookie file on the hard disk if I didn't have to use one. I tried
  # to get Curl to handle the cookie in memory without needing the file, but
  # none of the techniques I found on the internet worked for that purpose.
  loginReturnData=$( curl -s -i -L http://$modemIp )
  xsrfToken=$( echo "$loginReturnData" | grep 'XSRF_TOKEN=' | tail -1 | cut -f2 -d=|cut -f1 -d';')

  # Abort the script if the cookie is invalid.
  if [ -z "$xsrfToken" ]
  then
    LogMessage "err" "Failed to login to $modemIp - xsrfToken invalid"
    LogMessage "dbg" "Login return data:"
    LogMessage "dbg" "---------------------------------------------------"
    LogMessage "dbg" "$loginReturnData"
    LogMessage "dbg" "---------------------------------------------------"
    exit 1
  fi

  # Now that we have the token, we can log in, as long as we supply the token
  # in the cookie data that we send.
  curlParameters=(
                  -s -i -L
                  -b "XSRF_TOKEN=$xsrfToken"
                  -u $username:$password
                  http://$modemIp/RouterStatus.htm
                 )
  routerStatusReturnData=$( curl ${curlParameters[@]} )

  # Check the return message from the modem web page, which is the first line
  # of the response headers, gotten with "head -1", and the newlines and
  # carriage returns removed with tr -d.
  checkReturnMessage=`echo "${routerStatusReturnData}" | head -1 | tr -d '\r' | tr -d '\n'`
  if [ "$checkReturnMessage" == "HTTP/1.1 200 OK" ]
  then
    LogMessage "dbg" "Logged into $modemIp. xsrfToken: $xsrfToken"
  else 
    LogMessage "err" "Failed to login to $modemIp - did not return 200 OK"
    LogMessage "dbg" "Login return data:"
    LogMessage "dbg" "---------------------------------------------------"
    LogMessage "dbg" "$loginReturnData"
    LogMessage "dbg" "---------------------------------------------------"
    exit 1
  fi

  # ------------------------------------------------------------------------------
  # Retrieve reboot ID number
  # ------------------------------------------------------------------------------

  # Parse out the id number from a line that looks like the following:
  #      <form action='/goform/RouterStatus?id=1748112' method="post">
  rebootIdNumber=$( echo "$routerStatusReturnData" | grep 'RouterStatus?id=' | cut -f3 -d=| cut -f1 -d\')

  # Abort the script if the ID number is invalid.
  if [ -z "$rebootIdNumber" ]
  then
    LogMessage "err" "Failed to retrieve rebootIdNumber"
    exit 1
  fi

  # Print rebootIdNumber success to the console.
  LogMessage "dbg" "Reboot ID retrieved: $rebootIdNumber"

  # ------------------------------------------------------------------------------
  # Reboot modem
  # ------------------------------------------------------------------------------
  curlParameters=(
                  -s -i -L
                  # Add a timeout so curl doesn't hang on the reboot
                  --max-time 5
                  -b "XSRF_TOKEN=$xsrfToken"
                  -u $username:$password
                  -X POST --data "buttonSelect=2"
                  "http://$modemIp/goform/RouterStatus?id=$rebootIdNumber&buttonSelect=2"
                 )
  
  # Only reboot the cable modem if this script is not running in test mode.
  if [ "$testMode" = true ]
  then
    LogMessage "err" "TEST MODE: Not actually rebooting the modem at this time"

    # Fake out the final check below, so it displays success when in test mode.
    rebootReturn="HTTP/1.0 302 Redirect"
  else
    # Perform the actual reboot
    rebootReturn=$( curl ${curlParameters[@]} )
  fi

  # Check the return message from the reboot web page, which is the first line
  # of the response headers, gotten with "head -1", and the newlines and
  # carriage returns removed with tr -d.
  checkReturnMessage=`echo "${rebootReturn}" | head -1 | tr -d '\r' | tr -d '\n'`
  if [ "$checkReturnMessage" == "HTTP/1.0 302 Redirect" ]
  then
    LogMessage "info" "Reboot command successfully issued"

    # Must sleep a long time after rebooting the modem, or else it would just
    # try to reboot the thing again, since the network will still be down for
    # a long time while the modem is rebooting.
    sleep $SleepAfterReboot
    exit 0
  else 
    LogMessage "err" "Reboot command failed: $checkReturnMessage"
    LogMessage "dbg" "Reboot return data:"
    LogMessage "dbg" "---------------------------------------------------"
    LogMessage "dbg" "$rebootReturn"
    LogMessage "dbg" "---------------------------------------------------"
    exit 1
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
# Check if it is time for the daily modem reboot.
# ------------------------------------------------------------------------------

# Use technique described here: https://unix.stackexchange.com/a/395936
currentTime=$(date +%H:%M)
if [ "$dailyReboot" = true ]
then
  if [[ "$currentTime" > "$dailyRebootTimeStart" ]] && [[ "$currentTime" < "$dailyRebootTimeEnd" ]]
  then
       LogMessage "info" "Current time is $currentTime - Performing daily modem reboot"
       RebootModem
       exit 0
  else
       LogMessage "dbg" "Current time is $currentTime - Not within range of $dailyRebootTimeStart to $dailyRebootTimeEnd - No daily reboot to be performed during this run"
  fi
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

    # Change the Synology NAS logging level, depending on how many failures we
    # have had so far. Only log to the level of "error" if there have been more
    # than two failures in a row. For those who aren't running this on a
    # Synology NAS, the messages will not change.
    if [ "$numberOfNetworkFailures" -gt "2" ]
    then
      LogMessage "err" "Network is down on test loop $networkTestLoop of $NumberOfNetworkTests. Number of failures so far: $numberOfNetworkFailures"
    else
      LogMessage "info" "Network is down on test loop $networkTestLoop of $NumberOfNetworkTests. Number of failures so far: $numberOfNetworkFailures"
    fi
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
  RebootModem
  exit 0
else
  LogMessage "dbg" "Internet connection is either up, or partially up - will not reboot $modemIp"
  exit 0
fi



