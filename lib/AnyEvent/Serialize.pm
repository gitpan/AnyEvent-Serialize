package AnyEvent::Serialize;

use 5.010001;
use strict;
use warnings;
use Carp;

require Exporter;

use AnyEvent;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration       use AnyEvent::Serialize ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(serialize deserialize) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw();

our $VERSION = '0.02';


our $block_size = 1024;

sub import
{
    my ($class, @arg) = @_;


    for (reverse 0 .. $#arg - 1) {
        next unless $arg[$_] eq 'block_size';
        my $bs = $arg[$_ + 1];
        croak "Usage: use AnyEvent::Serialize block_size => 512 ..."
            unless $bs > 0;
        $block_size = $bs;
        splice @arg, $_, 2;
        last;
    }

    return $class->export_to_level(1, $class,  @arg);
}


sub serialize($&) {
    require Data::StreamSerializer;
    no warnings 'redefine';
    no strict 'refs';

    *{ __PACKAGE__ . '::serialize' } = sub ($&) {
        my ($obj, $cb) = @_;
        my $sr = new Data::StreamSerializer $obj;
        $sr->block_size($block_size);

        my $str = $sr->next;

        if ($sr->is_eof()) {
            $cb->($str, $sr->recursion_detected);
            return;
        }

        my $idle;
        $idle = AE::idle sub {
            my $part = $sr->next;
            $str .= $part if defined $part;
            if ($sr->is_eof) {
                undef $idle;
                $cb->($str, $sr->recursion_detected);
                return;
            }
        };
    };

    goto &serialize;
}

sub deserialize($&) {
    require Data::StreamDeserializer;
    no warnings 'redefine';
    no strict 'refs';

    *{ __PACKAGE__ . '::deserialize' } = sub ($&) {
        my ($data, $cb) = @_;
        my $dsr = new Data::StreamDeserializer
            data => $data, block_size => $block_size;

        if ($dsr->next_object) {
            $cb->($dsr->result, $dsr->error, $dsr->tail);
            return;
        }

        my $idle;
        $idle = AE::idle sub {
            return unless $dsr->next;
            undef $idle;
            $cb->($dsr->result('first'), $dsr->error, $dsr->tail);
        };
    };

    goto &deserialize;
}

1;

__END__

=head1 NAME

AnyEvent::Serialize - async serialize/deserialize function

=head1 SYNOPSIS

  use AnyEvent::Serialize ':all';
  use AnyEvent::Serialize 'serialize';
  use AnyEvent::Serialize 'deserialize';
  use AnyEvent::Serialize ... block_size => 666;

  serialize $object, sub { ($str, $recursion_detected) = @_ };
  deserialize $string, sub { my ($object, $error, $tail) = @_ }

=head1 DESCRIPTION

Sometimes You need to serialize/deserialize a lot of data. If You
do it using L<Data::Dumper> or B<eval> it can take You too much time.
This module splits (de)serialization process into fixed-size parts
and does this work in non-blocking mode.

This module uses L<Data::StreamSerializer> and L<Data::StreamDeserializer>
to serialize or deserialize Your data.

=head1 EXPORT

=head2 serialize($object, $result_callback)

Serializes Your object. When serialization is done it will call
B<$result_callback>. This callback receives two arguments:

=over

=item result string

=item flag if recursion is detected

=back


=head2 deserialize($str, $result_callback)

Deserializes Your string. When deserialization is done or an error is
detected it will call B<$result_callback>. This callback receives three
arguments:

=over

=item deserialized object

=item error string (if an error was occured)

=item undeserialized string tail

=back

=head1 SEE ALSO

L<Data::StreamSerializer>, L<Data::StreamDeserializer>.

=head1 AUTHOR

Dmitry E. Oboukhov, E<lt>unera@debian.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Dmitry E. Oboukhov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
