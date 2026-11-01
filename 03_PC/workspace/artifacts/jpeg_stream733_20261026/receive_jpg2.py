"""Strict reference JPG2 receiver. Bytes remain private until terminal COMMIT."""
import struct,zlib

class Receiver:
    def __init__(self,max_bytes=16777216):
        self.max_bytes=max_bytes;self.pending=None;self.commits=[];self.aborts=[]
    def accept(self,packet):
        if len(packet)<64 or len(packet)%16:raise ValueError('packet length')
        magic,frame,seq,width,height=struct.unpack_from('<IIIHH',packet)
        offset,length,kind,decoded=struct.unpack_from('<IIII',packet,16)
        if magic!=0x3247504a or not width or not height or decoded!=width*height*3:raise ValueError('header')
        if kind not in (0,1,2) or not length or (kind and length!=16):raise ValueError('kind/length')
        if len(packet)!=32+(length+15)//16*16+16:raise ValueError('encoded length')
        trailer,crc,checked,zero=struct.unpack_from('<IIII',packet,len(packet)-16)
        body=packet[32:32+length]
        if trailer!=0x32435243 or checked!=length or zero or zlib.crc32(packet[:32]+body)!=crc:raise ValueError('CRC/trailer')
        if any(packet[32+length:-16]):raise ValueError('nonzero padding')
        if self.pending is None:
            if seq or offset:raise ValueError('transaction begins mid-frame')
            self.pending=dict(frame=frame,width=width,height=height,seq=0,size=0,chunks=[])
        p=self.pending
        if (frame,width,height,seq,offset)!=(p['frame'],p['width'],p['height'],p['seq'],p['size']):raise ValueError('identity/order/offset')
        if kind==0:
            if length>4096 or p['size']+length>self.max_bytes:raise ValueError('capacity')
            p['chunks'].append(body);p['size']+=length;p['seq']+=1
            return None
        reason,total,segments,version=struct.unpack('<IIII',body)
        if (total,segments,version)!=(p['size'],p['seq'],2) or (kind==1 and reason):raise ValueError('terminal')
        self.pending=None
        if kind==2:
            self.aborts.append(dict(frame=frame,reason=reason,provisional_bytes=total));return None
        if not total:raise ValueError('empty commit')
        image=b''.join(p['chunks']);self.commits.append(dict(frame=frame,width=width,height=height,data=image))
        return image

def read_capture(path):
    packet=bytearray()
    for line in path.read_text().splitlines():
        word,last=line.split();packet+=int(word,16).to_bytes(16,'little')
        if int(last):yield bytes(packet);packet.clear()
    if packet:raise ValueError('unterminated wire packet')
