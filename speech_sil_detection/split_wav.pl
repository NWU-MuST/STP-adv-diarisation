#!/usr/bin/perl
use warnings;
use strict;
use Audio::Wav;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 1;

if ((@ARGV + 0) != 3) {
  print "perl split_wav.pl <in:wav> <par:num-wavs> <out:dir-wavs>\n\n";
  print "     <wav>       - Wav file for which the textgrid is to be created.\n";
  print "     <num-wavs>  - Number of approximately equal in duration wavs to create\n";
  print "     <dir-wavs>  - Directory within which to create the wavs.\n";
  exit 1;
}

my $fn_wav   = $ARGV[0];
my $num_wavs = $ARGV[1];
my $dir_wavs = $ARGV[2];

# Get the audio file duration
my $wav = new Audio::Wav;
my $read = $wav -> read($fn_wav);
my $audio_seconds = $read -> length_seconds();

printf "Info: Audio file duration: %.2f\n", $audio_seconds;

my @parts = split(/\//,$fn_wav);
my $bn = $parts[@parts - 1];
$bn =~ s/\.[^\.]+$//g;

my $split_dur = int($audio_seconds / $num_wavs);

my $ts = 0;
my $te = $split_dur;

foreach my $i (1..$num_wavs) {
  my $dur = $te - $ts;
  if ($i == $num_wavs) {
    $dur = $audio_seconds - $ts;
  }
  my $tgt_wav = sprintf("%s/%s-%d.wav", $dir_wavs, $bn, $i);

  system("sox $fn_wav $tgt_wav trim $ts $dur");

  $ts = $te;
  $te += $split_dur;
  if ($te > $audio_seconds) { $te = $audio_seconds; }
}
