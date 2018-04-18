#!/usr/bin/env python2
import sys

if not sys.argv[1]:
    print "usage: " + sys.argv[0] + " filename"

sbtests = []
with open(sys.argv[1], 'r') as infile:
    test = {}
    for line in infile:
        line = line.split()
        if not line:
            continue    
        if line[1] == 'threads':
            sbtests.append(test)
            test = {}
            test['threads'] = line [0]
        elif line[0] == 'test':
            test['name'] = line[1]
        elif line[0] == 'read:':
            test['reads'] = line[1]
        elif line[0] == 'write:':
            test['writes'] = line[1]
        elif line[0] == 'other:':
            test['others'] = line[1]
        elif line[0] == 'transactions:':
            test['transactions'] = line[1]
        elif line[0] == 'ignored' and line[1] == 'errors:':
            test['errors'] = line[2]
        elif line[0] == 'reconnects:':
            test['reconnects'] = line[1]
        elif line[0] == 'total' and line[1] == 'time:':
            test['time'] = line[2].rstrip('s')
        elif line[0] == 'min:':
            test['latency_min'] = line[1]
        elif line[0] == 'avg:':
            test['latency_avg'] = line[1]
        elif line[0] == 'max:':
            test['latency_max'] = line[1]
        elif line[0] == '95th':
            test['latency_95'] = line[2]

sbtests = filter(None, sbtests)

print "threads,test name,reads,writes,others,transactions,errors,reconnects,time,min latency,avg latency,max latency,95% latency"
for test in sbtests:
    try:
        print test['threads'] + ',' + test['name'] + ',' + test['reads'] + ',' + test['writes'] + ',' + test['others'] + ',' + test['transactions'] + ',' + test['errors'] + ',' +  \
          test['reconnects'] + ',' + test['time'] + ',' + test['latency_min'] + ',' + test['latency_avg'] + ',' + test['latency_max'] + ',' + test['latency_95']
    except KeyError:
        next


