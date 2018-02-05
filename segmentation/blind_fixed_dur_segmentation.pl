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
  print "     <seg-dur>   - Preferred segment duration\n";
  print "     <dir-wavs>  - Directory within which to create the wavs.\n";
  exit 1;
}

my $fn_wav   = $ARGV[0];
my $seg_dur  = $ARGV[1];
my $dir_wavs = $ARGV[2];

# Get the audio file duration
my $wav = new Audio::Wav;
my $read = $wav -> read($fn_wav);
my $audio_seconds = $read -> length_seconds();

printf "Info: Audio file duration: %.2f\n", $audio_seconds;

if ($seg_dur > $audio_seconds) {
  print "Warning: preferred segment duration longer than audio file!\n";
  $seg_dur = $audio_seconds;
}

my $d1 = $audio_seconds / $seg_dur;
my $d2 = int($d1 + 0.5);
my $d3 = $seg_dur * $d2;
my $d4 = int(($audio_seconds - $d3)/$d2);
my $d5 = $seg_dur + $d4;

printf "Info: Ammending segment duration from %.2f to %.2f\n", $seg_dur, $d5;

my @parts = split(/\//,$fn_wav);
my $bn = $parts[@parts - 1];
$bn =~ s/\.[^\.]+$//g;

my $split_dur = $d5;

my $ts = 0;
my $te = $split_dur;

foreach my $i (1..$d2) {
  my $dur = $te - $ts;
  if ($i == $d2) {
    $dur = $audio_seconds - $ts;
    $te  = $audio_seconds;
  }
  my $tgt_wav = sprintf("%s/%s_%.2f-%.2f.wav", $dir_wavs, $bn, $ts, $te);

  system("sox $fn_wav $tgt_wav trim $ts $dur");

  $ts = $te;
  $te += $split_dur;
  if ($te > $audio_seconds) { $te = $audio_seconds; }
}
