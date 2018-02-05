#!/usr/bin/perl
use warnings;
use strict;
use Audio::Wav;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 1;

sub add_silence($\%\%) {
  my ($dur, $speech_p, $silence_p) = @_;
  my @sorted_ts = sort { $a <=> $b } keys %{ $speech_p };

  # Beginning is special
  if ($sorted_ts[0] > 0) {
    $silence_p->{0}{"te"} = $sorted_ts[0];
  }

  # End is special
  my $last_speech_ts = $sorted_ts[@sorted_ts - 1];
  my $last_speech_te = $speech_p->{$last_speech_ts}{"te"};

  printf "Debug: last speech start: %.2f\n", $last_speech_ts if ($debug == 1);
  printf "Debug: last speech end  : %.2f\n", $last_speech_te if ($debug == 1);
  if ($last_speech_te < $dur) {
    $silence_p->{$last_speech_te}{"te"} = $dur;
    printf "Debug: setting last silence: %.2f (%.2f)\n",$last_speech_te,$dur if ($debug == 1);
  }

  # Fill in the blanks
  foreach my $i (1..(@sorted_ts - 1)) {
    my $ts_1 = $sorted_ts[$i - 1];
    my $ts_2 = $sorted_ts[$i];
    my $te_1 = $speech_p->{$ts_1}{"te"};

    if ($ts_2 > $te_1) {
      $silence_p->{$te_1}{"te"} = $ts_2;
    }
  }
}

sub read_segment($\%) {
  my ($fn, $segments_p) = @_;

  open FN, "$fn" or die "Error: Cannot open '$fn' for reading!\n";
  while(<FN>) {
    chomp;
    my @parts = split(/\s+/,$_);
    my $lab = $parts[0];
    my $ts  = $parts[1];
    my $te  = $parts[2];
    $segments_p->{$ts}{"te"} = $te;
    $segments_p->{$ts}{"txt"} = $lab;
  }
  close(FN);
}

if ((@ARGV + 0) != 3) {
  print "perl add_silence.pl <in:wav> <in:segment> <out:silence-added>\n\n";
  print "     <wav>       - Wav file for which the textgrid is to be created.\n";
  print "     <segment>   - Audioseg segment file\n";
  print "     <textgrid>  - Audioseg segment file with silence added.\n";
  exit 1;
}

my $fn_wav = $ARGV[0];
my $fn_speech = $ARGV[1];
my $fn_speech_and_sil = $ARGV[2];

# Get the audio file duration
my $wav = new Audio::Wav;
my $read = $wav -> read($fn_wav);
my $audio_seconds = $read -> length_seconds();

printf "Debug: Audio file duration: %.2f\n", $audio_seconds if ($debug == 1);

my %segments;
my %silence;
read_segment($fn_speech, %{ $segments{"speech"} });
add_silence($audio_seconds, %{ $segments{"speech"} }, %{ $segments{"sil"} });

my @speech_ts = keys %{ $segments{"speech"} };
my @silence_ts = keys %{ $segments{"sil"} };

my @sorted_ts = sort { $a <=> $b } (@speech_ts, @silence_ts);

open OUT, ">$fn_speech_and_sil" or die "Error: Cannot open '$fn_speech_and_sil' for reading!\n";
foreach my $ts (@sorted_ts) {
  my $lab = "speech";
  if (exists($segments{"sil"}{$ts})) { $lab = "sil"; }
  my $te = $segments{$lab}{$ts}{"te"};
  printf OUT "%s %.2f %.2f\n", $lab, $ts, $te;
}
close(OUT);
