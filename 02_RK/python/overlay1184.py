"""Transparent asynchronous elderly-monitoring overlay; coordinates already upright."""
import math
import cv2
import numpy as np

SKELETON=((5,6),(5,7),(7,9),(6,8),(8,10),(5,11),(6,12),(11,12),(11,13),(13,15),(12,14),(14,16))

def render(result,generation,session,now_ns):
    image=np.zeros((540,960,4),np.uint8)
    meta=dict(state='WAITING_FOR_POSE',pose_frame_id=None,bones=0,points=0,boxes=0,alarm=None,stale=True)
    if result is not None:
        if result['generation']!=generation or result['session']!=session:raise ValueError('Overlay session/generation mismatch')
        row=result['observation'];age=now_ns-row['completed_ns']
        if row['finished_ns']<row['completed_ns'] or now_ns<row['finished_ns']:raise ValueError('Overlay result timestamps invalid')
        state=row['fall_state'];alarm=state['alarm']
        stale=age>500_000_000
        meta.update(state='POSE_STALE' if stale else state['state'],pose_frame_id=row['frame_id'],age_ms=age/1e6,alarm=alarm,stale=stale,npu_ms=row['npu_ms'])
        def point(x,y):
            if not math.isfinite(x) or not math.isfinite(y):raise ValueError('Nonfinite pose coordinate')
            return (max(0,min(959,round(x/2))),max(0,min(539,round(y/2))))
        if not stale:
            for person in row['people']:
                if person['confidence']<.4:continue
                x1,y1,x2,y2=person['box_xyxy'];cv2.rectangle(image,point(x1,y1),point(x2,y2),(70,240,100,255),2);meta['boxes']+=1
                points=person['keypoints_xyc']
                if len(points)!=17:raise ValueError('Expected17 pose keypoints')
                for i,j in SKELETON:
                    if points[i][2]>=.4 and points[j][2]>=.4:
                        cv2.line(image,point(*points[i][:2]),point(*points[j][:2]),(0,220,255,255),2);meta['bones']+=1
                for x,y,c in points:
                    if c>=.4:cv2.circle(image,point(x,y),3,(255,140,0,255),-1);meta['points']+=1
    # Opaque pixels only: RGB is already valid for premultiplied alpha.
    cv2.rectangle(image,(0,0),(959,77),(18,18,18,255),-1)
    cv2.putText(image,'ELDERLY SAFETY | '+meta['state'],(12,27),cv2.FONT_HERSHEY_SIMPLEX,.65,(255,255,255,255),1,cv2.LINE_8)
    text='Waiting for an AI observation'
    if meta['pose_frame_id'] is not None:text=f"AI frame {meta['pose_frame_id']} | age {meta['age_ms']:.0f} ms | NPU {meta['npu_ms']:.1f} ms"
    cv2.putText(image,text,(12,56),cv2.FONT_HERSHEY_SIMPLEX,.55,(230,230,230,255),1,cv2.LINE_8)
    if meta['alarm'] is not None:
        a=meta['alarm'];cv2.rectangle(image,(0,490),(959,539),(0,0,210,255),-1)
        cv2.putText(image,f"FALL ALERT #{a['id']} {a['status']} - CHECK PERSON",(12,521),cv2.FONT_HERSHEY_SIMPLEX,.7,(255,255,255,255),2,cv2.LINE_8)
    return image,meta
