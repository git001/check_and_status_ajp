# check_and_status_ajp

This tool have two modes.

* ajp ping
* ajp check

## Used perl modules
* Socket
* Time::HiRes
* POSIX

## Description

The default mode is the **ping** mode

The check mode can be used when the program is called as **check_ajp.pl**.

This can be done with symlinks or with a copy of **ajpping.pl**

You **must** call ajpping.pl with at least two parameters.

* hostname or ip
* port

the third parameter is a timeout in **microseconds**.

Default is

* 100000 # 100 milli seconds

One call runs the program once!

The return codes are the same as for icinga or nagios

https://nagios-plugins.org/doc/guidelines.html#AEN78

There are a lot of possibilities to run this programm in a regulary manner, use your *regular* tool for that task ;-)

## Ping mode

A Setup of the output line is at the end of the file in the END Block

```
%Y-%m-%d %T host %s ip %s port %s connect %f syswrite %f sysread %f timeouted %d timeout %d good_answer %d
```

## Check mode

The output of the check mode looks similar. The only difference is that the line prefix is not the date and time.

```
OK - AJP | host %s ip %s port %s connect %f syswrite %f sysread %f timeouted %d timeout %d good_answer %d
CRITICAL - Timedout | host %s ip %s port %s connect %f syswrite %f sysread %f timeouted %d timeout %d good_answer %d
CRITICAL - Protocol missmatch | host %s ip %s port %s connect %f syswrite %f sysread %f timeouted %d timeout %d good_answer %d
```

## Field description

Name | Description
------------ | -------------
host    | the given hostname or ip address
ip      | the resolved ip address
port    | the given port
connect  ( TCP / IP )| connect time in microseconds
syswrite ( request ) | request time in microseconds
sysread ( response ) | response time in microseconds
timeouted            | reached any of the operation above the given timeout
timeout              | given timeout value in microseconds
good_answer          | was the response a valid ajp pong message


Link for git hub editing

https://help.github.com/categories/writing-on-github/

https://guides.github.com/features/mastering-markdown/
