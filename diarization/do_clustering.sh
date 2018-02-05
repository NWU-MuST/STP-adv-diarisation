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

if [ $# -ne "5" ]; then
  echo "Usage: $0 <in:fn-wav> <in:fn-seg> <par:BIC> <out:dir-out> <nj>"
  echo "  fn-wav    - audio file to be segmented into speech/silence"
  echo "  fn-seg    - segmentation file defining segments to be clustered"
  echo "  BIC       - 0 (wasn't used) or 1 (was used)"
  echo "  dir-out   - directory within which all output created"
  echo "  nj        - number of processors available for parallelization"
  echo "e.g.: $0 abc.wav abc.seg /tmp 4"
  exit 1;
fi
echo "XXX"
# -----------------------------------------------------------------------------

dir_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

wav=$1
seg=$2
bic=$3
dir_out=$4
nj=$5

dir_work=$dir_out/clustering
safe_remove_dir $dir_work 0
mkdir -p $dir_work

# -----------------------------------------------------------------------------

# Check required scripts / software

binaries=( sox soxi sfbcep scluster spfcat perl ) 
scripts=( simple_merge_scluster_output.pl
          interpret_scluster_results.v1.pl )

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

# scluster input segmentation

echo "Info: First iteration of scluster"
time scluster --full -i --log=$dir_work/${bn}.scluster.v1.log \
	      $dir_out/${bn}.mfcc ${seg} \
	      $dir_work/${bn}.scluster.it1.seg

# ------------------------------------------------------

# This part only makes sense if BIC switched on.
if [ $bic -eq 1 ]; then
  # - Merges adjoining segments with the same label
  # - If two different clusters co-occur more than once within continuous speech 
  #   segments, consider them to be the same
  #   (if two people interrupt each other more than once, this may lead to an
  #    incorrect cluster)
  perl $dir_script/simple_merge_scluster_output.pl \
	  $dir_work/${bn}.scluster.it1.seg |\
	  grep "XXX" | awk '{print "unk " $3 " " $4}' \
	  > $dir_work/${bn}.scluster.it1.merged.seg

  echo "Info: Second iteration of scluster"
  time scluster --full -i --log=$dir_work/${bn}.scluster.v2.log \
		$dir_out/${bn}.mfcc $dir_work/${bn}.scluster.it1.merged.seg \
		$dir_work/${bn}.scluster.it2.merged.seg

  wc $dir_work/${bn}.scluster.it2.merged.seg
else
  cp -v $dir_work/${bn}.scluster.it1.seg \
        $dir_work/${bn}.scluster.it2.merged.seg
fi
# ------------------------------------------------------

seg_orig=$dir_work/${bn}.scluster.it2.merged.seg
cp $seg_orig $dir_work/${bn}.scluster.it2.merged.seg.tmp
seg=$dir_work/${bn}.scluster.it2.merged.seg.tmp

sed -i "s/\[/_/g" $seg
sed -i "s/\]//g" $seg

# ------------------------------------------------------

  for i in 1.5
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

      if [ $num_c_end -eq 1 ]; then
        num_c_init=1
      fi
      echo "Info: $i COUNTS $num_c_init $num_c_end"
    done
  done
# Select segments for training cluster GMMs
# - go over the file and mark all continuous (may be separated by silence)
#   speech segments from a speaker.
#   If such a 'continuous' segment is > min_duration, add it for training
perl $dir_script/interpret_scluster_results.v1.pl \
	$dir_work/${bn}.scluster.it2.merged.seg.tmp \
	> $dir_work/${bn}.scluster.it2.merged.log

cat $dir_work/${bn}.scluster.it2.merged.log |\
       	grep "XXX" | awk '{print $2 " " $3 " " $4}' \
	> $dir_work/${bn}.scluster.it2b.merged.seg
cat $dir_work/${bn}.scluster.it2.merged.log |\
	grep "YYY" | awk '{print $2 " " $3 " " $4}' \
	> $dir_work/${bn}.scluster.it2.merged.spk-data.lab

# -----------------------------------------------------------------------------
cp $dir_work/${bn}.scluster.it2b.merged.seg $dir_work/${bn}.gmm.boost.merged.seg

cat $dir_work/${bn}.gmm.boost.merged.seg |\
       	awk -v var=${bn} '{print var "_" $2 "-" $3 " " var " " $2 " " $3 " " $1}' \
	> $dir_work/gmm.boost.merged.seg
cp -v $dir_work/gmm.boost.merged.seg $dir_work/final.seg

echo "Info: Done clustering!"
