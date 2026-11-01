"""Geometry parity and presentation safety; no hardware/network needed."""
import copy
import unittest
from posture_hint import features, classify, display_classify, describe, PostureHints


def person():
    p = [[100., 100., .9] for _ in range(17)]
    for left, right, y in ((5,6,200),(11,12,400),(13,14,600),(15,16,800)):
        p[left] = [80.,float(y),.9];p[right] = [120.,float(y),.9]
    return dict(confidence=.9,box_xyxy=[50.,100.,150.,850.],keypoints_xyc=p)


class Hints(unittest.TestCase):
    def test_horizontal_torso_with_bent_legs_is_not_lying(self):
        f=dict(torso_angle_deg=60,body_angle_deg=65,knee_angle_deg=90,box_aspect_ratio=1.2)
        self.assertEqual(classify(f),'horizontal_candidate')
        self.assertEqual(display_classify(f),'uncertain_pose')
        f['knee_angle_deg']=170
        self.assertEqual(display_classify(f),'horizontal_candidate')
        f['body_angle_deg']=20
        self.assertEqual(display_classify(f),'uncertain_pose')
        f.update(torso_angle_deg=10,body_angle_deg=10,knee_angle_deg=170,box_aspect_ratio=.8)
        self.assertEqual(classify(f),'bending_candidate')
        self.assertEqual(display_classify(f),'uncertain_pose')
        f['torso_angle_deg']=40
        self.assertEqual(display_classify(f),'bending_candidate')

    def test_stability_uses_distinct_frames_and_resets_on_missing(self):
        hints=PostureHints()
        pose=dict(people=[person()],fall_state=dict(state='UPRIGHT'),frame_id=0,completed_ns=1000000000)
        self.assertIn('变化中',hints.update('s','RUNNING',pose,True))
        for _ in range(20):self.assertIn('变化中',hints.update('s','RUNNING',pose,True))
        pose.update(frame_id=1,completed_ns=1200000000)
        self.assertIn('变化中',hints.update('s','RUNNING',pose,True))
        pose.update(frame_id=2,completed_ns=1400000000)
        self.assertIn('直立',hints.update('s','RUNNING',pose,True))
        self.assertIn('等待',hints.update('s','RUNNING',pose,False))
        self.assertIn('变化中',hints.update('s','RUNNING',pose,True))
        self.assertIn('变化中',hints.update('new','RUNNING',pose,True))

    def test_vertical_angle_convention_and_no_mutation(self):
        p=person();before=copy.deepcopy(p);f=features(p)
        self.assertEqual(f['torso_angle_deg'],0)
        self.assertAlmostEqual(f['knee_angle_deg'],180)
        self.assertEqual(classify(f),'upright_candidate')
        self.assertEqual(p,before)
        pose=dict(people=[p],fall_state=dict(state='CANDIDATE',event=None))
        old=copy.deepcopy(pose)
        self.assertIn('直立',describe('RUNNING',pose,True))
        self.assertEqual(pose,old)  # Hint never changes candidate or its event.

    def test_pi_threshold_branches(self):
        common=dict(torso_angle_deg=0,body_angle_deg=0,knee_angle_deg=180,box_aspect_ratio=.3)
        for expected,changes in [
            ('horizontal_candidate',dict(torso_angle_deg=55,box_aspect_ratio=.9)),
            ('seated_candidate',dict(torso_angle_deg=45,knee_angle_deg=135)),
            ('bending_candidate',dict(torso_angle_deg=20,box_aspect_ratio=.48)),
            ('uncertain_pose',dict(torso_angle_deg=50)),
            ('insufficient_keypoints',dict(torso_angle_deg=None))]:
            self.assertEqual(classify(dict(common,**changes)),expected)

    def test_missing_and_degenerate_geometry(self):
        p=person();p['keypoints_xyc'][5][2]=.1
        self.assertEqual(classify(features(p)),'insufficient_keypoints')
        p=person();p['box_xyxy']=[1,1,1,2];self.assertIsNone(features(p))
        p=person();p['keypoints_xyc'][5][0]=float('nan');self.assertIsNone(features(p))
        p=person();p['keypoints_xyc']=[];self.assertIsNone(features(p))
        p=person();p['keypoints_xyc']=[[1,1,.9]]*17
        self.assertEqual(classify(features(p)),'insufficient_keypoints')

    def test_unavailable_and_ambiguous_observations_cannot_show_posture(self):
        pose=dict(people=[person()],fall_state=dict(state='UPRIGHT'))
        self.assertIn('等待',describe('RUNNING',pose,False))
        self.assertIn('回放',describe('RUNNING',pose,True,True))
        self.assertEqual(describe('DONE',pose,True),'姿态提示：—')
        pose['people']*=2;self.assertIn('多人',describe('RUNNING',pose,True))
        pose['people']=[];self.assertIn('未见人体',describe('RUNNING',pose,True))
        pose['people']=[person()];pose['people'][0]['confidence']=.1
        self.assertIn('置信度不足',describe('RUNNING',pose,True))
        pose['people']=[person()];pose['fall_state']['state']='UNCERTAIN'
        self.assertIn('无法判断',describe('RUNNING',pose,True))


if __name__=='__main__':unittest.main()
