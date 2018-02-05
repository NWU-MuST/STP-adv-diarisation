#!/bin/bash
set -eu

# -----------------------------------------------------------------------------
# Function: remove_dir

# If a dir exists, does rm -r dir, else prints info message about non-existant
# directory

function remove_dir {
  if [ $# -ne 1 ]; then
    echo "Usage: $FUNCNAME <dir>"
    exit $E_BAD_ARGS
  fi
  dir=$1

  if [ -d $dir ]; then
    echo "INFO: Recursively removing '$dir'...";
    rm -r $dir
  else
    echo "INFO: '$dir' does not exist!"
  fi
}

# -----------------------------------------------------------------------------

# Function: safe_remove_dir
# 
# "Safe remove" because:
# - option to prompt a user before deleting a non-empty directory 
# - does not use -f (which is necessary if a directory does not exist, otherwise
#   bash script exists due to set -eu.

function safe_remove_dir {
  if [ $# -ne 2 ]; then
    echo "Usage: $FUNCNAME <dir> <1/0 (prompt/don't prompt)>"
    exit $E_BAD_ARGS
  fi

  dir=$1
  prompt_before_remove=$2

  if [ -d $dir ]; then
    if [ "$(ls -A $dir)" ]; then
       echo "Warning: '$dir' is not empty!"
       if [ $prompt_before_remove -eq 1 ]; then
         prompt_remove_dir $dir
       else
         remove_dir $dir
       fi
    else
      echo "Info: '$dir' is empty. Removing..."
      rmdir $dir
    fi
  else
    echo "Warning: '$dir' does not exist."
  fi
}

# -----------------------------------------------------------------------------

if [ $# -ne "4" ]; then
  echo "Usage: $0 <in:fn-wav> <out:fn-seg> <out:dir-out> <nj>"
  echo "  fn-wav    - audio file to be segmented into speech/silence"
  echo "  fn-seg    - file where segmentation info should be saved to"
  echo "  dir-out   - directory within which all output created"
  echo "  nj        - number of processors available for parallelization"
  echo "e.g.: $0 abc.wav abc.seg /tmp 4"
  exit 1;
fi

# -----------------------------------------------------------------------------

dir_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

wav=$1
seg=$2
dir_out=$3
nj=$4

dir_work=$dir_out/speech_sil_detection
safe_remove_dir $dir_work 0
mkdir -p $dir_work

# -----------------------------------------------------------------------------

# Check required scripts / software

binaries=( sox soxi praat sfbcep sgminit sgmestim sviterbi python perl ) 
scripts=( extract_pitch.praat segment_rms.py add_silence.pl split_wav.pl combine_split_segments.pl )

exit_status=0
missing=""
for bin in "${binaries[@]}"; do
  type -p $bin &> /dev/null
  if [ $? -ne 0 ]; then
    missing="$missing [$bin]"
    exit_status=1
  fi
done

for script in "${scripts[@]}"; do
  if [ ! -e "$dir_script/$script" ]; then
    missing="$missing [$script]"
    exit_status=1
  fi
done

if [ $exit_status = 1 ]; then
  echo "Error: Binaries/scripts missing! $missing" 1>&1
  exit $exit_status
else
  echo "Info: All required software present"
fi

# -----------------------------------------------------------------------------

# Get audio file information

bn=`echo $wav | awk -F '/' '{print $NF}' | sed "s/\.[^\.]\+$//g"`
dur=`soxi $wav | grep "Duration" | awk '{print $3}' | awk -F ':' '{print $1*60*60 + $2*60 + $3}'`
sf=`soxi $wav | grep "Sample Rate" | awk '{print $NF}'`

# -----------------------------------------------------------------------------

# Convert the audio to wav file (in case other format)

echo "Info: Converting '$wav' to wav file -> $dir_work/${bn}.wav"
sox $wav $dir_work/${bn}.wav

# Do initial speech / sil segmentation using praat & python

cd $dir_script
echo "Info: Intial speech / silence segmentation using praat + python"

perl $dir_script/split_wav.pl $dir_work/${bn}.wav $nj $dir_work

segments=""
for i in `seq 1 $nj`;
do
  (
  dur=`soxi $dir_work/${bn}-${i}.wav | grep "Duration" | awk '{print $3}' | awk -F ':' '{print $1*60*60 + $2*60 + $3}'`
  echo "python $dir_script/segment_rms.py $dir_work/${bn}-${i}.wav $dir_work 0 $dur"
  python $dir_script/segment_rms.py $dir_work/${bn}-${i}.wav $dir_work 0 $dur
  ) &
  segments="$segments $dir_work/${bn}-${i}.segment"
done

wait

perl $dir_script/combine_split_segments.pl \
	$dir_work/${bn}.wav $nj $segments > $dir_work/${bn}.segment
wc $dir_work/${bn}.segment

cat $dir_work/${bn}.segment |\
    awk '{print "speech " $3 " " $4}' > $dir_work/${bn}.speech.init

perl $dir_script/add_silence.pl $dir_work/${bn}.wav \
	                        $dir_work/${bn}.speech.init \
				$dir_work/${bn}.lab

echo "Info: Refining speech / silence segmentation using audioseg"
echo "Info: Extracting features"
sfbcep -f ${sf} --mel --num-filter=40 --num-cep=20 \
       $dir_work/${bn}.wav $dir_work/${bn}.mfcc

echo -e "$dir_work/${bn}.mfcc $dir_work/${bn}.lab" > $dir_work/train.script

num_comp=8
file_list=$dir_work/train.script
dir_out=$dir_work/models
mkdir -p $dir_out

for lab in speech sil
do
   cmnd="sgminit --verbose=1 --label=$lab --quantize --mahalanobis --num-comp=$num_comp --file-list=$file_list $dir_out/${lab}_init.gmm"
   echo $cmnd
   $cmnd

   cmnd="sgmestim --verbose=1 --label=$lab --file-list=$file_list --output=${dir_out}/${lab}.gmm $dir_out/${lab}_init.gmm"
   echo $cmnd
   $cmnd
done

# -----------------------------------------------------------------------------

# Viterbi decode with speech / sil HMM

echo "2
speech $dir_work/models/speech.gmm
sil $dir_work/models/sil.gmm
0.5 0.5
0.2 0.8
0.8 0.2
0.5 0.5" > $dir_work/models/speech+sil.hmm

sviterbi -p 20 $dir_work/models/speech+sil.hmm $dir_work/${bn}.mfcc $dir_work/vit.out

cat $dir_work/vit.out | grep "speech" | awk '{print $1 " " $2 " " $3}' > $dir_work/${bn}.seg
perl $dir_script/add_silence.pl $dir_work/${bn}.wav \
	                        $dir_work/${bn}.seg \
			        $dir_work/${bn}.plus_sil.seg

cp -v $dir_work/${bn}.seg $seg
cp -v $dir_work/${bn}.seg $dir_work/final.seg

# Make the converted wav and mfcc file available to other processes
mv -v $dir_work/${bn}.mfcc $dir_out/
mv -v $dir_work/${bn}.wav  $dir_out/

# -----------------------------------------------------------------------------

echo "Info: Done speech silence segmentation!"
