package Catmandu::Importer::getXML;
#ABSTRACT: import XML via HTTP GET request
#VERSION

use Moo;
use XML::Struct::Reader;
#use Catmandu::Importer::XML;
#TODO: Catmandu::Importer::Foo->new(%args, file => \$content)->to_array;
# getCSV, getXLS...

extends 'Catmandu::Importer::HTTP';

has '+headers' => (
    is => 'ro',
    default => sub { [ 'Accept' => 'application/xml' ] }
);

has simple => (is => 'ro', default => sub { 1 });

sub response_hook {
    my ($self, $response) = @_;

    my $reader = XML::Struct::Reader->new(
        simple => $self->simple,
        from => \$response->{content},
    );

    $reader->read;
}

1;

=head1 SYNOPSIS

    echo http://example.org/data.xml | catmandu convert getXML to YAML
    catmandu convert getXML --from http://example.org/data.xml to YAML

=head1 DESCRIPTION

This L<Catmandu::Importer> is a L<Catmandu::Importer::HTTP> that reads XML
data with L<XML::Struct>.

=head1 CONFIGURATION

=over

=item simple

Parse XML into simple format, not preserving element order (default).

=back

=head1 SEE ALSO

L<Catmandu::XML>

=encoding utf8
