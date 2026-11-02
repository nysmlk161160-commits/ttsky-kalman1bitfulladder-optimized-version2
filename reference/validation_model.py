"""Pure-Python clock-edge model of the supplied DIV/MUL RTL.
Not a substitute for iverilog/cocotb synthesis or PNR checks.
"""
import random

def sign(v,n):
    v &= (1<<n)-1
    return v-(1<<n) if (v>>(n-1)) else v

class Divider:
    def __init__(self):
        self.remainder=0; self.trial_bits=0; self.difference=0
        self.quotient=0; self.equal_case=0; self.bit_index=0
        self.gain_index=0; self.carry=0; self.phase=0; self.running=0; self.done=0
    def result(self):
        return (self.equal_case<<6)|self.quotient
    def tick(self,start,p,s):
        self.done=0
        if start:
            self.remainder=p & 1023; self.quotient=0
            self.equal_case=int(s!=0 and p==s)
            self.gain_index=0; self.phase=0
            self.running=int(s!=0 and p!=s)
            if s==0 or p==s: self.done=1
        elif self.running:
            if not self.phase:
                self.trial_bits=(self.remainder<<1)&0xfff
                self.difference=0;self.carry=1;self.bit_index=0;self.phase=1
            else:
                denominator_bit=(s>>self.bit_index)&1 if self.bit_index!=11 else 0
                a=self.trial_bits&1; b=1-denominator_bit; cin=self.carry
                su=a^b^cin; co=(a&b)|((a^b)&cin)
                next_difference=(su<<11)|(self.difference>>1)
                next_quotient=((self.quotient<<1)|co)&63
                self.trial_bits >>= 1
                self.difference=next_difference
                self.carry=co
                if self.bit_index==11:
                    self.remainder=(next_difference&0x7ff) if co else ((self.remainder<<1)&0x7ff)
                    self.quotient=next_quotient
                    if self.gain_index==5:
                        self.running=0;self.done=1
                    else:
                        self.gain_index+=1;self.phase=0
                else:self.bit_index+=1

class Multiplier:
    def __init__(self):
        self.product=0;self.bit_count=0;self.bit_index=0
        self.carry=0;self.running=0;self.done=0
    def result(self):
        return sign((self.product>>6)&0x7ff,11)
    def tick(self,start,a,b):
        self.done=0
        if start:
            self.product=a&127;self.bit_count=0;self.bit_index=0
            self.carry=0;self.running=1
        elif self.running:
            if self.bit_index==12:
                self.product=((self.product>>1)|((self.product>>18)<<18))&0x7ffff
                self.bit_index=0;self.carry=0
                if self.bit_count==6:
                    self.running=0;self.done=1
                else:self.bit_count+=1
            else:
                b11=b&0x7ff
                multiplicand_bit=((b11>>10)&1) if self.bit_index==11 else ((b11>>self.bit_index)&1)
                a_bit=(self.product>>7)&1
                b_bit=(self.product&1)&multiplicand_bit
                cin=self.carry
                su=a_bit^b_bit^cin
                co=(a_bit&b_bit)|((a_bit^b_bit)&cin)
                self.product=(self.product&0x7f)|((((su<<11)|(self.product>>8))&0xfff)<<7)
                self.carry=co
                self.bit_index+=1

class Top:
    # IDLE, DIV_START, DIV_WAIT, X_START, X_WAIT, P_START, P_WAIT, FINISH
    def __init__(self, shared, z,x,p,r):
        self.shared=shared;self.z=z&1023;self.x=x&1023
        self.p=p&1023;self.r=r&1023
        self.delta=0;self.s=0;self.x_out=0;self.p_out=0
        self.ready=0;self.state=0
        self.div=Divider();self.mul=Multiplier()
    def tick(self,start):
        state=self.state
        div_start=(state==1)
        mul_start=(state==3 or state==5)
        div_result=self.div.result()
        mul_result=self.mul.result()
        mul_b=self.delta if state in (3,4) else self.p
        div_done=self.div.done;mul_done=self.mul.done
        old_s=self.s
        # Compute one 11-bit shared ALU, with exactly the Verilog operand selectors.
        alu_sub=state in (1,6)
        alu_a=(self.z if state==1 else self.x if state==4 else self.p)
        if state==1:alu_a=sign(self.z,10)&0x7ff
        alu_b_raw=self.r if state==0 else sign(self.x,10)&0x7ff if state==1 else mul_result&1023
        alu_b=alu_b_raw^(0x7ff if alu_sub else 0)
        alu_y=(alu_a+alu_b+int(alu_sub))&0x7ff

        if state==0 and start:
            self.s=alu_y if self.shared else (self.p+self.r)&0x7ff
            if not self.shared:
                self.delta=sign(self.z,10)-sign(self.x,10)
                self.delta=sign(self.delta,11)
            self.ready=0;self.state=1
        elif state==1:
            if self.shared:self.delta=sign(alu_y,11)
            self.state=2
        elif state==2:
            if div_done:self.state=3
        elif state==3:self.state=4
        elif state==4:
            if mul_done:
                self.x_out=(alu_y if self.shared else self.x+mul_result)&1023
                self.state=5
        elif state==5:self.state=6
        elif state==6:
            if mul_done:
                self.p_out=(alu_y if self.shared else self.p-mul_result)&1023
                self.state=7
        elif state==7:self.ready=1;self.state=0

        self.div.tick(div_start,self.p,old_s)
        self.mul.tick(mul_start,div_result,mul_b)

def run(cases):
    normal=fast=0
    for case in cases:
        z,x,p,r=case
        a=Top(False,z,x,p,r);b=Top(True,z,x,p,r)
        a.tick(True);b.tick(True)
        for n in range(1,400):
            a.tick(False);b.tick(False)
            assert a.state==b.state and a.ready==b.ready, (case,n,'state')
            assert a.x_out==b.x_out and a.p_out==b.p_out,(case,n,'result')
            if a.ready:
                assert n in (189,267),(case,n)
                k=(p<<6)//(p+r) if p+r else 0
                expected_x=(x+((k*(z-x))>>6))&1023
                expected_p=(p-((k*p)>>6))&1023
                assert (a.x_out,a.p_out)==(expected_x,expected_p),(case,n,(a.x_out,a.p_out),(expected_x,expected_p))
                if n==267:normal+=1
                else:fast+=1
                break
        else:raise AssertionError(('timeout',case))
    return normal,fast

if __name__=='__main__':
    cases=[
        (96, 0, 64, 320), (-96, 0, 64, 320),
        (0, 64, 64, 0), (32, -64, 32, 32),
        (511, -512, 1023, 0), (-512, 511, 1023, 0),
        (0, 0, 0, 1), (80, -80, 1, 1023),
        (127, -127, 1023, 1023), (-128, 127, 255, 255),
        (0, 0, 0, 0), (1, 0, 1, 0), (-1, 0, 1, 0),
        (511, 511, 0, 1023), (-512, -512, 0, 0),
    ]
    rng=random.Random(20261101)
    cases += [(rng.randrange(-512,512),rng.randrange(-512,512),rng.randrange(1024),rng.randrange(1024)) for _ in range(50)]
    print('Original 65-case model checks:',run(cases))
    rng=random.Random(123456)
    extra=[(rng.randrange(-512,512),rng.randrange(-512,512),rng.randrange(1024),rng.randrange(1024)) for _ in range(2000)]
    print('Extra 2000-case model checks:',run(extra))
