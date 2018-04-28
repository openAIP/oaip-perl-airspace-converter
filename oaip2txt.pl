#!/usr/bin/perl
#
# converts OpenAIP XML Airspace descriptions to OpenAir TXT format.
# The output is intended for pilots using XCSoar
#
# Author: Ronald Niederhagen
# Initial version as of April 20, 2017
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.


use strict;
use warnings;
use Switch;
use POSIX;
use XML::LibXML;

main();

sub trim {
  $_[0] =~ s/^\s*//g;
  $_[0] =~ s/\s*$//g;
  return $_[0] ;
}

sub rectify_category {
  switch ($_[0]) {
    case 'GLIDING' { return 'W'; }
    case 'RESTRICTED' { return 'R'; }
    case 'DANGER' { return 'Q'; }
  }
  return $_[0];
}

sub altitude_format {
  my $num = $_[0];
  my $unit = $_[1];
  my $ref = $_[2];

  if (($num == 0) && ($ref eq 'GND'))
    { return 'GND'; }

  my $rv;
  switch ($unit) {
    case 'FL' { $rv = 'FL'.$num; }
    case 'F' { $rv = $num . 'ft '. $ref; }
    case 'M' { $rv = $num . 'm '. $ref; }
  }

  return $rv;
}

sub frac2gms {
  my $hem;

  if ($_[0] < 0) {
    $_[0] = $_[0] * -1.0;
    $hem = $_[2];
    } else { $hem = $_[1]; }

  $_[0] += 5.0/36000.0; # to achieve rounding to the nearest second
  my $g = int $_[0];
  my $f = 60 * ($_[0] - $g);
  my $m = int $f;
  $f = 60 * ($f - $m);
  my $s = int $f;

  return (sprintf("%02d:%02d:%02d $hem",$g,$m,$s));
}

sub dump_polygon {
  my @cs;
  my ($x,$y);
  my $xs;
  my $ys;
  my $of = $_[0];
  @cs = split(/,/,$_[1]);

  foreach my $coord (@cs)
    {
    # print $coord, "\n";
    ($x,$y) = split(/ /,trim($coord));
    $xs = frac2gms($x,'E','W');
    $ys = frac2gms($y,'N','S');
    print $of "DP $ys $xs\n";
    }
}

sub main {
  my $argc = @ARGV;
  if ($argc != 2) { perror "Usage: $0 input_file output_file\n"; exit(); }
  my $filename = shift @ARGV;
  my $result = shift @ARGV;

  open(my $of, '>', $result) or die "Could not open file '$filename' for write $!";

  my $parser = XML::LibXML->new();
  my $xmldoc = $parser->parse_file($filename);

  if($@) {
      # Log failure and exit
      print "Error parsing '$filename':\n$@";
      exit 0;
  }

  my ($nm);
  my @attrs;
  my $category;
  my ($num,$unit,$ref);
  my $nspace=0;

  for my $sample ( $xmldoc->findnodes('/OPENAIP/AIRSPACES/ASP') ) {
    $nm = $sample->getChildrenByTagName('CATEGORY');
    $category = rectify_category($sample->getAttribute('CATEGORY'));
    print $of 'AC ', $category, "\n";

    $nm = $sample->getChildrenByTagName('NAME');
    print $of 'AN ', trim($nm->to_literal), "\n";

    $nm = $sample->getChildrenByTagName('ALTLIMIT_TOP');
    $num = int(trim($nm->to_literal));

    @attrs= $sample->findnodes("./ALTLIMIT_TOP/ALT/@*");
    foreach my $attr (@attrs)
      { if ($attr->nodeName eq 'UNIT')
	{$unit = $attr->value;
	}}

    @attrs= $sample->findnodes("./ALTLIMIT_TOP/@*");
    foreach my $attr (@attrs)
      { if ($attr->nodeName eq 'REFERENCE')
	{$ref = $attr->value;
	# print ' ', $ref, "\n";
	}}

    print $of 'AH '. altitude_format ($num,$unit,$ref) ."\n";

    $nm = $sample->getChildrenByTagName('ALTLIMIT_BOTTOM');
    $num = int(trim($nm->to_literal));

    @attrs= $sample->findnodes("./ALTLIMIT_BOTTOM/ALT/@*");
    foreach my $attr (@attrs)
      { if ($attr->nodeName eq 'UNIT')
	{$unit = $attr->value;
	# print ' ', $unit;
	}}

    @attrs= $sample->findnodes("./ALTLIMIT_BOTTOM/@*");
    foreach my $attr (@attrs)
      { if ($attr->nodeName eq 'REFERENCE')
	{$ref = $attr->value;
	# print ' ', $ref, "\n";
	}}

    print $of 'AL '. altitude_format ($num,$unit,$ref) ."\n";

    $nm = $sample->findnodes('./GEOMETRY/POLYGON');
    dump_polygon($of,trim($nm->to_literal));

    print $of "\n";
    $nspace += 1;
  }

  close $of;
  print "done: $nspace airspaces\n";
  exit 0;
}
