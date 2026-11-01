"""Local incident latch. Detector thresholds/model are unchanged; no remote delivery."""
import argparse
import json
import math
import sqlite3
import uuid
from pathlib import Path


class AlarmStore:
    def __init__(self, path):
        self.db = sqlite3.connect(str(path), timeout=5)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA synchronous=FULL')
        with self.db:
            self.db.execute('''CREATE TABLE IF NOT EXISTS incidents (
                id INTEGER PRIMARY KEY, status TEXT NOT NULL,
                opened_session TEXT NOT NULL, opened_s REAL NOT NULL,
                closed_session TEXT, closed_s REAL, manual_required INTEGER NOT NULL DEFAULT 0)''')
            self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS one_open ON incidents((1)) WHERE status != 'CLOSED'")
            self.db.execute('''CREATE TABLE IF NOT EXISTS transitions (
                seq INTEGER PRIMARY KEY, incident_id INTEGER NOT NULL,
                action TEXT NOT NULL, session TEXT NOT NULL, time_s REAL NOT NULL,
                detail TEXT NOT NULL)''')

    def active(self):
        row = self.db.execute("SELECT * FROM incidents WHERE status != 'CLOSED'").fetchone()
        return dict(row) if row else None

    def apply(self, action, session, time_s, detail='', incident_id=None):
        if action not in ('OPEN', 'RECOVER', 'ACK', 'RESOLVE', 'HOLD'):
            raise ValueError('unknown action')
        if not session or not isinstance(time_s, (int, float)) or not math.isfinite(time_s) or time_s < 0:
            raise ValueError('session and finite nonnegative monotonic time required')
        if action in ('ACK', 'RESOLVE') and (not detail.strip() or incident_id is None):
            raise ValueError('operator/reason and explicit incident ID required')
        # Serialize read/update with another local operator process.
        self.db.execute('BEGIN IMMEDIATE')
        try:
            row = self.active()
            if action == 'OPEN' and row is None:
                key = self.db.execute("INSERT INTO incidents(status,opened_session,opened_s) VALUES('ACTIVE',?,?)",
                                      (session, time_s)).lastrowid
            elif row is None or (incident_id is not None and incident_id != row['id']):
                if action in ('ACK', 'RESOLVE'):
                    raise ValueError('incident is no longer active')
                self.db.commit()
                return None
            elif action == 'OPEN' or (action == 'ACK' and row['status'] == 'ACKNOWLEDGED') or (action == 'HOLD' and row['manual_required']):
                self.db.commit()
                return None
            elif action == 'RECOVER' and (row['manual_required'] or row['opened_session'] != session):
                self.db.commit()
                return None
            else:
                key = row['id']
                if action == 'HOLD':
                    self.db.execute('UPDATE incidents SET manual_required=1 WHERE id=?', (key,))
                elif action == 'ACK':
                    self.db.execute("UPDATE incidents SET status='ACKNOWLEDGED' WHERE id=?", (key,))
                else:
                    self.db.execute("UPDATE incidents SET status='CLOSED',closed_session=?,closed_s=? WHERE id=?",
                                    (session, time_s, key))
            self.db.execute('INSERT INTO transitions(incident_id,action,session,time_s,detail) VALUES(?,?,?,?,?)',
                            (key, action, session, time_s, detail))
            self.db.commit()
            return dict(incident_id=key, action=action, session=session, time_s=time_s, detail=detail)
        except BaseException:
            self.db.rollback()
            raise

    def snapshot(self, path):
        target = Path(path)
        with target.open('xb'):
            pass
        destination = sqlite3.connect(str(target))
        try:
            self.db.backup(destination)
        finally:
            destination.close()

    def close(self):
        self.db.close()


class AlarmMonitor:
    def __init__(self, detector, store, session=None):
        self.detector, self.store = detector, store
        self.session = session or uuid.uuid4().hex
        # Recovery from a new detector after restart cannot identify an old person.
        self.owns_incident = False

    def update(self, time_s, people, width, height):
        result = dict(self.detector.update(time_s, people, width, height))
        event = result['event']
        transition = None
        if result.get('reason'):
            transition = self.store.apply('HOLD', self.session, time_s, result['reason'])
            self.owns_incident = False
        elif event == 'SUSPECTED_FALL':
            transition = self.store.apply('OPEN', self.session, time_s, 'pose candidate; accuracy unvalidated')
            if transition:
                self.owns_incident = True
        elif event == 'RECOVERED' and self.owns_incident:
            active = self.store.active()
            if active and not active['manual_required'] and active['opened_session'] == self.session:
                transition = self.store.apply('RECOVER', self.session, time_s,
                                              'detector observed sustained upright', active['id'])
                self.owns_incident = False
        active = self.store.active()
        result.update(detector_event=event,
                      event=event if transition and transition['action'] in ('OPEN', 'RECOVER') else None,
                      alarm_transition=transition, alarm=active,
                      alarm_requires_manual_resolution=bool(active and (active['manual_required'] or active['opened_session'] != self.session)))
        return result


def main():
    import time
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--action', choices=('status', 'ack', 'resolve'), default='status')
    parser.add_argument('--incident', type=int)
    parser.add_argument('--reason', default='')
    args = parser.parse_args()
    if not args.db.is_file():
        parser.error('existing database required')
    store = AlarmStore(args.db)
    try:
        change = None
        if args.action != 'status':
            change = store.apply(args.action.upper(), uuid.uuid4().hex, time.monotonic(),
                                 args.reason, args.incident)
        print(json.dumps(dict(transition=change, active=store.active())))
    finally:
        store.close()


if __name__ == '__main__':
    main()
