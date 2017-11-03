use Renard::Incunabula::Common::Setup;
package Renard::Incunabula::MuPDF::mutool::ObjectParser;
# ABSTRACT: Parser for the output of C<mutool show>

use Moo;
use Renard::Incunabula::Common::Types qw(Str Bool File InstanceOf);

use constant {
	TypeString     => 1,
	TypeNumber     => 2,
	TypeReference  => 3,
	TypeDictionary => 4,
	TypeDate       => 5,
	TypeArray      => 6,
};

has filename => (
	is => 'ro',
	isa => File,
	coerce => 1,
	required => 1,
);

has string => (
	is => 'ro',
	isa => Str,
	required => 1,
);

has is_toplevel => (
	is => 'ro',
	isa => Bool,
	default => sub { 1 },
);

method BUILD(@) {
	$self->_parse;
};

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
			$data->{$+{Key}} = Renard::Incunabula::MuPDF::mutool::ObjectParser->new(
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
		} elsif( $scalar =~ /^\((?<String>.*)\)/ ) {
			my $string = $+{String};
			if( $string =~ /^D:/ ) {
				$self->data( $self->parse_date($string) );
				$self->type($self->TypeDate);
			} else {
				$self->data($self->unescape($string));
				$self->type($self->TypeString);
			}
		} elsif( $scalar =~ /^\[/ ) {
			$self->data('NOT PARSED');
			$self->type($self->TypeArray);
		} else {
			die "unknown type";
		}
	}
}

classmethod unescape((Str) $pdf_string ) {
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

classmethod parse_date( (Str) $date_string ) {
	# § 3.8.3 Dates (pg. 160)
	# (D:YYYYMMDDHHmmSSOHH'mm')
	# where
	my $date_re = qr/
		(?<Prefix>D:)?
		(?<Year> \d{4} )        # YYYY is the year
		(?<Month> \d{2} )?      # MM is the month
		(?<Day> \d{2} )?        # DD is the day (01–31)
		(?<Hour> \d{2} )?       # HH is the hour (00–23)
		(?<Minute> \d{2} )?     # mm is the minute (00–59)
		(?<Second> \d{2} )?     # SS is the second (00–59)
		(?<TzOffset> [-+Z] )?   # O is the relationship of local time
		                        # to Universal Time (UT), denoted by
		                        # one of the characters +, −,
		                        # or Z (see below)
		(?<TzHourW>
			(?<TzHour> \d{2})
			'
		)? # HH followed by ' is the absolute
		   # value of the offset from UT in hours
		   # (00–23)
		(?<TzMinuteW>
			(?<TzMinute> \d{2})
			'
		)? # mm followed by ' is the absolute
		   # value of the offset from UT in
		   # minutes (00–59)
	/x;

	my $time = {};

	die "Not a date string" unless $date_string =~ $date_re;

	$time->{year} = $+{Year};
	$time->{month} = $+{Month} // '01';
	$time->{day} = $+{Day} // '01';

	$time->{hour} = $+{Hour} // '00';
	$time->{minute} = $+{Minute} // '00';
	$time->{second} = $+{Second} // '00';

	if( exists $+{TzOffset} ) {
		$time->{tz}{offset} = $+{TzOffset};
		$time->{tz}{hour} = $+{TzHour} // '00';
		$time->{tz}{minute} = $+{TzMinute} // '00';
	}

	$time;
}

has data => (
	is => 'rw',
);

has type => (
	is => 'rw',
);

method resolve_key( (Str) $key ) {
	return unless $self->type == $self->TypeDictionary
		&& exists $self->data->{$key};

	my $value = $self->data->{$key};

	while( $value->type == $self->TypeReference ) {
		$value = $self->new_from_reference( $value );
	}

	return $value;
}

method new_from_reference( (InstanceOf['Renard::Incunabula::MuPDF::mutool::ObjectParser']) $ref_obj ) {
	return unless $ref_obj->type == $self->TypeReference;
	my $ref_id = $ref_obj->data;
	$self->new(
		filename => $self->filename,
		string => Renard::Incunabula::MuPDF::mutool::get_mutool_get_object_raw($self->filename, $ref_id),
	);
}


1;
