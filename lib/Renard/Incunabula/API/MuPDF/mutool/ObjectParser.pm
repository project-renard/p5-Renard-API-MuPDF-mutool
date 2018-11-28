use Renard::Incunabula::Common::Setup;
package Renard::Incunabula::API::MuPDF::mutool::ObjectParser;
# ABSTRACT: Parser for the output of C<mutool show>

use Moo;
use Renard::Incunabula::Common::Types qw(Str Bool File InstanceOf);
use Renard::Incunabula::API::MuPDF::mutool::DateObject;
use Encode qw(decode encode_utf8);
use utf8;

=head1 Types

  TypeString
  TypeStringASCII
  TypeStringUTF16BE
  TypeNumber
  TypeBoolean
  TypeReference
  TypeDictionary
  TypeDate
  TypeArray

The listed types are an enum for the kind of datatypes stored in the C<type>
attribute.

=cut
use constant {
	TypeString            => 1,
	TypeStringASCII       => 2,
	TypeStringUTF16BE     => 3,
	TypeNumber            => 4,
	TypeBoolean           => 5,
	TypeReference         => 6,
	TypeDictionary        => 7,
	TypeDate              => 8,
	TypeArray             => 9,
};

=attr filename

A required C<File> attribute that represents the location of the PDF file.

=cut
has filename => (
	is => 'ro',
	isa => File,
	coerce => 1,
	required => 1,
);

=attr string

A required C<Str> attribute that represents the raw string output from
C<mutool show>.

=cut
has string => (
	is => 'ro',
	isa => Str,
	required => 1,
);

=attr is_toplevel

An optional C<Bool> attribute that tells whether the data is top-level or not.
This influences the parsing by removing the header from the C<mutool show>
output.

Default: C<true>

=cut
has is_toplevel => (
	is => 'ro',
	isa => Bool,
	default => sub { 1 },
);

=method BUILD

Initialises the object by parsing the input data.

=cut
method BUILD(@) {
	$self->_parse;
};

=begin comment

=method _parse

A private method that parses the data in the C<string> attribute.

=end comment

=cut
method _parse() {
	my $text = $self->string;
	chomp($text);
	my @lines = split "\n", $text;

	return unless @lines;

	my $id;
	$id = shift @lines if $self->is_toplevel;

	if( $lines[0] eq '<<' ) {
		my $data = {};
		my $line;
		while( ">>" ne ($line = shift @lines)) {
			next unless $line =~ m|^ \s* / (?<Key>\w+) \s+ (?<Value>.*) $|x;
			$data->{$+{Key}} = Renard::Incunabula::API::MuPDF::mutool::ObjectParser->new(
				filename => $self->filename,
				string => $+{Value},
				is_toplevel => 0,
			);
		}

		$self->data( $data );
		$self->type( $self->TypeDictionary );
	} else {
		my $scalar = $lines[0];
		if( $scalar =~ m|^(?<Id>\d+) 0 R$| ) {
			$self->data($+{Id});
			$self->type($self->TypeReference);
		} elsif( $scalar =~ m|^(?<Number>\d+)$| ) {
			$self->data($+{Number});
			$self->type($self->TypeNumber);
		} elsif( $scalar =~ m{^(?<Boolean>/True|/False)$} ) {
			$self->data($+{Boolean} eq '/True');
			$self->type($self->TypeBoolean);
		} elsif( $scalar =~ /^\((?<String>.*)\)/ ) {
			my $string = $+{String};
			if( $string =~ /^D:/ ) {
				$self->data(
					Renard::Incunabula::API::MuPDF::mutool::DateObject->new(
						string => $string
					)
				);
				$self->type($self->TypeDate);
			} else {
				$self->data($self->unescape_ascii_string($string));
				$self->type($self->TypeStringASCII);
			}
		} elsif( $scalar =~ /^<(?<String>\s*FE\s*FF[^>]*)>/ ) {
			$self->data( $self->decode_hex_utf16be( $+{String} ) );
			$self->type($self->TypeStringUTF16BE);
		} elsif( $scalar =~ /^\[/ ) {
			$self->data('NOT PARSED');
			$self->type($self->TypeArray);
		} else {
			die "unknown PDF type: $scalar"; # uncoverable statement
		}
	}
}

=classmethod unescape_ascii_string

  classmethod unescape_ascii_string((Str) $pdf_string )

A class method that unescapes the escape sequences in a PDF string.

Returns a C<Str>.

=cut
classmethod unescape_ascii_string((Str) $pdf_string ) {
	my $new_string = $pdf_string;
	# TABLE 3.2 Escape sequences in literal strings (pg. 54)
	my %map = (
		'n'  => "\n", # Line feed (LF)
		'r'  => "\r", # Carriage return (CR)
		't'  => "\t", # Horizontal tab (HT)
		'b'  => "\b", # Backspace (BS)
		'f'  => "\f", # Form feed (FF)
		'('  => '(',  # Left parenthesis
		')'  => ')',  # Right parenthesis
		'\\' => '\\', # Backslash
	);

	my $escape_re = qr/
		(?<Char> \\ [nrtbf()\\] )
		|
		(?<Octal> \\ \d{1,3}) # \ddd Character code ddd (octal)
	/x;
	$new_string =~ s/$escape_re/
		exists $+{Char}
		?  $map{ substr($+{Char}, 1) }
		: chr(oct(substr($+{Octal}, 1)))
		/eg;

	$new_string;
}

=classmethod decode_hex_utf16be

  classmethod decode_hex_utf16be( (Str) $pdf_string )

A class method that decodes data stored in angle brackets.

Currently only implements Unicode character encoding for what is called a
I<UTF-16BE encoded string with a leading byte order marker> using
B<ASCIIHexDecode>:

=for :list
* first two bytes must be the Unicode byte order marker (C<U+FEFF>),
* one byte per each pair of hex characters (C<< /[0-9A-F]{2}/ >>))
* whitespace is ignored


See the following parts of PDF Reference 1.7:


=for :list
* Section 3.3.1 ASCIIHexDecode Filter (pg. 69) and
* Section 3.8.1 Text String Type (pg. 158)


Returns a C<Str>.

=cut
classmethod decode_hex_utf16be( (Str) $pdf_string ) {
	if( $pdf_string =~ /^FE\s*FF/ ) {
		# it is a UTF-16BE string
		my $string = decode('UTF-16',
			pack(
				'H*',
				# remove strings
				$pdf_string =~ s/\s+//gr
			)
		);

		# This is a text string, so we can enable the UTF8 flag.
		utf8::upgrade($string);

		return $string;
	} else {
		# Possibly PDFDocEncoded string type?
		die "Not a UTF-16BE hex string";
	}
}

=attr data

A C<Str> containing the parsed data.

=cut
has data => (
	is => 'rw',
);

=attr type

Contains the type parsed in the C<data> attribute. See L</Types> for more
information.

=cut
has type => (
	is => 'rw',
);

=method resolve_key

  method resolve_key( (Str) $key )

A method that follows the reference IDs contained in the data for the until a
non-reference type is found.

Returns a C<Renard::Incunabula::API::MuPDF::mutool::ObjectParser> instance.

=cut
method resolve_key( (Str) $key ) {
	return unless $self->type == $self->TypeDictionary
		&& exists $self->data->{$key};

	my $value = $self->data->{$key};

	while( $value->type == $self->TypeReference ) {
		$value = $self->new_from_reference( $value );
	}

	return $value;
}

=method new_from_reference

  method new_from_reference( (InstanceOf['Renard::Incunabula::API::MuPDF::mutool::ObjectParser']) $ref_obj )

Returns an instance of C<Renard::Incunabula::API::MuPDF::mutool::ObjectParser> that
follows the reference ID contained inside C<$ref_obj>.

=cut
method new_from_reference( (InstanceOf['Renard::Incunabula::API::MuPDF::mutool::ObjectParser']) $ref_obj ) {
	return unless $ref_obj->type == $self->TypeReference;
	my $ref_id = $ref_obj->data;
	$self->new(
		filename => $self->filename,
		string => Renard::Incunabula::API::MuPDF::mutool::get_mutool_get_object_raw($self->filename, $ref_id),
	);
}


1;
