package Catmandu::Importer::getJSON;
#ABSTRACT: Load JSON-encoded data from a server using a GET HTTP request
#VERSION

use Catmandu::Sane;
use Moo;
use JSON;
use Furl;
use Scalar::Util qw(blessed);
use URI::Template;

with 'Catmandu::Importer';

has url     => ( is => 'rw', trigger => 1 );
has from    => ( is => 'ro' );
has timeout => ( is => 'ro', default => sub { 10 } );
has agent   => ( is => 'ro' );
has proxy   => ( is => 'ro' );
has dry     => ( is => 'ro' );
has headers => ( is => 'ro', default => sub { [ 'Accept' => 'application/json' ] } );
has client  => (
    is => 'ro',
    lazy => 1,
    builder => sub { 
        Furl->new( 
            map { $_ => $_[0]->{$_} } grep { defined $_[0]->{$_} }
            qw(timeout agent proxy),
        ) 
    }
);

has json => (is => 'ro', default => sub { JSON->new->utf8(1) } );

sub _trigger_url {
    my ($self, $url) = @_;

    if (!blessed $url) {
        $url = URI::Template->new($url) unless blessed $url;
    }

    if ($url->isa('URI::Template')) {
        unless ($url->variables) {
            $url = URI->new("$url");
        }
    }

    $self->{url} = $url;
}

sub generator {
    my ($self) = @_;

    if ($self->from) {
        return sub {
            state $done = 0;
            return if $done;
            $done = 1;
            return $self->_query_url($self->from);
        }
    }

    sub {
        state $fh   = $self->fh;
        state $data;

        if ( $data and ref $data eq 'ARRAY' and @$data ) {
            return shift @$data;
        }

        my $line = <$fh> // return;
        my $url = $self->_construct_url($line) // return;

        $data = $self->_query_url($url);

        return (ref $data // '') eq 'ARRAY' ? shift @$data : $data;
    }
}

sub request_hook {
    my ($self, $line) = @_;

    if ($line =~ /^\s*{/) {
        return $self->json->decode($line); 
    } else {
        my $url;

        # plain URL
        if ( $line =~ /^https?:\// ) {
            $url = URI->new($line);
        # URL path (and optional query)
        } elsif ( $line =~ /^\// ) {
            $url = "".$self->url;
            $url =~ s{/$}{}; 
            $line =~ s{\s+$}{};
            $url = URI->new($url . $line);
        }
 
        return $url;
    }
}

sub _construct_url {
    my ($self, $line) = @_;

    chomp $line;
    $line =~ s/^\s+|\s+$//g;

    my $request = $self->request_hook($line);
    my $url;

    # Template or query variables
    if (ref $request and not blessed($request)) {
        $url = $self->url;
        if ($url->isa('URI::Template')) {
            $url = $url->process($request);
        } else {
            $url = $url->clone;
            $url->query_form($request);
        }         
    } else {
        $url = $request;
    }
  
    warn "failed to _construct URL from: '$line'\n" unless $url;

    return $url;
}

sub _query_url {
    my ($self, $url) = @_;

    if ( $self->dry ) {
        return { url => "$url" };
    }

    my $response = $self->client->get($url, $self->headers);
    unless ($response->is_success) {
        warn "request failed: $url\n";
        return;
    }

    my $content = $response->decoded_content;
    my $data    = $self->json->decode($content);

    $self->response_hook($data);
}

sub response_hook { $_[1] }

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

This L<Catmandu::Importer> performs a HTTP GET request to load JSON-encoded
data from a server. The importer expects a line-separated input. Each line
corresponds to a HTTP request that is mapped to a JSON-record on success. The
following input formats are accepted:

=over

=item plain URL

A line that starts with "C<http://>" or "C<https://>" is used as plain URL.

=item URL path

A line that starts with "C</>" is appended to the configured B<url> parameter.

=item variables

A JSON object with variables to be used with an URL template or as HTTP query
parameters. For instance the input line C<< {"name":"Karl Marx"} >> with URL
C<http://api.lobid.org/person> or the input line 
C<< {"entity":"person","name":"Karl Marx"} >> with URL template
C<http://api.lobid.org/{entity}{?id}{?name}{?q}> are both expanded to
L<http://api.lobid.org/person?name=Karl+Marx>.

=back

If the JSON data returned in a HTTP response is a JSON array, its elements are
imported as multiple items. If a JSON object is returned, it is imported as one
item.

=head1 CONFIGURATION

=over

=item url

An L<URI> or an URI templates (L<URI::Template>) as defined by 
L<RFC 6570|http://tools.ietf.org/html/rfc6570> to load JSON from. If no B<url>
is configured, plain URLs must be provided as input or option C<from> must be
used instead.

=item from

A plain URL to load JSON without reading any input lines.

=item timeout / agent / proxy / headers

Optional HTTP client settings.

=item client

Instance of a L<Furl> HTTP client to perform requests with.

=item dry

Don't do any HTTP requests but return URLs that data would be queried from. 

=item file / fh

Input to read lines from (see L<Catmandu::Importer>). Defaults to STDIN.

=item fix

An optional fix to be applied on every item (see L<Catmandu::Fix>).

=back

=head1 EXTENDING

This importer provides two methods to filter requests and responses,
respectively. See L<Catmandu::Importer::Wikidata> for an example.

=head2 request_hook

Gets a whitespace-trimmed input line and is expected to return an unblessed
object or an URL.

=head2 response_hook

Gets the queried response object and is expected to return an object.

=head1 LIMITATIONS

Error handling is very limited.

Future versions of this module may also support asynchronous HTTP fetching
modules such as L<HTTP::Async>, for retrieving multiple URLs at the same time..

=head1 SEE ALSO

L<Catmandu>

=encoding utf8
