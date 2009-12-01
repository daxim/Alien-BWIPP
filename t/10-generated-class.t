#!perl -T
use strict;
use warnings FATAL   => 'all';
use Test::More tests => 7;

use Alien::BWIPP;
my $instance = Alien::BWIPP::qrcode->new;
can_ok($instance, qw(DESC EXAM EXOP RNDR smallest_symbol_version metrics));
is($instance->DESC, 'QR Code');
is($instance->EXAM, 'http://www.terryburton.co.uk/barcodewriter/');
is($instance->EXOP, 'eclevel=M');
is($instance->RNDR, 'renmatrix');
is($instance->smallest_symbol_version->{L}[9], 271, 'eclevel=L version=9 can encode 271 bytes at most');
is($instance->metrics->{12}{size}, 65, 'a version=12 barcode is 65 units long and wide');
