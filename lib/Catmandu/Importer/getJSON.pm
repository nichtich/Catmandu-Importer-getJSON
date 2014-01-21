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

has timeout => ( is => 'ro', default => sub { 10 } );
has agent   => ( is => 'ro' );
has proxy   => ( is => 'ro' );
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
    sub {
        state $fh   = $self->fh;
        state $data;

        if ( $data and ref $data eq 'ARRAY' and @$data ) {
            return shift @$data;
        }

        my $line = <$fh> // return;
        my $url = $self->construct_url($line) // return;

        my $response = $self->client->get($url, $self->headers);
        unless ($response->is_success) {
            warn "request failed: $url\n";
            return;
        }

        my $content = $response->decoded_content;

        $data = $self->json->decode($content);

        return (ref $data // '') eq 'ARRAY' ? shift @$data : $data;
    }
}

sub construct_url {
    my ($self, $line) = @_;
    chomp $line;

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
    # Template or query variables
    } else { 
        my $vars = $self->json->decode($line); 
        $url = $self->url;
        if ($url->isa('URI::Template')) {
            $url = $url->process($vars);
        } else {
            $url = $url->clone;
            $url->query_form( $vars );

        }
    }
   
    warn "failed to construct URL from: '$line'\n" unless $url;

    return $url;
}

1;

=head1 DESCRIPTION

This L<Catmandu::Importer> performs a HTTP GET request to load JSON-encoded
data from a server. Each input line corresponds to a HTTP request. The
following input formats are accepted:

=over

=item plain URL

A line that starts with "http://" or "https://" is used as URL as given.

=item URL path

A line that starts with "/" is appended to the configured url parameter.

=item variables

A JSON object with variables to be used with an URL Template or as HTTP query
parameters.

=back

If the HTTP response is a JSON array, its elements are returned as items.

=head1 CONFIGURATION

=over

=item url

An URL to load from. Can be an L<URI> or an URI templates (L<URI::Template>) as
defined by L<http://tools.ietf.org/html/rfc6570|RFC 6570>. If no URL is
configured, the URL must be provided from input.

=item timeout

=item agent

=item proxy

Optional HTTP client settings.

=item client

Instance of L<Furl> to do HTTP requests with. Future versions of this module
may also support other HTTP fetching modules, such as L<HTTP::Async> for
asynchronous requests.

=item file

=item fh

Input to read lines from (see L<Catmandu::Importer>). Defaults to STDIN.

=item fix

An optional fix to be applied on every item (see L<Catmandu::Fix>).

=back

=head1 TODO

Error handling!

=encoding utf8
