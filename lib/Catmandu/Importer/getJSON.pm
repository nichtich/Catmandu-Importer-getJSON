package Catmandu::Importer::getJSON;
#ABSTRACT: import JSON via HTTP GET request
#VERSION

use Moo;

extends 'Catmandu::Importer::HTTP';
  
has '+headers' => (
    is => 'ro',
    default => sub { [ 'Accept' => 'application/json' ] }
);

sub response_hook {
    my ($self, $response) = @_;
    $self->json->decode($response->{content});
}

1;

=head1 SYNOPSIS

The following three examples are equivalent:

    Catmandu::Importer::getJSON->new(
        file => \"http://example.org/alice.json\nhttp://example.org/bob.json"
    )->each(sub { my ($record) = @_; ... );

    Catmandu::Importer::getJSON->new(
        url  => "http://example.org",
        file => \"/alice.json\n/bob.json"
    )->each(sub { my ($record) = @_; ... );
    
    Catmandu::Importer::getJSON->new(
        url  => "http://example.org/{name}.json",
        file => \"{\"name\":\"alice\"}\n{\"name\":\"bob\"}"
    )->each(sub { my ($record) = @_; ... );

For more convenience the L<catmandu> command line client can be used:

    echo http://example.org/alice.json | catmandu convert getJSON to YAML
    catmandu convert getJSON --from http://example.org/alice.json to YAML
    catmandu convert getJSON --dry 1 --url http://{domain}/robots.txt < domains

=head1 DESCRIPTION

This L<Catmandu::Importer> is a L<Catmandu::Importer::HTTP> that expects and
returns items serialized in JSON.

If the JSON data returned in a HTTP response is a JSON array, its elements are
imported as multiple items. If a JSON object is returned, it is imported as one
item.

=head1 SEE ALSO

L<Catmandu::Fix::get_json> provides this importer as fix function.

=encoding utf8
