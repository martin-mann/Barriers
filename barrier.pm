# -*-Perl-*-
# Last changed Time-stamp: <2003-08-03 18:43:19 ivo>
# calculate (an upper limit) to the energy barrier separating
# two secondary structures. Call as
#
# find_saddle($sequence, $structure1, $structure2, $search_depth);
# or
# find_saddle($sequence, $structure1, $structure2, $search_depth, $energy);
#
# where $energy is a previously known upper limit.
# returns energy and structure of best saddle point found.
# saddle point structure will be undef if no path below $energy could be found
#
# performance could be improved by C implementation, 
# RNA::energy_of_struct is not the bottleneck
# performance 58% in try_moves, 26% in sort, 16% rest

package RNA::barrier;
use strict;
use RNA;
use Benchmark;

use vars '@path';
my ($string, %shash, %sshash, $max_keep, $opt_v);
my %pair = ('AU', 5, 'GC', 1, 'CG', 2, 'GU', 3, 'UG', 4, 'UA', 6);

#$opt_v = 1;
BEGIN {
 RNA::update_fold_params();
}
my $cache=0;
my $mm = 0;
sub try_moves {
   use integer;
   # try all moves in list, store best results in %shash
   my ($maxE, $struc, $ocost, $listp) = @_;
   my @list = @{$listp};
#  using RNA::make_loop_index() is only 15% faster
   my @loop = loop_index($struc);
#  my tmp = RNA::cdata(RNA::make_loop_index($struc),length($struc)*4);
#  my @loop = unpack("i*", tmp);
   my $moves=0;
   my $index=-1;
   foreach (@list) {
      $index++;
      my ($i, $j) = @{$_};
      my $test = $struc;
      if ($j<0) { # it's a delete move
	 substr($test, -$i, 1) = '.';
	 substr($test, -$j, 1) = '.';
      } elsif ( # add a base pair
		($loop[$i] == $loop[$j])      && # i and j belong to same loop
		(substr($test, $i, 1) eq '.') &&
		(substr($test, $j, 1) eq '.')    # ... and are unpaired
		) {
	 substr($test, $i, 1) = '(';
	 substr($test, $j, 1) = ')';
      } else {
	 next; #illegal move, try next;
      }
      $moves++;	
      no integer;
      my $test_en;
      if (exists $shash{$test}) {
	 $test_en = $shash{$test}->[1];
	 $cache++;
      } else {
	 $test_en = RNA::energy_of_struct($string, $test);
	 next if $test_en >= $maxE;
      }
#     my $test_en = RNA::energy_of_move($string, $test, $i, $j);
      my $cost = ($test_en>$ocost) ? $test_en : $ocost;
      if ((!exists $shash{$test}) || ($shash{$test}->[0] >$cost)) {
	 my @llist = @list;
	 splice(@llist, $index, 1);
	 $shash{$test} = [$cost, $test_en, $i, $j, \@llist];
      }
   }
   warn "no possible moves $struc @list" if ($moves==0);
   $mm += $moves;
}

sub loop_index {
   use integer;
   # number loops and assign each position its loop-number
   # handy for checking which pairs can be added
   my $struc = shift;
   my($c, $j, @olist, @loop);
   my ($hx,$i,$l, $nl)=(0,0,0,0);
   foreach $c (split(//,$struc)) {
      if ($c eq '(') {
	 $nl++; $l=$nl;       # start a new loop
	 $olist[$hx++]=$i;
      }
      $loop[$i]=$l;
      if ($c eq ')') {
	 --$hx;                         # i pairs with olist[--hx]
	 if ($hx>0) {                   # we're still in a loop
	    my $jj = $olist[$hx-1];    # jj started the previous loop 
	    $l = $loop[$jj] if (defined($jj)); # previous loop index
	 } else {
	    $l = 0;                    # external loop has index 0
	 }
      }
      $i++;
   }
   push @loop, $nl;
   return @loop;
}

sub make_pair_table {
   use integer;
   # let table[i]=j if (i,j) is pair, -1 if i unpaired
   # indices start at 0 in this version!
   my($i,$j,$hx, @olist);
   my($structure) = pop(@_);

   $hx=$i=0;
   my ($c,@table);
   foreach $c (split(//,$structure)) {
      if ($c eq '.') {
	 $table[$i]= -1;
      } elsif ($c eq '(') {
	 $olist[$hx++]=$i;
      } elsif ($c eq ')') {
	 $j = $olist[--$hx];
	 die ('unbalanced brackets in make_pair_table') if ($hx<0);
	 $table[$i]=$j;
	 $table[$j]=$i;
      }
      $i++;
   }
   die ('too few closed brackets in make_pair_table') if ($hx!=0);
   return @table;
}

sub check_struct {
   use integer;
   # check if structure is legal, for debugging only
   my($structure) = pop(@_);
   my($i,$j,$hx, @olist);
   
   $hx=$i=0;
   my $c;
   foreach $c (split(//,$structure)) {
      if ($c eq '(') {
	 $olist[$hx++]=$i;
      } elsif ($c eq ')') {
	 $j = $olist[--$hx];
	 return 0 if ($hx<0);
	 return 0 unless
	     ($pair{substr($string,$i,1) . substr($string,$j,1)});
      }
      $i++;
   }
   return 0 if ($hx!=0);
   return 1;
}    

sub find_saddle_once {
   # find best path connecting $struct1 and $struct2 
   my ($struc1, $struc2, $saddleE) = @_;
   
   my $en1 = RNA::energy_of_struct($string, $struc1);
   printf '%s (%5.2f)\n', $struc1, $en1 if ($opt_v);
   my $en2 = RNA::energy_of_struct($string, $struc2);
   printf "%s (%5.2f)\n", $struc2, $en2 if ($opt_v);
   my @p1 = make_pair_table($struc1);
   my @p2 = make_pair_table($struc2);
   
   my @plist = (); # normal moves
   my @slist = (); # shift moves
   my $i;
   for $i (0..$#p1) {
      if ($p1[$i] != $p2[$i]) {
	 push @plist, [-$i, -$p1[$i]] if ($i<$p1[$i]);
	 push @plist, [$i, $p2[$i]] if ($i<$p2[$i]);
	 # if both are paired we have a  shift move
#	   push @slist, [-$p1[$i], $p2[$i]]
#	 if (($p1[$i]>=0)&&($p2[$i]>=0));
      }
   }
   my $llen = $#plist;
   my $struc = $struc1;
   
   # greedy walk from struc1 to struc2
   my @structs;
   my %prev;
   $prev{$struc1} = [$en1, \@plist];
   for my $level (0..$llen) {
      my $en;
      %shash = ();
#      print 'try_moves', times();
      foreach $struc (keys %prev) {
	 try_moves($saddleE, $struc, @{$prev{$struc}});
      }
      %prev = ();
#      print ' sort', times();
      my @keep = sort {$shash{$a}->[0] <=> $shash{$b}->[0]
#			   || $shash{$a}->[1] <=> $shash{$b}->[1]
			} keys %shash;
      my %new;
#      print ' other', times(), "\n";
      print "tested $#keep structures\n" if ($opt_v);
      $#keep=$max_keep if ($#keep>$max_keep);
      my $ll=0;
      for (@keep) {
	 my @l = @{$shash{$_}};
	 last if ($l[0]>=$saddleE);  
	 $new{$_} = [@l[0,2,3]];
	 splice(@l,1,3);
	 $prev{$_} = \@l;
	 $ll++;
      }
      last if ($ll==0);
      $structs[$level] = \%new;
   }
   
   return ($saddleE, undef)
       if ($#structs<$llen); # didn't find a better solution
   $struc = $struc2;
   $saddleE = $structs[-1]{$struc}[0];
   my $saddle;
   @path = ();
   foreach (reverse @structs) {
      my %last = %{$_};
      my ($en, $i, $j) = @{$last{$struc}};
      if ($j<0) {
	 substr($struc, -$i, 1) = '(';
	 substr($struc, -$j, 1) = ')';
      } else {
	 substr($struc, $i, 1) = '.';
	 substr($struc, $j, 1) = '.';
      }
      no integer;
      my $ee = RNA::energy_of_struct($string, $struc);
      $saddle = $struc if ($ee==$saddleE);
      printf "$struc (%6.2f) (%6.2f) $i $j\n", $ee, $en if ($opt_v);
      push @path, $struc;
   }
   return ($saddleE, $saddle);
}

sub find_saddle {
   no integer;
   my ($struc1, $struc2, $saddleE, $max);
   ($string, $struc1, $struc2, $max, $saddleE) = @_;
   $saddleE = 9999. if (!defined($saddleE));
   
   die ("unequal length $string, $struc1, $struc2")
       unless ((length ($string)==length($struc1))
	       && (length ($string)==length($struc2)));
   
   $max_keep=1/2;
   my $saddle;
   while ($max_keep<$max) {
      $max_keep *= 2; 
      $max_keep = $max if ($max<$max_keep);
      my @new = find_saddle_once($struc2, $struc1, $saddleE);
      ($saddleE, $saddle) = @new if ($new[0]<$saddleE);
      ($struc2, $struc1) = ($struc1, $struc2);
   }
   print "cache hits: $cache of $mm\n" if $opt_v;
   return ($saddleE, $saddle);
}

sub get_neighbors {
   use integer;
   my ($seq, $struc) = @_;
#  using RNA::make_loop_index() is only 15% faster
   my @loop = loop_index($struc);
   my @ptable = make_pair_table($struc);
#  my tmp = RNA::cdata(RNA::make_loop_index($struc),length($struc)*4);
#  my @loop = unpack("i*", tmp);
   my @moves;
   # invert loop_index
   my @posl;
   for my $p (0..length($struc)-1) {
     next unless substr($struc, $p, 1) eq '.';
     my $l = $loop[$p];
     if (!defined($posl[$l])) {
       $posl[$l] = [$p];
     } else {
       push @{$posl[$l]}, $p;
     }
   }
   # find insert moves
   foreach my $pl (@posl) {
     foreach my $i (@{$pl}) {
       foreach my $j (@{$pl}) {
	 next unless $j>$i+3;
	 next unless $pair{substr($seq,$i,1) . substr($seq,$j,1)};
	 my $new = $struc;
	 substr($new, $i, 1) = '(';
	 substr($new, $j, 1) = ')';
	 push @moves, $new;
       }
     }
   }
   for my $p (0..length($struc)-1) {
     next unless substr($struc,$p,1) eq '(';
     my $new = $struc;
     substr($new, $p, 1) = '.';
     substr($new, $ptable[$p], 1) = '.';
     push @moves, $new;
   }
   return @moves;
}

1;
