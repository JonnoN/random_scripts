#!/usr/bin/python
# vim: ai ts=4 sts=4 et sw=4 ft=python

# python packages needed: python-pip, python-httplib2, python-croniter
# pip install --upgrade google-api-python-client

import httplib2
import os
import socket
from apiclient import discovery
from apiclient.http import BatchHttpRequest
from oauth2client import client
from oauth2client import tools
from oauth2client.file import Storage
from croniter import croniter
import datetime
import gzip
import glob
import argparse


LOGFILE = '/var/log/mysql-zrm/mysql-zrm.log'
CONF_DIR = '/etc/mysql-zrm'

CALENDARS = { 'adc': '@group.calendar.google.com',
              'bdc': '@group.calendar.google.com',
              'cdc': '@group.calendar.google.com',
              'ddc': '@group.calendar.google.com',
              'edc': '@group.calendar.google.com' }

this_host_dc = socket.gethostname()[:3]
calendar = CALENDARS.get(this_host_dc)


# If modifying these scopes, delete your previously saved credentials
# at ~/.credentials/calendar-python-quickstart.json
SCOPES = 'https://www.googleapis.com/auth/calendar'
CLIENT_SECRET_FILE = 'client_secret.json'
APPLICATION_NAME = 'ZRM Calendar Updater'

# we are building one week schedule, mon-sun
today = datetime.date.today()
last_monday = today - datetime.timedelta(days=today.weekday())
next_sunday = last_monday + datetime.timedelta(days=6)
last_sunday = last_monday - datetime.timedelta(days=1)
week_start = datetime.datetime.combine(last_monday - datetime.timedelta(days=1), datetime.time(23, 59, 59))
week_start_google = week_start.isoformat() + 'Z'
week_end = datetime.datetime.combine(next_sunday, datetime.time(23, 59, 59))
week_end_google = week_end.isoformat() + 'Z'


def get_credentials():
    """Gets valid user credentials from storage.

    If nothing has been stored, or if the stored credentials are invalid,
    the OAuth2 flow is completed to obtain the new credentials.

    Returns:
        Credentials, the obtained credential.
    """
    home_dir = os.path.expanduser('~')
    credential_dir = os.path.join(home_dir, '.credentials')
    if not os.path.exists(credential_dir):
        os.makedirs(credential_dir)
    credential_path = os.path.join(credential_dir,
                                   'calendar-python-quickstart.json')

    store = Storage(credential_path)
    credentials = store.get()
    if not credentials or credentials.invalid:
        flow = client.flow_from_clientsecrets(CLIENT_SECRET_FILE, SCOPES)
        flow.user_agent = APPLICATION_NAME
        if flags:
            credentials = tools.run_flow(flow, store, flags)
        else: # Needed only for compatibility with Python 2.6
            credentials = tools.run(flow, store)
        print 'INFO: Storing credentials to ' + credential_path
    return credentials


def gather_backup_data():
    # backup sets are defined by the existence of a config directory
    hostlist = [ name for name in os.listdir(CONF_DIR) if os.path.isdir(os.path.join(CONF_DIR, name)) ]
    try:
        hostlist.remove('BackupSet1')
    except:
        pass
 
    previous_logfile = LOGFILE + '-' + last_sunday.strftime('%Y%m%d') + '.gz'
    if not os.path.isfile(previous_logfile):
        try:
            previous_logfile = max(glob.iglob('/var/log/mysql-zrm/mysql-zrm.log-*.gz'), key=os.path.getmtime)
        except:
            previous_logfile = None

    # check the logs for duration of backup for each host
    backup_length = { }
    with open(LOGFILE) as logfile:
        for host in hostlist:
            for line in logfile:
                if host in line:
                    if 'backup-time' in line:
                        length = line.split('=')[1].strip().split(':')
                        length = map(int, length)
                        backup_length[host] = datetime.timedelta(hours=length[0], minutes=length[1], seconds=length[2])
                        break
            logfile.seek(0)
            if not host in backup_length and previous_logfile:
                # gzip doesnt support 'with' until python 2.7
                oldlogfile = gzip.open(previous_logfile, 'r')
                try:
                    for line in oldlogfile:
                        if host in line:
                            if 'backup-time' in line:
                                length = line.split('=')[1].strip().split(':')
                                length = map(int, length)
                                backup_length[host] = datetime.timedelta(hours=length[0], minutes=length[1], seconds=length[2])
                                break
                finally:
                    oldlogfile.close()
            if not host in backup_length and args.verbose:
                backup_length[host] = datetime.timedelta(minutes=15)
                print 'WARNING: unable to find previous backup length in logs for ' + host + '. Defaulting to 15m.'
    
    crontab = [ ]
    with open('/var/spool/cron/mysql', 'r') as cronfile:
        for line in cronfile:
            if 'backup' in line:
                line = line.rstrip('\n').split()
                if line[0] != '#':
                    crontab.append([ line[9], ' '.join(line[0:5]) ])
    
    
    cronhosts = set()
    full_schedule = [ ]
    for line in crontab:
        cronhosts.add(line[0])
        if not args.no_audit:
            if not line[0] in hostlist:
                print 'CRITICAL: ' + line[0] + ' has a cron entry, but no backup set configured.'
        iter = croniter(line[1], week_start)
        while True:
            output = iter.get_next(datetime.datetime)
            if output > week_end:
                break
            # [hostname, start_time, end_time]
            full_schedule.append( [ line[0], output.isoformat() + 'Z', (output + backup_length[line[0]]).isoformat() + 'Z' ] )
    
    #safety check:
    if not args.no_audit:
        for host in hostlist:
            if not host in cronhosts:
                print 'CRITICAL: Backup Set ' + host + ' has no schedule!'
    
    return full_schedule


def batch_callback(request_id, response, exception):
    if args.verbose and exception is not None:
        print 'WARNING: error in API response: ', exception
        #sys.exit(1)

def clear_calendar(service, batch):
    if args.verbose:
        print 'INFO: clearing existing calendar entries.'
    events_result = service.events().list(calendarId=calendar, timeMin=week_start_google, timeMax=week_end_google, singleEvents=True, orderBy='startTime').execute()
    current_events = events_result.get('items', [])
    if current_events:
        for event in current_events:
            batch.add(service.events().delete(calendarId=calendar, eventId=event['id']))
        batch.execute()


def main():

    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--verbose", help="increase output verbosity", action="store_true", default=False)
    parser.add_argument("--no-audit", help="skip audit checks", action="store_true", default=False)
    parser.add_argument("--no-calendar", help="skip google calendar push", action="store_true", default=False)
    # using 'global' is hacky, so sue me :)
    global args
    args = parser.parse_args()

    full_schedule = gather_backup_data()

    credentials = get_credentials()
    http = credentials.authorize(httplib2.Http())
    service = discovery.build('calendar', 'v3', http=http)
    batch = service.new_batch_http_request(callback=batch_callback)

    #clear the calendar first
    if not args.no_calendar:
        clear_calendar(service, batch)

    #insert events
    if not args.no_calendar:
        if args.verbose:
            print 'INFO: creating calendar entries.'
        for item in full_schedule:
            event = {
              'summary': item[0],
              'start': { 'dateTime': item[1] },
              'end': { 'dateTime': item[2] },
            }
            batch.add(service.events().insert(calendarId=calendar, body=event))
        batch.execute()


        
if __name__ == '__main__':
    main()

