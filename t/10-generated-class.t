#!perl -T
use strict;
use warnings FATAL   => 'all';
use Test::More tests => 5;

use Alien::BWIPP;
my $instance = Alien::BWIPP::qrcode->new;
can_ok($instance, qw(DESC EXAM EXOP RNDR));
is($instance->DESC, 'QR Code');
is($instance->EXAM, 'http://www.terryburton.co.uk/barcodewriter/');
is($instance->EXOP, 'eclevel=M');
is($instance->RNDR, 'renmatrix');
