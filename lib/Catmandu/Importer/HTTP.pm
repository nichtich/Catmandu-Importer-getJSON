package Catmandu::Importer::HTTP;
#ABSTRACT: import items via HTTP GET requests
#VERSION

use Catmandu::Sane;
use Moo;
use JSON;
use Furl;
use Scalar::Util qw(blessed);
use URI::Template;

with 'Catmandu::Importer';

has url     => ( is => 'rw', trigger => 1 );
has from    => ( is => 'ro');
has timeout => ( is => 'ro', default => sub { 10 } );
has agent   => ( is => 'ro' );
has proxy   => ( is => 'ro' );
has dry     => ( is => 'ro' );
has headers => ( is => 'ro' );
has wait    => ( is => 'ro' );
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

has time => (is => 'rw');

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
            state $data = do {
                my $r = $self->_query_url($self->from);
                (ref $r // '') eq 'ARRAY' ? $r : [$r];
            };
            return shift @$data;
        }
    }

    sub {
        state $fh = $self->fh;
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

    $self->log->debug($url);

    if ( $self->dry ) {
        return { url => "$url" };
    }

    if ( $self->wait and $self->time ) {
        my $elapsed = ($self->time // time) - time;
        sleep( $self->wait - $elapsed );
    }
    $self->time(time);

    my $response = $self->client->get($url, $self->headers // []);
    unless ($response->is_success) {
        warn "request failed: $url\n";
        return;
    }

    my $data = { 
        code     => $response->code,
        message  => $response->message,
        protocol => $response->protocol,
        headers  => [$response->headers->flatten],
        content  => $response->decoded_content,
    };

    $self->response_hook($data);
}

sub response_hook { $_[1] }

sub parse {
    my ($self, $response) = @_;
    $response;
}

1;

=head1 DESCRIPTION

This L<Catmandu::Importer> performs a HTTP GET request to load items from a
server. See L<Catmandu::Importer::getJSON> and L<Catmandu::Importer::getXML>
for specialized variants that load JSON- or XML-encoded items, respectively. 

The importer expects a line-separated input. Each line corresponds to a HTTP
request that is mapped to a JSON-record on success. The following input formats
are accepted:

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

=head1 CONFIGURATION

=over

=item url

An L<URI> or an URI templates (L<URI::Template>) as defined by 
L<RFC 6570|http://tools.ietf.org/html/rfc6570> to load JSON from. If no B<url>
is configured, plain URLs must be provided as input or option C<from> must be
used instead.

=item from

A plain URL to load from without reading any input lines.

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

=item wait

Number of seconds to wait between requests.

=back

=head1 METHODS

=head2 time

Returns the UNIX timestamp right before the last request. This can be used for
instance to add timestamps or the measure how fast requests were responded.

=head1 EXTENDING

This importer provides two methods to filter requests and responses,
respectively. See L<Catmandu::Importer::Wikidata> for an example.

=head2 request_hook

Gets a whitespace-trimmed input line and is expected to return an unblessed
object or an URL.

=head2 response_hook

Gets the HTTP response in form of a HASH reference as following to transform to
an item:

    {
        protocol => 'HTTP/1.1',
        code     => 200,
        message  => 'Ok',
        headers  => [ key => 'value', key => 'value', ... ],
        content  => '...decoded response content...'
    }

Subclasses should implement their own variant of this method. See
L<Catmandu::Importer::getJSON> and L<Catmandu::Importer::getJSON> for simple
examples.

=head1 LOGGING

URLs are emitted before each request on DEBUG log level.

=head1 LIMITATIONS

Error handling is very limited.

Future versions of this module may also support asynchronous HTTP fetching
modules such as L<HTTP::Async>, for retrieving multiple URLs at the same time.

=encoding utf8
