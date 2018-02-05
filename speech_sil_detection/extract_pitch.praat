form Test command line calls
    word wav_dir none
    word txt_dir none
    word basename none
endform

wav_name$ = wav_dir$ + "/" + basename$ + ".wav"
txt_name$ = txt_dir$ + "/" + basename$ + ".txt"

appendInfoLine:  wav_name$
appendInfoLine:  txt_name$

wav_praat$ = replace$ (basename$, ".", "_", 0)

appendInfoLine:  basename$
appendInfoLine:  wav_praat$

appendInfoLine:  wav_name$
Read from file... 'wav_dir$'/'basename$'.wav
deleteFile: "'txt_dir$'/'basename$'.pitch"
appendInfoLine:  txt_name$
select Sound 'wav_praat$'
To Pitch... 0.01 50 500
ts = Get start time
te = Get end time

select Pitch 'wav_praat$'
for i to (te-ts)/0.01
	time = ts + i * 0.01
	pitch = Get value at time: time, "Hertz", "Linear"
	if pitch = undefined
		pitch = 0.00
	endif
	result$ = "'time''tab$''pitch''newline$'"
	fileappend "'txt_dir$'/'basename$'.pitch" 'result$'
endfor
select Sound 'wav_praat$'
plus Pitch 'wav_praat$'
Remove

