import numpy as np
import wave
import sys
import subprocess
import os
import os.path
from numpy import mean, sqrt, square
import matplotlib.pyplot as plt

fine_tune_win = 0.30
fine_tune_win_pitch = 0.50

# -----------------------------------------------------------------------------
# FUNCTIONS

# f_shift in ms
def f2sec(i,f_shift):
    return i*f_shift/1000.0

def sec2f(i, f_shift):
    return 1000*i/f_shift

def check_pitch(pitch, ts, te):
    tot  = 0
    has_pitch = 0
    if max(pitch.shape) < te:
        print "Warning: te out of bounds: ", te, max(pitch.shape)
        te = max(pitch.shape) - 1
    for i in range(int(ts),int(te+1)):
        if pitch[i,1] > 0:
            has_pitch += 1
        tot += 1
    if has_pitch > 0.1*tot:
        return 1
    return 0

def fine_tune_pitch_left(pitch, i, lim):
    i = np.int(i)
    # Check if there's pitch within win
    last_pitch = i
    j = max(0,int(i - sec2f(lim, f_shift)))
    while i >= j:
        if pitch[i,1] > 0:
            last_pitch = i - 1
            #print "XXXXXXXXXXXXXXXXXXXXX"
        i -= 1
    return last_pitch

def fine_tune_pitch_right(pitch, i, lim):
    i = np.int(i)
    # Check if there's pitch within win
    last_pitch = i
    j = min(max(pitch.shape) - 1, int(i + sec2f(lim, f_shift)))
    while i <= j:
        if pitch[i,1] > 0:
            last_pitch = i + 1
            #print "YYYYYYYYYYYYYYYYYYYYY"
        i += 1
    return last_pitch
    

# Find the time when the graph crosses line x,
# at most lim secs to the left
def fine_tune_left(values, i, x, lim):
    i = np.int(i)
    th_up = i - sec2f(lim, f_shift)
    if th_up < 0:
        th_up = 0
    #print "I: %d J: %d" %(i, th_up)
    bv = values[int(th_up)]
    bi = th_up
    j = i
    while j >= th_up:
        if values[j] < x:
            bv = values[j]
            bi = j
            break
        j -= 1
    # If there is a small peak within 500ms, include it. May possibly be release of plosives
    if int(th_up) < bi:
        j_max_v = max(values[int(th_up):bi])
        z = max(np.where(values[int(th_up):bi] == max(values[int(th_up):bi])))
        j_max_i = bi - (bi - int(th_up) - max(z))
    #print "XXX: %f %d %d %d\n" %(j_max_v, j_max_i, i, bi)
        #if j_max_v > 2*(bv/3.0):
        if j_max_v > bv:
            j = j_max_i
            while j >= th_up:
                if values[j] < bv/3.0:
                    return j
                j -= 1

    j = i
    while j >= th_up:
        if values[j] < bv/3.0:
            return j
        j -= 1

    j = i - 1
    while j >= th_up/2.0:
        if values[j] > values[j + 1]:
            return j
        j -= 1
    return bi

def fine_tune_right(values, i, x, lim):
    i = np.int(i)
    th_up = i + sec2f(lim, f_shift)
    if th_up >= max(values.shape) - 1:
        th_up = max(values.shape) - 1
    #print "+I: %d J: %d" %(i, th_up)
    bv = values[int(th_up)]
    bi = th_up
    j = i
    while j <= th_up:
        if values[j] < x:
            bv = values[j]
            bi = j
            break
        j += 1


    if bi < int(th_up):
        j_max_v = max(values[bi:int(th_up)])
        z = np.where(values[bi:int(th_up)] == max(values[bi:int(th_up)]))
        j_max_i = bi + max(max(z))
        #if j_max_v > 2*(bv/3.0):
        if j_max_v > bv:
            j = j_max_i
            while j <= th_up:
                if values[j] < bv/3.0:
                    return j
                j += 1
    j = i
    while j <= th_up:
        if values[j] < bv/3.0:
            return j
        j += 1

    j = i
    while j <= th_up/2.0:
        if values[j] > values[j - 1]:
            return j
        j += 1
    return bi

# Thumb suck rule to recalculate the rms min and max for every minute of audio
# Should guard against instances where there's a minute of silence though,
# therefore, raise a warning and resort to 20% of rms values if calculated
# values are less than 20%
def rms_sanity_check(old_min, old_max, new_min, new_max):
    if new_min < 0.2*old_min:
        print "Warning: rms min value too low! ", old_min, " -> ", new_min
        new_min = old_min * 0.2
    if new_max < 0.2*old_max:
        print "Warning: rms max value too low! ", old_max, " -> ", new_max
        new_max = old_max * 0.2
    return (new_min, new_max)
# -----------------------------------------------------------------------------

total = len(sys.argv)

if total - 1 != 4:
    sys.exit("Usage: ./segment_rms.py <in:wav> <out:dir> <start> <dur>")

# Read the wav file
spf = wave.open(str(sys.argv[1]),'r')
dir_out=str(sys.argv[2])
start= int(float(sys.argv[3]))
dur = int(float(sys.argv[4]))

bn=os.path.basename(str(sys.argv[1]))
bn=os.path.splitext(bn)[0]
print "BASE: %s" %(bn)

# Get pitch using praat
# Pitch
wav_dir = os.path.dirname(str(sys.argv[1]))
this_script_dir = os.path.dirname(os.path.realpath(__file__))
subprocess.call(['praat', '--run', this_script_dir + '/extract_pitch.praat', wav_dir, dir_out, bn])
pitch_file = dir_out + "/" + bn + ".pitch"
pitch = np.loadtxt(pitch_file)

fs = spf.getframerate()
nf = spf.getnframes()

# Extract Raw Audio from Wav File
signal = spf.readframes(-1)
signal = np.fromstring(signal, 'Int16')

# Calculate the intensity every 10ms over 25ms window
f_dur = 25
f_shift = 10

s_shift = f_shift*fs/1000
s_dur   = f_dur*fs/1000

# A frame will be f_dur*fs/1000
# Number of frames
num_frames = int(round(nf/s_shift) - 2)

rms = np.zeros(num_frames)
x = np.zeros(num_frames)

y_max = np.zeros(num_frames)

i = 0
j = 0

np.set_printoptions(linewidth=400)
while i < max(signal.shape) and j < num_frames:
    i_end = i + s_shift - 1
    mu = mean(square(signal[i:i_end].astype(np.int32)))
    if mu > 0:
        rms[j] = sqrt(mu)
    else:
        rms[j] = 0
    x[j] = i
    i += s_shift
    j += 1

# Estimate a max and a min value
rms_sorted = np.sort(rms)
rms_min = mean(rms_sorted[0:1000])
rms_i_end = max(rms_sorted.shape) - 1
rms_max = mean(rms_sorted[(rms_i_end - 1000):rms_i_end])
print "(Old) Recalculating vals: ", rms_min, " - ", rms_max
glob_rms_min = rms_min
glob_rms_max = rms_max

#rms_window = 180000 # 3 minutes
rms_window = 60000 # 3 minutes
rms_s = 0
rms_e = int(min(rms_window/f_shift,max(rms.shape) - 1))

rms_sorted = np.sort(rms[rms_s:rms_e])
rms_min = mean(rms_sorted[0:1000])
rms_i_end = max(rms_sorted.shape) - 1
rms_max = mean(rms_sorted[(rms_i_end - 1000):rms_i_end])
print "(New) Recalculating vals: ", rms_min, " - ", rms_max
(rms_min, rms_max) = rms_sanity_check(glob_rms_min, glob_rms_max, rms_min, rms_max)

# Iterate over the signal using a state machine
# (1) If speech is encountered, activate (min duration?) - state 1
# (2) When line crossed again, keep count. If 500ms has passed without another crossing, enter sil state
# (3) Exit sil state when speech encountered - state 0
state = 0
timer = 0
timer_0_start = 0
timer_1_start = 0
timer_2_start = 0

timer_0_end = 0
timer_1_end = 0

state_2_max = 500 # ms

f_out = dir_out + '/' + bn + '.segment'
f = open(f_out, 'w')

lines = []

#plt.plot(rms)
#plt.show()

recalc_rms_params = 0
for i in range(max(rms.shape)):
    if int(i*f_shift) % rms_window == 0:
        # recalculate rms_min & rms_max
        recalc_rms_params = 1

    if state == 0:
        if recalc_rms_params == 1:
            recalc_rms_params = 0
            rms_s = rms_e
            rms_e = int(min(rms_window/f_shift + rms_s, max(rms.shape) - 1))
            print "Recalculating time: ", rms_s, " - ", rms_e
            if rms_e > rms_s + 2000:
                rms_sorted = np.sort(rms[rms_s:rms_e])
                rms_min = mean(rms_sorted[0:1000])
                rms_i_end = max(rms_sorted.shape) - 1
                rms_max = mean(rms_sorted[(rms_i_end - 1000):rms_i_end])
                print "Recalculating vals: ", rms_min, " - ", rms_max
                (rms_min, rms_max) = rms_sanity_check(glob_rms_min, glob_rms_max, rms_min, rms_max)

        if rms[i] >= rms_max/3:
            state = 1
            timer_0_end   = i
            timer_0_end = fine_tune_left(rms, i, rms_max/20, fine_tune_win)
            timer_0_end = fine_tune_pitch_left(pitch, timer_0_end, fine_tune_win_pitch)
            timer_1_start = timer_0_end
    elif state == 1:
        #ts = lines[i][1]
        #te = lines[i][2]
        if rms[i] < rms_max/3:
            state = 2
            timer_2_start = i
    elif state == 2:
        if rms[i] >= rms_max/3:
            state = 1
        elif (i - timer_2_start)*f_shift > state_2_max:
            state = 0
            timer_1_end   = fine_tune_right(rms, timer_2_start, rms_max/20, fine_tune_win)
            timer_1_end   = fine_tune_pitch_right(pitch, timer_1_end, fine_tune_win_pitch)
            timer_0_start = timer_1_end
            ts=timer_1_start
            te=timer_1_end
            lines.append([bn, ts, te, bn, ts/100.0, te/100.0])
    y_max[i] = rms_max

# TODO: Fine tune
# TODO: End
if timer_0_end < max(rms.shape) - 1 and timer_1_end < max(rms.shape) - 1:
    if state == 0:
        timer_0_end = i
    else:
        timer_1_end = i
        ts=timer_1_start
        te=timer_1_end
        lines.append([bn, ts, te, bn, ts/100.0, te/100.0])

# Write the lines to file, merging overlapping segments
plot_lines_s = []
plot_lines_e = []
flag_print_next_line = 1
for i in range(0,len(lines)):
    bn = lines[i][0]
    ts = lines[i][1]
    te = lines[i][2]

    if i < len(lines) - 1:
        # See if the next segments's start time overlaps with the current segment
        ts_next = lines[i+1][1]
        if ts_next <= te:
            # Merge the segments
            lines[i+1][1] = ts
        else:
            if check_pitch(pitch, ts, te) > 0:
                line = "%s_%06d-%06d %s %.2f %.2f\n" %(bn, ts, te, bn, ts/100.0, te/100.0)
                f.write(line)
                plot_lines_s.append(ts)
                plot_lines_e.append(te)
            else:
                print "No pitch values: %s %.2f %2.f\n" %(bn, ts/100.0, te/100.0)
    else:
        if check_pitch(pitch, ts, te) > 0:
            line = "%s_%06d-%06d %s %.2f %.2f\n" %(bn, ts, te, bn, ts/100.0, te/100.0)
            f.write(line)
            plot_lines_s.append(ts)
            plot_lines_e.append(te)
        else:
            print "No pitch values: %s %.2f %2.f\n" %(bn, ts/100.0, te/100.0)

f.close()
