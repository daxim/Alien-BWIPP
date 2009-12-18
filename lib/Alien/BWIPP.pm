package Alien::BWIPP;
use 5.010;
use utf8;
use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars %LAST_PAREN_MATCH);
use File::ShareDir qw(dist_file);
use IO::File qw();
use Moose::Meta::Class qw();
use Moose qw(has);
use MooseX::ClassAttribute qw(class_has);
use Storable qw(dclone);

our $VERSION = '0.003';

has 'barcode_source_handle' => (
    is      => 'rw',
    isa     => 'IO::File',
    default => sub {
        return IO::File->new(dist_file('Alien-BWIPP', 'barcode.ps'), 'r');
    },
);

has '_chunks' => (is => 'ro', isa => 'HashRef', lazy_build => 1,);

has '_encoders' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy_build => 1,
);

class_has 'encoders_meta_classes' => (is => 'rw', isa => 'ArrayRef[Moose::Meta::Class]',);

sub _build__chunks {
    my ($self) = @_;
    my %chunks;
    {
        while (defined(my $line = $self->barcode_source_handle->getline)) {
            state ($block_type, $block_name, $in_begin);
            $in_begin = $line if $in_begin;
# $in_begin is a work-around because the flip..flop operator does not work
# correctly in given/when under 5.10.0. This has been fixed for 5.10.1.
            given ($line) {
                when (/\A %[ ]--BEGIN[ ](?<type>(?:RENDER|ENCOD)ER)[ ](?<name>\w+)--/msx) {
                    $in_begin = 1;
                    $block_type = $LAST_PAREN_MATCH{type} if $LAST_PAREN_MATCH{type};
                    $block_name = $LAST_PAREN_MATCH{name} if $LAST_PAREN_MATCH{name};
                }
                when (/\A %[ ]--END  [ ]        (?:RENDER|ENCOD)ER/msx) {
                    $in_begin = 0;
                }
                when ($in_begin) {
                    $chunks{$block_type}{$block_name}{post_script_source_code} .= $line;
                    continue;
                }
                when (/\A % [ ] --
                    (?<feature_name>\w+) :? [ ]
                    (?<feature_value>.*?)
                    (?:--)? \n \z/msx
                ) {
                    next if $LAST_PAREN_MATCH{feature_name} ~~ [qw(BEGIN END)];
                    $chunks{ENCODER}{$block_name}{$LAST_PAREN_MATCH{feature_name}}
                      = $LAST_PAREN_MATCH{feature_value};
                }
                when (/\A [ ]{20,23}
                    (?<smallest_symbol_version> \d{1,4} (?: [ ]{2,4} \d{2,4} ){9} )
                        [ ]{3} % [ ] [123]? 1-
                    (?<quality> [LMQH] )
                        [ ]{1,2} - [ ] [1234] 0-
                    \g{quality} \n \z/msx
                ) {
                    push @{$chunks{ENCODER}{qrcode}{smallest_symbol_version}{$LAST_PAREN_MATCH{quality}}},
                      split q{ }, $LAST_PAREN_MATCH{smallest_symbol_version};
                }
                when (
                    / \A [ ]{8} [[] [ ] [(]
                    (?<format> (?:micro|full) )
                        [)] [ ]{2,3} [(]
                    (?<vers> (?:[56789]|M[1234]|1\d?|2\d?|3\d?|40?) )
                        [)] [ ]{2,4}
                    (?<size> \d\d\d? )
                        [ ]{2}
                    (?<align> \d\d [ ] \d\d )
                        [ ]{2,5}
                    (?<modules> \d{2,5} )
                        [ ]{2} [[] [ ]{1,3}
                    (?<error_codewords> \d{1,3} [ ]{1,4} \d{1,4} [ ]{1,3} \d{1,4} [ ]{1,3} \d{1,4} )
                        [ ] []] [ ]{2} [[] [ ]{1,2}
                    (?<error_correction_blocks> \d\d? [ ]{1,2} \d\d? (?: [ ]{1,2} (?:-1|\d\d?) ){6} )
                    [ ] []] [ ] []] \n \z/msx
                ) {
                    my %metrics = %LAST_PAREN_MATCH;
                    for my $section (qw(error_codewords error_correction_blocks)) {
                        $metrics{$section} = [split q{ }, $metrics{$section}];
                    }
                    my $version = delete $metrics{vers};
                    $chunks{ENCODER}{qrcode}{metrics}{$version} = \%metrics;
                }
            }
        }
    }
    return \%chunks;
}

sub _build__encoders {
    my ($self) = @_;
    return [keys %{$self->_chunks->{ENCODER}}];
}

sub create_classes {
    my ($self) = @_;
    my @meta_classes;
    my %chunks = %{$self->_chunks};
    for my $encoder (@{$self->_encoders}) {
        my $prepended;
        for my $renderer (split q{ }, $chunks{ENCODER}{$encoder}{RNDR}) {
            $prepended .= $chunks{RENDERER}{$renderer}{post_script_source_code};
        }
        $chunks{ENCODER}{$encoder}{post_script_source_code}
          = $prepended . $chunks{ENCODER}{$encoder}{post_script_source_code};

        my $class_name = $self->meta->name . q{::} . $encoder;
        my $meta_class = Moose::Meta::Class->create($class_name,
            superclasses => ['Moose::Object'],);
        for my $attribute_name (keys %{$chunks{ENCODER}{$encoder}}) {
            my $attribute_value = $chunks{ENCODER}{$encoder}{$attribute_name};
            $attribute_value = dclone($attribute_value) if ref $attribute_value;
            $meta_class->add_attribute($attribute_name =>
                  (is => 'ro', default => sub {return $attribute_value;},));
        }
        push @meta_classes, $meta_class;
    }
    $self->encoders_meta_classes([@meta_classes]);
    return;
}

sub import {
    my ($class) = @_;
    $class->new->create_classes;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Alien::BWIPP - Barcode Writer in Pure PostScript


=head1 VERSION

This document describes C<Alien::BWIPP> version C<0.003>. It is based on
I<Barcode Writer in Pure PostScript> version C<2009-11-15>.


=head1 SYNOPSIS

    use Alien::BWIPP;
    say $_->name for @{Alien::BWIPP->encoders_meta_classes};

=head1 DESCRIPTION

This modules builds encoder classes from PostScript source.


=head1 INTERFACE

=head2 C<import>

Class method, automatically called by L<use>. Creates an instance and calls
L</create_classes>.

=head2 C<create_classes>

Method, builds encoder classes. The generated classes may have the following
attributes:

=over

=item C<post_script_source_code>

Ready to use PostScript source code, concatenated from the encoder source
code and the renderer needed by it.

=item DESC

Human readable description of this encoder. Example:

    AusPost 4 State Customer Code

=item EXAM

Example string for this encoder. Example:

    0123456789

=item EXOP

Stringified list of example options for this encoder. Example:

    includetext includecheck includecheckintext

=item RNDR

Stringified list of renderers needed for this encoder. Example:

    renlinear renmatrix

=item REQUIRES

=item SUGGESTS

=back

=head2 C<encoders_meta_classes>

Class Attribute, returns the generated meta classes as
ArrayRef[L<Moose::Meta::Class>].


=head1 EXPORTS

Nothing.


=head1 DIAGNOSTICS

None.


=head1 CONFIGURATION AND ENVIRONMENT

C<Alien::BWIPP> requires no configuration files or environment variables.


=head1 DEPENDENCIES

=head2 Configure time

Perl 5.10, L<Module::Build> >= 0.35_14

=head2 Run time

=head3 core modules

Perl 5.10, L<English>, L<IO::File>, L<Storable>

=head3 CPAN modules

L<File::ShareDir>, L<Moose>, L<Moose::Meta::Class>, L<MooseX::ClassAttribute>


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
L<http://github.com/daxim/Alien-BWIPP/issues>,
or send an email to the maintainer.


=head1 TO DO

No future plans yet.

Suggest more future plans by L<filing a bug|/"BUGS AND LIMITATIONS">.


=head1 AUTHOR

=head2 Distribution maintainer

Lars Dɪᴇᴄᴋᴏᴡ C<< <daxim@cpan.org> >>


=head2 Contributors

See file F<AUTHORS>.


=head1 LICENCE AND COPYRIGHT

=head2 F<barcode.ps>

Barcode Writer in Pure PostScript - Version 2009-11-15

Copyright © 2004-2009 Terry Burton C<< <tez@terryburton.co.uk> >>

Permission is hereby granted, free of charge, to any
person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the
Software without restriction, including without
limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice
shall be included in all copies or substantial portions
of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.


=head2 All other files

Copyright © 2004-2009 Lars Dɪᴇᴄᴋᴏᴡ C<< <daxim@cpan.org> >>

Distributable under the same licence.


=head1 SEE ALSO

homepage L<http://www.terryburton.co.uk/barcodewriter/>,
manual L<http://groups.google.com/group/postscriptbarcode/web>
