package Catmandu::Fix::get_json;
#ABSTRACT: get JSON data from an URL as fix function

use Catmandu::Sane;
use Moo;
use Catmandu::Fix::Has;
use Catmandu::Importer::getJSON;

with "Catmandu::Fix::Base";

has url => (fix_arg => 1);
has path => (fix_opt => 1, default => sub {""});
has dry => (fix_opt => 1);
has importer => (is => 'ro', lazy => 1, builder => 1);

sub _build_importer {
	my $self = shift;
	Catmandu::Importer::getJSON->new(from => $self->url, dry => $self->dry);
}

sub emit {
    my ($self, $fixer) = @_;
    my $path = $fixer->split_path($self->path);
    my $generator_var = $fixer->capture($self->importer->generator);

    $fixer->emit_create_path($fixer->var, $path, sub {
        my $var = shift;
        "${var} = ${generator_var}->();";
    });
}

1;

=head1 SYNOPSIS

	# returns the hash
	get_json("http://example.com/json")

	# stores the in path.key
	get_json("http://example.com/json", path.key)

=cut
