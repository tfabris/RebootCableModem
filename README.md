RebootCableModem
==============================================================================
&copy; 2019 by Tony Fabris

https://github.com/tfabris/RebootCableModem

RebootCableModem is a Bash script which reboots my Xfinity SMC SMCD3GNV cable
modem if the Internet is down for more than a few minutes. This can be run as
a Cron job on any Linux or Mac system. I'm running it under the Task Scheduler
on the Synology NAS on my LAN.

I recommend running this only on a system which has a direct wired Ethernet
connection to the cable modem, otherwise it might get false alarms if there is
WiFi flakiness.

The commands which are used to reboot the modem are specific to the SMCD3GNV
modem, but the techniques used in this script could potentially be adaptable
to other models.

------------------------------------------------------------------------------


Configuration
------------------------------------------------------------------------------
####  Obtain and unzip the latest files:
- Download the latest project file and unzip it to your hard disk:
  https://github.com/tfabris/RebootCableModem/archive/master.zip
- (Alternative) Use Git or GitHub Desktop to clone this repository:
  https://github.com/tfabris/RebootCableModem

####  Create credentials file:
Create a file named "modem-creds" (no file extension), containing a single
line of ASCII text: A username, a space, and then a password. These will be
used for connecting to the web interface of your cable modem. Create the
"modem-creds" file and place it in the same directory as this script.

####  Edit the modemIp variable:
Edit the "modemIp" variable inside the RebootCableModem.sh script, to the
address of the cable modem on your LAN.

####  Set file permissions:
Set the access permissions on the folder which contains this script, the
script itself, and its credentials file, using a shell prompt:

     chmod 770 RebootCableModem
     cd RebootCableModem
     chmod 770 RebootCableModem.sh
     chmod 660 modem-creds

####  Create automated task to run the script:
If running this on a Linux computer, create a Cron job for this script, or, if
you are running it on a Synology NAS via the Synology Task Scheduler, create a
task for it there. Create the job so that it runs RebootCableModem.sh once
every five minutes continuously. If you have edited the script to alter its
timing intervals, then configure the job accordingly.


Behavior
------------------------------------------------------------------------------
By default, the script is configured so that it will perform a check of the
Internet, once per minute, for four minutes. After the last check, if any of
the Internet checks were good, it will exit the script without doing anything.
If all of the Internet checks were bad, it will reboot the cable modem and
then exit the script. Then, about a minute after the script is done, the next
timed run of the script will fire off, and the process repeats.

Using this pattern, the script will therefore only restart the cable modem if
the Internet has been down continuously for several minutes.

You can alter the number of checks, and the number of seconds between each
check, by editing variables in the script. You could, for example, configure
it to run 14 checks at intervals of 60 seconds. If you modify those values,
then configure the scheduled task to run at the appropriate interval to match
the changes you made. For instance, if you program it to make 14 checks at one
check per minute, then run the scheduled task every 15 minutes.


Caution
------------------------------------------------------------------------------
Make sure not to set the intervals to be so short that the modem doesn't have
a chance to finish rebooting before the next run of the script. Otherwise it
will reboot the modem in an infinite loop every few minutes.

If the Internet connection is so poor that even rebooting the modem doesn't
fix the problem, then this script will continue to reboot the modem in an
infinite loop every few minutes until the connection is stable again.

