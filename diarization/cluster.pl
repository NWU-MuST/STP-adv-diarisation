#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 1;
my $tgt   = "SPEECH";

my $add = 2.0;

# Window size = 5s (count the amount of other high conf tags)
# Threshold (or apply to everything?)

sub mean (\@) {
  my $v_p = @_;

  my $cnt = 0;
  my $tot = 0;
  foreach my $v (@{ $v_p }) {
    $tot += $v;
    $cnt += 1;
  }

  return $tot / $cnt;
}

sub std (\@) {
  my $v_p = @_;

  my $cnt = 0;
  my $tot = 0;
  foreach my $v (@{ $v_p }) {
    $tot += $v;
    $cnt += 1;
  }

  my $u = $tot / $cnt;

  $tot = 0;
  foreach my $v (@{ $v_p }) {
    $tot += ($v - $u)*($v - $u);
  }

  return sqrt($tot / ($cnt - 1));
}

if ((@ARGV + 0) != 2) {
  print "perl window_boost_gmm_scores.pl <in:models> <in:ll.log>\n\n";
  exit 1;
}

my $fn_models = $ARGV[0];
my $fn_ll     = $ARGV[1];

my @models;
open MODELS, "$fn_models" or die "Error: Cannot open '$fn_models' for reading!\n";
while(<MODELS>) {
  chomp;
  if (/.*\/(.*).gmm/) {
    push @models, $1;
  }
}
close(MODELS);

# Determine which model is the UBM
my $iubm = 0;
foreach my $i (0..(@models - 1)) { if ($models[$i] =~ /ubm/) { $iubm = $i; } }

my %scores;
my %cluster;
my %values;
open LL, "$fn_ll" or die "Error: Cannot open '$fn_ll' for reading!\n";
while(<LL>) {
  chomp;
  my @parts = split(/\s+/,$_);
  my $bn = shift @parts;
  my $ts = shift @parts;
  my $te = shift @parts;
  my $n_frams = shift @parts;
  my $m_init  = shift @parts;
  my $n_models= shift @parts;

  my $info = sprintf("%s %s %s", $bn, $ts, $te);

  $scores{$ts}{"te"} = $te;

  my $ubm_ll = $parts[$iubm];

  my $highest = -999;
  my $high_i = -1;
  foreach my $i (0..(@parts - 1)) {
    if ($i != $iubm) {
      if ($parts[$i] > $highest) { $highest = $parts[$i]; $high_i = $i;}
    }
  }

  $scores{$ts}{"lab"} = $models[$high_i];

  foreach my $i (0..(@parts - 1)) {
    if ($i != $iubm) {
      $scores{$ts}{"models"}{$models[$i]} = $parts[$i] - $highest + $add;
      #$scores{$ts}{"models"}{$models[$i]} = $parts[$i] - $ubm_ll;
      #push @{ $cluster{$high_i} }, $highest - $parts[$i];
      my $m1 = $models[$high_i];
      my $m2 = $models[$i];
      push @{ $values{$m1}{"all"} }, ($highest - $parts[$i]);
      #$cluster{$m1}{$m2}{"tot"} += $highest - $parts[$i];
      $cluster{$m1}{$m2}{"tot"} += ($highest - $parts[$i])*($te - $ts);

      #$cluster{$m1}{$m2}{"tot"} += $ubm_ll - $parts[$i];
      #$cluster{$m1}{$m2}{"cnt"} += 1;
      #$cluster{$m1}{$m2}{"tot"} += ($ubm_ll - $parts[$i])*($te - $ts);
      $cluster{$m1}{$m2}{"cnt"} += ($te - $ts);
    }
  }
      
  $scores{$ts}{"info"} = $info;

  if ($debug == 1) {
    printf "L: %.2f %.2f",$ts, $te;
    foreach my $m (sort keys %{ $scores{$ts}{"models"} }) {
      printf " %8s", $m;
    }
    print "\n";
    printf "O: %.2f %.2f",$ts, $te;
    foreach my $m (sort keys %{ $scores{$ts}{"models"} }) {
      printf " %8.2f", $scores{$ts}{"models"}{$m};
    }
    print "\n";
  }
}
close(LL);

foreach my $i (sort keys %cluster) {
  foreach my $j (sort keys %{ $cluster{$i} }) {
      my $s1 = $cluster{$i}{$j}{"tot"};
      my $c1 = $cluster{$i}{$j}{"cnt"};

      my $s2 = 0;
      my $c2 = 0;

      if (exists($cluster{$j}{$i}{"tot"})) {
        $s2 = $cluster{$j}{$i}{"tot"};
	$c2 = $cluster{$j}{$i}{"cnt"}
      }

      $cluster{$i}{$j}{"scr"} = ($s1 / $c1)*($c1 / ($c1 + $c2)) + ($s2 / $c2)*($c2 / ($c1 + $c2) );
      $cluster{$j}{$i}{"scr"} = ($s1 / $c1)*($c1 / ($c1 + $c2)) + ($s2 / $c2)*($c2 / ($c1 + $c2) );
  }
}

foreach my $i (sort keys %cluster) {
  print "$i";
  #my $std = sqrt(@{ $values{$i}{"all"} });
  foreach my $j (sort { $cluster{$i}{$a}{"scr"} <=> $cluster{$i}{$b}{"scr"} } keys %{ $cluster{$i} }) {
    printf " $j:%.2f", $cluster{$i}{$j}{"scr"};
	  #printf " $j:%.2f", $cluster{$i}{$j}{"scr"}/$std;
  }
  print "\n";
}

# Assume anything under 1.0 is similar, and merge
my %assigned;
my %part_of_a_cluster;
my %cluster_by_id;
foreach my $i (sort keys %cluster) {
  foreach my $j (sort { $cluster{$i}{$a}{"scr"} <=> $cluster{$i}{$b}{"scr"} } keys %{ $cluster{$i} }) {
    if ($i ne $j and $cluster{$i}{$j}{"scr"} < 1.0) {
      print "Info: Merging $i + $j\n";
      # Three options:
      # (1) Neither belongs to a cluster      (form a new cluster)
      # (2) One belongs to a cluster          (join both to the one cluster)
      # (3) Both belong to different clusters (join the two clusters)
      # TODO: Could build a safeguard here (if belonging to different clusters, check their scores)
      if (exists($part_of_a_cluster{$i}) and 
	  exists($part_of_a_cluster{$j})) {
        if ($part_of_a_cluster{$i} != $part_of_a_cluster{$j}) {
	  # (3)
	  my $i_id = $part_of_a_cluster{$i};
	  my $j_id = $part_of_a_cluster{$j};
	  my $c_i = join " ", (sort keys %{ $cluster_by_id{$i_id} });
	  my $c_j = join " ", (sort keys %{ $cluster_by_id{$j_id} });
	  printf "Info: Merging existing clusters: <$c_i> + <$c_j>\n";
	  foreach my $c (keys %{ $cluster_by_id{$j_id} }) {
	    $part_of_a_cluster{$c} = $i_id;
	    $cluster_by_id{$i_id}{$c} = 1;
	    delete $cluster_by_id{$j_id}{$c};
	  }
	  delete $cluster_by_id{$j_id};
	} else {
          printf "Info: $i & $j already merged!\n";
	}
      } elsif (exists($part_of_a_cluster{$i}) and !exists($part_of_a_cluster{$j}) or
	       exists($part_of_a_cluster{$j}) and !exists($part_of_a_cluster{$i})) {
        if (exists($part_of_a_cluster{$i})) {
          my $id = $part_of_a_cluster{$i};
	  my $c_i = join " ", (sort keys %{ $cluster_by_id{$id} });
	  printf "Info: Merging $j into existing cluster: <$c_i> + [$j]\n";

	  $part_of_a_cluster{$j} = $id;
	  $cluster_by_id{$id}{$j} = 1;
	} else {
          my $id = $part_of_a_cluster{$j};
	  my $c_j = join " ", (sort keys %{ $cluster_by_id{$id} });
	  printf "Info: Merging $j into existing cluster: <$c_j> + [$i]\n";

	  $part_of_a_cluster{$i} = $id;
	  $cluster_by_id{$id}{$i} = 1;
	}
      } else {
        my @sorted = sort { $b <=> $a } keys %cluster_by_id;
	my $id = 0;
	if (scalar(@sorted) > 0) {
	  $id = $sorted[0] + 1;
        }
	$part_of_a_cluster{$i} = $id;
	$part_of_a_cluster{$j} = $id;
	$cluster_by_id{$id}{$i} = 1;
	$cluster_by_id{$id}{$j} = 1;
        print "Info: Forming new cluster: $i + $j\n";
      }
    }
  }
}

# Create a map
my %map;
foreach my $id (sort keys %cluster_by_id) {
  my @sorted = sort { $a cmp $b } keys %{ $cluster_by_id{$id} };
  my $new_id = $sorted[0];
  foreach my $i (1..(@sorted - 1)) {
    $map{$sorted[$i]} = $new_id;
  }
}

foreach my $ts (sort { $a <=> $b } keys %scores) {
  my $te = $scores{$ts}{"te"};
  my $lab= $scores{$ts}{"lab"};
  if (exists($map{$lab})) { $lab = $map{$lab}; }
  printf "XXX: %s %.2f %.2f\n", $lab, $ts, $te;
}

# TODO: Find sections which made it to the final clusters and use that for training
#       Reclassify the rest.
