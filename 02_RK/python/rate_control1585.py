"""Keep the eight-frame hardware queue guard relative to actual command issue."""
from rate_control1558 import Controller as Previous


class Controller(Previous):
    def issued_frontier(self,frame):
        if type(frame) is not int or frame<self.last_index:
            raise ValueError('Command frontier precedes observed frame')
        self.last_change=max(self.last_change,frame)

    def observe(self,index,size,actual_quality,preprocess_mode):
        # A pipe can contain older committed frames when the command is issued.
        # They predate that command; they are not late hardware responses.
        frontier=self.last_change
        buffered=(actual_quality==self.previous_quality and actual_quality!=self.quality
                  and index<=frontier and index>self.last_index)
        if buffered:self.last_change=index-1
        try:
            row=super().observe(index,size,actual_quality,preprocess_mode)
        finally:
            if buffered:self.last_change=frontier
        row['command_commit_frontier']=self.last_change
        return row
