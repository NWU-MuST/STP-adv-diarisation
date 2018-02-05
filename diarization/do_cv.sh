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
  echo "Usage: $0 <in:fn-wav> <in:seg-merged> <in:speech-sil-merged> <out:dir-out>"
  echo "  fn-wav            - audio file to be segmented into speech/silence"
  echo "  seg-merged        - single merged segmentation file"
  echo "  speech-sil-merged - speech silence segmentation file"
  echo "  dir-out           - directory within which all output created"
  echo "e.g.: $0 abc.wav clusters.seg speech-sil.seg /tmp"
  exit 1;
fi

# -----------------------------------------------------------------------------

dir_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

wav=$1
seg_merged=$2
sil_merged=$3
dir_out=$4

dir_work=$dir_out/cv
safe_remove_dir $dir_work 0
mkdir -p $dir_work

# -----------------------------------------------------------------------------

# Check required scripts / software

binaries=( sox soxi sfbcep scluster sgminit sgmestim sgmlike spfcat perl ) 
scripts=( interpret_scluster_results.v1.pl
          smooth_sgmlike_results.pl
	  split_segment_into_folds.pl )

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
seg=$seg_merged
seg_orig=$seg

wc -l $seg_orig
  
perl $dir_script/interpret_scluster_results.v1.pl $seg > ${seg}.log

cat ${seg}.log |\
    grep "YYY" | awk '{print $2 " " $3 " " $4}' \
    > $dir_work/${bn}.train

echo -e "${mfcc} $seg_orig" \
	> $dir_work/train.spks.all.script
file_list=$dir_work/train.spks.all.script

num_comp=8
dir_models=$dir_work/models_round6
mkdir -p $dir_models
rm -f $dir_models/*.gmm

# Training one global UBM
sgminit --verbose=1 --quantize \
	--mahalanobis --num-comp=$num_comp \
	--file-list=$file_list $dir_models/ubm_init.gmm

sgmestim --verbose=1 \
	 --file-list=$file_list \
	 --output=${dir_models}/ubm.gmm $dir_models/ubm_init.gmm

echo "Info: training speaker GMMs"
echo -e "${mfcc} $dir_work/${bn}.train" \
  > $dir_work/train.spks.select.script
file_list=$dir_work/train.spks.select.script

num_comp=8
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

dir_labs=$dir_models/labs
mkdir -p $dir_labs

for lab in `cat $dir_work/${bn}.train | awk '{print $1}' | sort -u`
do
  # Make a backup of the model
  mv $dir_models/$lab.gmm $dir_models/$lab.gmm.bak

  # Find and split data into 10 folds
  perl $dir_script/split_segment_into_folds.pl $seg $lab $dir_labs

  for fn in `ls $dir_labs | grep -P "$lab\..*.seg"`
  do
    i=`echo "$fn" | awk -F '/' '{print $NF}' | sed "s/C_\d\+//g" | sed "s/\.seg//g"`

    ls $dir_labs | grep -P "$lab\..*.seg" | sed "/$fn/d" |\
       xargs -I {} cat $dir_labs/{} > $dir_labs/$lab.trn
    echo $fn | xargs -I {} cat $dir_labs/{} > $dir_labs/$lab.tst
    wc -l $dir_labs/$lab.trn $dir_labs/$lab.tst

    echo -e "${mfcc} $dir_labs/$lab.trn" \
      > $dir_work/train.${lab}.script
    file_list=$dir_work/train.${lab}.script
    echo "$file_list"

    # For each fold, estimate on a model and score the held-out segment
    sgmestim --verbose=1 --label=$lab \
	  --file-list=$file_list \
	  --output=${dir_models}/${lab}.gmm $dir_models/ubm_init.gmm \
	  2> $dir_work/${lab}.log
    if [ `cat $dir_work/${lab}.log |\
	   grep "$num_comp defunct component after iteration" |\
	   wc -l` -ge 1 ]; then
      echo "Error! $lab has $num_comp defunct mixtures"
      rm ${dir_models}/${lab}.gmm
    else
      echo -e "${mfcc} $dir_labs/$lab.tst" \
              > $dir_work/test.${lab}.script
      file_list=$dir_work/test.${lab}.script
      sgmlike --list=$dir_work/models.lst \
	--file-list=$file_list \
	-s -n > $dir_labs/score.${lab}.${i}.log
      wc $dir_labs/score.${lab}.${i}.log
    fi
  done
done

find $dir_labs -iname "score.C*.log" |\
     xargs -I {} cat {} > $dir_work/score.cv.log

perl $dir_script/cluster.pl $dir_work/models.lst \
	                    $dir_work/score.cv.log \
			    > $dir_work/cluster.cv.log
cat $dir_work/cluster.cv.log |\
    grep "XXX" | awk '{print $2 " " $3 " " $4}' > $dir_work/${bn}.cv.seg
cp -v $dir_work/${bn}.cv.seg $dir_out/
wc $dir_out/${bn}.cv.seg

echo "DONE CV"
exit 0
