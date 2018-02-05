#!/usr/bin/perl
use warnings;
use strict;
use Audio::Wav;
use open IO => ':encoding(utf8)';

use utf8;

sub read_segment($$\%) {
  my ($fn, $ts, $seg_p) = @_;

  my @parts = split(/\//,$fn);
  my $bn = $parts[@parts - 1];
  $bn =~ s/\.[^\.]+$//g;
  my $tgt_bn = $bn;
  $tgt_bn =~ s/-\d+$//;

  open FN, "$fn" or die "Error: Cannot open '$fn' for reading!\n";
  while(<FN>) {
    chomp;
    my $line = $_;
    $line =~ s/$bn/$tgt_bn/g;
    @parts = split(/\s+/,$line);
    @parts[@parts - 2] += $ts;
    @parts[@parts - 1] += $ts;
    $line = join " ", @parts;
    if (exists($seg_p->{$parts[@parts - 2]})) {
      die "Error: '$parts[@parts - 2]' should not exist.\n";
    }
    $seg_p->{$parts[@parts - 2]} = $line;
  }
  close(FN);
}

if ((@ARGV + 0) < 3) {
  print "perl split_wav.pl <in:wav> <par:num-wavs> <in:segments>\n\n";
  print "     <wav>       - Wav file for which the textgrid is to be created.\n";
  print "     <num-wavs>  - Number of approximately equal in duration wavs created\n";
  print "     <dir-wavs>  - Segments to combine.\n";
  exit 1;
}

my $fn_wav   = $ARGV[0];
my $num_wavs = $ARGV[1];

my @segments;

foreach my $i (2..(@ARGV - 1)) {
  push @segments, $ARGV[$i];
}

if (scalar(@segments) != $num_wavs) {
  die "Error: Number of segments files does not equal number of wavs!\n";
}

# Get the audio file duration
my $wav = new Audio::Wav;
my $read = $wav -> read($fn_wav);
my $audio_seconds = $read -> length_seconds();

my @parts = split(/\//,$fn_wav);
my $bn = $parts[@parts - 1];
$bn =~ s/\.[^\.]+$//g;

my $split_dur = int($audio_seconds / $num_wavs);

my $ts = 0;
my $te = $split_dur;

my %seg;

foreach my $i (1..$num_wavs) {
  my $dur = $te - $ts;
  if ($i == $num_wavs) {
    $dur = $audio_seconds - $ts;
  }

  read_segment($segments[$i - 1], $ts, %seg);

  $ts = $te;
  $te += $split_dur;
  if ($te > $audio_seconds) { $te = $audio_seconds; }
}

foreach my $ts (sort { $a <=> $b } keys %seg) {
  printf "%s\n", $seg{$ts};
}
