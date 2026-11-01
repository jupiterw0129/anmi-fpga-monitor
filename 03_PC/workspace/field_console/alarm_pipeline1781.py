"""Generate independent alarm modules; retain accepted SD1765 and direct media."""
from sd_pipeline1765 import sources as sd_sources, augment_controller as sd_controller


def sources(root):
    names=sd_sources(root)
    original=root.parent/'artifacts/native_required1138_20261028'
    result={
        'event_record1781.py':(original/'event_record1256.py').read_text().replace('from jpeg_event1256 import','from jpeg_event1781 import'),
        'event_finalize1781.py':(original/'event_record1264.py').read_text().replace('from event_record1256 import','from event_record1781 import'),
        'event_worker1781.py':(original/'event_worker1267.py').read_text().replace('from event_record1264 import','from event_finalize1781 import'),
        'live_record1781.py':(root/'live_record1765.py').read_text().replace('from event_worker1267 import','from event_worker1781 import'),
    }
    worker=result['event_worker1781.py']
    old="                        self.stats['discarded_jobs_on_abort']+=len(self.jobs);self.jobs.clear();self.pending_bytes=0;break"
    assert worker.count(old)==1
    worker=worker.replace(old,'                        break')
    old='        finally:\n            self.ready.set()\n'
    new='''        finally:
            if self.error or self.aborting:
                with self.condition:
                    self.stats['discarded_jobs_on_abort']+=len(self.jobs)
                    self.pending_alarms-=sum(kind=='alarm' for kind,args,size in self.jobs)
                    self.jobs.clear();self.pending_bytes=0
            self.ready.set()
'''
    assert worker.count(old)==1
    result['event_worker1781.py']=worker.replace(old,new)
    for name,text in result.items():
        compile(text,name,'exec');(root/name).write_text(text,encoding='utf-8')
    return (*names,*result,'jpeg_event1781.py')


def augment_controller(text):
    text=sd_controller(text)
    assert text.count("'live_record1765.py'")==1
    return text.replace("'live_record1765.py'","'live_record1781.py'")
