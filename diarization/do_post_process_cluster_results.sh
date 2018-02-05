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
  echo "Usage: $0 <in:fn-wav> <in:segs.lst> <in:speech-sil.lst> <out:dir-out>"
  echo "  fn-wav    - audio file to be segmented into speech/silence"
  echo "  fn-segs   - segmentation file defining segments to be clustered"
  echo "  fn-speechsil - speech silence segmentation for all sub-files"
  echo "  dir-out   - directory within which all output created"
  echo "e.g.: $0 abc.wav models.lst /tmp"
  exit 1;
fi

# -----------------------------------------------------------------------------

dir_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

wav=$1
lst=$2
sil=$3
dir_out=$4

dir_work=$dir_out/re-clustering
safe_remove_dir $dir_work 0
mkdir -p $dir_work

# -----------------------------------------------------------------------------

# Check required scripts / software

binaries=( sox soxi sfbcep scluster sgminit sgmestim sgmlike spfcat perl ) 
scripts=( file_list.pl
          merge_segment_files.pl
	  merge_speech_sil_files.pl
	  read_scluster_results_and_relabel_segment_file.pl
          interpret_scluster_results.v1.pl
	  cluster.pl
	  smooth_sgmlike_results.pl )

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

if [ ! -e "$dir_out/${bn}.wav" ]; then
  echo "Info: Converting '$wav' to wav file -> $dir_out/${bn}.wav"
  sox $wav $dir_out/${bn}.wav
else
  echo "Info: using $dir_out/${bn}.wav"
  soxi $wav
  soxi $dir_out/${bn}.wav
fi

if [ ! -e "$dir_out/${bn}.mfcc" ]; then
  echo "Info: Extracting features"
  sfbcep -f ${sf} --mel --num-filter=40 --num-cep=20 \
         $dir_out/${bn}.wav $dir_out/${bn}.mfcc
else
  echo "Info: using $dir_out/${bn}.mfcc"
fi

mfcc=$dir_out/${bn}.mfcc

# -----------------------------------------------------------------------------

# Create unique list of models
seg_merged=$dir_work/${bn}.gmm.boost.merged.seg
perl $dir_script/merge_segment_files.pl $lst $seg_merged

sil_merged=$dir_work/${bn}.speech_sil.seg
perl $dir_script/merge_speech_sil_files.pl $sil $sil_merged

seg=$seg_merged
seg_orig=$seg

wc -l $seg_orig

cp $seg $dir_work/${bn}.txt # .txt, because we want to remove all .seg
seg=$dir_work/${bn}.txt # rename ${seg}

for x in 3 4
do
  echo "Info: round $x"

  for i in 1.5 2.0 2.5 3.0 5.0 10.0
  do
    num_c_init=1
    num_c_end=0

    while [ $num_c_init -ne $num_c_end ];
    do
      rm -f $dir_work/*.mfcc
      #rm -f $dir_work/*.seg

      perl $dir_script/file_list.pl $dir_work $seg $i > $dir_work/file_list.lst.tmp
      cat $dir_work/file_list.lst.tmp | grep "YYY" | sed "s/YYY: //g" > $dir_work/file_list.lst
      cat $dir_work/file_list.lst.tmp | grep "XXX" | sed "s/XXX: //g" > $dir_work/file_list.seg

      num_c_init=`cat $seg | awk '{print $1}' | sort -u | wc -l`

      echo -e "$mfcc $dir_work/file_list.seg" > $dir_work/train.script

      for lab in `cat $seg | awk '{print $1}' | sort -u`
      do
	echo "'$lab'"
	spfcat --label=$lab --file-list=$dir_work/train.script $dir_work/${lab}.mfcc
      done

      scluster --full -i --log=$dir_work/out.log --file-list=$dir_work/file_list.lst

      perl $dir_script/read_scluster_results_and_relabel_segment_file.pl $dir_work/file_list.lst $seg
      wc $seg $seg_orig

      num_c_end=`cat $seg | awk '{print $1}' | sort -u | wc -l`
      echo "Info: $i COUNTS $num_c_init $num_c_end"
    done
  done

  # Select segments for retraining models
  # - min of 2 segments
  # - only samples of >= 1.5s
  # - total of at least 10s
  # - retrain, classify LL
  perl $dir_script/interpret_scluster_results.v1.pl $seg > ${seg}.log

  cat ${seg}.log |\
	  grep "YYY" | awk '{print $2 " " $3 " " $4}' \
	  > $dir_work/${bn}.train


  # Train background model on all speech
  echo -e "${mfcc} $seg_orig" \
	  > $dir_work/train.spks.all.script
  file_list=$dir_work/train.spks.all.script

  num_comp=8
  dir_models=$dir_work/models_round${x}
  mkdir -p $dir_models
  rm -f $dir_models/ubm_init.gmm
  rm -f $dir_models/ubm.gmm
  rm -f $dir_models/C_*.gmm

  if [ $x -eq 3 ]; then
    # Traing one global UBM
    sgminit --verbose=1 --quantize \
	    --mahalanobis --num-comp=$num_comp \
	    --file-list=$file_list $dir_models/ubm_init.gmm

    sgmestim --verbose=1 \
	     --file-list=$file_list \
	     --output=${dir_models}/ubm.gmm $dir_models/ubm_init.gmm
  else
    cp -v $dir_work/models_round3/ubm_init.gmm $dir_models/
  fi

  echo -e "${mfcc} $dir_work/${bn}.train" \
	  > $dir_work/train.spks.select.script
  file_list=$dir_work/train.spks.select.script

  echo "Info: training speaker GMMs"

  for lab in `cat $dir_work/${bn}.train |\
	  awk '{print $1}' | sort -u`
  do
     sgmestim --verbose=1 --label=$lab \
	      --file-list=$file_list \
	      --output=${dir_models}/${lab}.gmm $dir_models/ubm_init.gmm \
	      2> $dir_work/${lab}.log
     if [ `cat $dir_work/${lab}.log |\
               grep "$num_comp defunct component after iteration" |\
	       wc -l` -ge 1 ]; then
       echo "Error! $lab has $num_comp defunct mixtures"
       rm ${dir_models}/${lab}.gmm
     fi
  done

  # ALL
  ls -l $dir_models | grep "C_.*gmm" | awk -v d=$dir_models '{print d "/" $NF}' >  $dir_work/models.lst
  ls -l $dir_models | grep "ubm.gmm" | awk -v d=$dir_models '{print d "/" $NF}' >> $dir_work/models.lst

  echo -e "${mfcc} $sil_merged" \
	  > $dir_work/all.speech-segs.script

  # Rather only score the segments that were trained on. The other are either
  # unreliable, or can lead to confusion.

  file_list=$dir_work/all.speech-segs.script

  sgmlike --list=$dir_work/models.lst \
	  --file-list=$file_list \
	  -s -n > $dir_work/score.log
  cp $dir_work/score.log $dir_work/score.${x}.log

  perl $dir_script/cluster.pl $dir_work/models.lst $dir_work/score.${x}.log > $dir_work/cluster.${x}.log
  cat $dir_work/cluster.${x}.log | grep "XXX" | awk '{print $2 " " $3 " " $4}' > $dir_work/${bn}.train

  perl $dir_script/interpret_scluster_results.v1.pl $dir_work/${bn}.train > $dir_work/${bn}.train.log
  cat $dir_work/${bn}.train.log | grep "YYY" | awk '{print $2 " " $3 " " $4}' > $dir_work/${bn}.txt

  wc $dir_work/${bn}.train $dir_work/${bn}.txt

  seg=$dir_work/${bn}.txt # rename ${seg}

done

echo -e "${mfcc} $dir_work/${bn}.train" \
  > $dir_work/train.spks.select.script
file_list=$dir_work/train.spks.select.script

echo "Info: training speaker GMMs"
num_comp=8
dir_models=$dir_work/models_round4
mkdir -p $dir_models
rm -f $dir_models/C_*.gmm
for lab in `cat $dir_work/${bn}.train |\
  awk '{print $1}' | sort -u`
do
sgmestim --verbose=1 --label=$lab \
      --file-list=$file_list \
      --output=${dir_models}/${lab}.gmm $dir_models/ubm_init.gmm \
      2> $dir_work/${lab}.log
if [ `cat $dir_work/${lab}.log |\
       grep "$num_comp defunct component after iteration" |\
       wc -l` -ge 1 ]; then
echo "Error! $lab has $num_comp defunct mixtures"
rm ${dir_models}/${lab}.gmm
fi
done

# ALL
ls -l $dir_models | grep "C_.*gmm" | awk -v d=$dir_models '{print d "/" $NF}' >  $dir_work/models.lst
ls -l $dir_models | grep "ubm.gmm" | awk -v d=$dir_models '{print d "/" $NF}' >> $dir_work/models.lst

echo -e "${mfcc} $sil_merged" \
  > $dir_work/all.speech-segs.script

# Rather only score the segments that were trained on. The other are either
# unreliable, or can lead to confusion.

file_list=$dir_work/all.speech-segs.script

sgmlike --list=$dir_work/models.lst \
  --file-list=$file_list \
  -s -n > $dir_work/score.log
cp $dir_work/score.log $dir_work/score.5.log

i=0.4
perl $dir_script/smooth_sgmlike_results.pl $dir_work/models.lst \
$dir_work/score.5.log $i |\
grep "XXX:" | awk '{print $2 " " $3 " " $4}' > $dir_work/${bn}.gmm.boost.seg
perl $dir_script/interpret_scluster_results.v1.pl $dir_work/${bn}.gmm.boost.seg |\
grep "XXX:" | awk '{print $2 " " $3 " " $4}' > $dir_work/${bn}.gmm.boost.merged.seg

cp -v $sil_merged $dir_out/
cp -v $dir_work/${bn}.gmm.boost.merged.seg $dir_out/
wc -l $dir_out/${bn}.gmm.boost.merged.seg

echo "Done training round 3 & 4"
