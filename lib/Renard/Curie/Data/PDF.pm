use Renard::Curie::Setup;
package Renard::Curie::Data::PDF;
# ABSTRACT: Retrieve PDF image and text data via MuPDF's mutool

use Capture::Tiny qw(capture_stdout tee_stdout);
use XML::Simple;
use Alien::MuPDF 0.005;
use Path::Tiny;
use Function::Parameters;

use Log::Any qw($log);

BEGIN {
	our $MUTOOL_PATH = Alien::MuPDF->mutool_path;
}

=func _call_mutool

  _call_mutool( @args )

Helper function which calls C<mutool> with the contents of the C<@args> array.

Returns the captured C<STDOUT> of the call.

This function dies if C<mutool> unsuccessfully exits.

=cut
fun _call_mutool( @mutool_args ) {
	my @args = ( $Renard::Curie::Data::PDF::MUTOOL_PATH, @mutool_args );
	my ($stdout, $exit);

	# Note: The code below is marked as uncoverable because it only applies
	# on Windows and we are currently only automatically checking coverage
	# on Linux via Travis-CI.
	# uncoverable branch true
	if( $^O eq 'MSWin32' ) {
		# Need to redirect to a file for two reasons:
		# - /SUBSYSTEM:WINDOWS closes stdin/stdout <https://github.com/project-renard/curie/issues/128>.
		# - MuPDF does not set the mode on stdout to binary <http://bugs.ghostscript.com/show_bug.cgi?id=694954>.
		my $temp_fh = File::Temp->new;                       # uncoverable statement
		close $temp_fh; # to avoid Windows file locking      # uncoverable statement

		my $output_param = 0;                                # uncoverable statement
		for my $idx (1..@args-2) {                           # uncoverable statement
			# uncoverable branch true
			if( $args[$idx] eq '-o'                      # uncoverable statement
				&& $args[$idx+1] eq '-' ) {
				$args[$idx+1] = $temp_fh->filename;  # uncoverable statement
				$output_param = 1;                   # uncoverable statement
			}
		}

		# uncoverable branch true
		if( not $output_param ) {                            # uncoverable statement
			# redirect into a temp file
			my $cmd = join " ",                          # uncoverable statement
				map { $_ =~ /\s/ ? "\"$_\"" : $_ }   # uncoverable statement
				@args;                               # uncoverable statement
			my $redir = $temp_fh->filename;              # uncoverable statement
			@args = ("$cmd > \"$redir\"");               # uncoverable statement
		}

		$log->infof("running mutool: %s", \@args);           # uncoverable statement
		system( @args );                                     # uncoverable statement
		$stdout = path( $temp_fh->filename )->slurp_raw;     # uncoverable statement
		$exit = $?;                                          # uncoverable statement
	} else {
		($stdout, $exit) = capture_stdout {
			$log->infof("running mutool: %s", \@args);
			system( @args );
		};
	}

	die "Unexpected mutool exit: $exit" if $exit;

	return $stdout;
}

=func get_mutool_pdf_page_as_png

  get_mutool_pdf_page_as_png($pdf_filename, $pdf_page_no)

This function returns a PNG stream that renders page number C<$pdf_page_no> of
the PDF file C<$pdf_filename>.

=cut
fun get_mutool_pdf_page_as_png($pdf_filename, $pdf_page_no) {
	my $stdout = _call_mutool(
		qw(draw),
		qw( -F png ),
		qw( -o -),
		$pdf_filename,
		$pdf_page_no,
	);

	return $stdout;
}

=func get_mutool_text_stext_raw

  get_mutool_text_stext_raw($pdf_filename, $pdf_page_no)

This function returns an XML string that contains structured text from page
number C<$pdf_page_no> of the PDF file C<$pdf_filename>.

The XML format is defined by the output of C<mutool> looks like this (for page
23 of the C<pdf_reference_1-7.pdf> file):

  <document name="test-data/test-data/PDF/Adobe/pdf_reference_1-7.pdf">
    <page width="531" height="666">
      <block bbox="261.18 616.16394 269.77765 625.2532">
        <line bbox="261.18 616.16394 269.77765 625.2532">
          <span bbox="261.18 616.16394 269.77765 625.2532" font="MyriadPro-Semibold" size="7.98">
            <char bbox="261.18 616.16394 265.50037 625.2532" x="261.18" y="623.2582" c="2"/>
            <char bbox="265.50037 616.16394 269.77765 625.2532" x="265.50037" y="623.2582" c="3"/>
          </span>
        </line>
      </block>
      <block bbox="225.78 88.20229 305.18158 117.93829">
        <line bbox="225.78 88.20229 305.18158 117.93829">
          <span bbox="225.78 88.20229 305.18158 117.93829" font="MyriadPro-Bold" size="24">
            <char bbox="225.78 88.20229 239.5176 117.93829" x="225.78" y="111.93829" c="P"/>
            <char bbox="239.5176 88.20229 248.4552 117.93829" x="239.5176" y="111.93829" c="r"/>
            <char bbox="248.4552 88.20229 261.1128 117.93829" x="248.4552" y="111.93829" c="e"/>
            <char bbox="261.1128 88.20229 269.28238 117.93829" x="261.1128" y="111.93829" c="f"/>
            <char bbox="269.28238 88.20229 281.93997 117.93829" x="269.28238" y="111.93829" c="a"/>
            <char bbox="281.93997 88.20229 292.50958 117.93829" x="281.93997" y="111.93829" c="c"/>
            <char bbox="292.50958 88.20229 305.18158 117.93829" x="292.50958" y="111.93829" c="e"/>
          </span>
        </line>
      </block>
    </page>
  </document>

Simplified, the high-level structure looks like:

  <page> -> [list of blocks]
    <block> -> [list of blocks]
      a block is either:
        - stext
            <line> -> [list of lines] (all have same baseline)
              <span> -> [list of spans] (horizontal spaces over a line)
                <char> -> [list of chars]
        - image
            TODO

=cut
fun get_mutool_text_stext_raw($pdf_filename, $pdf_page_no) {
	my $stdout = _call_mutool(
		qw(draw),
		qw(-F stext),
		qw(-o -),
		$pdf_filename,
		$pdf_page_no,
	);

	return $stdout;
}

=func get_mutool_text_stext_xml

  get_mutool_text_stext_xml($pdf_filename, $pdf_page_no)

Returns a HashRef of the structured text from from page
number C<$pdf_page_no> of the PDF file C<$pdf_filename>.

See the function L<get_mutool_text_stext_raw|/get_mutool_text_stext_raw> for
details on the structure of this data.

=cut
fun get_mutool_text_stext_xml($pdf_filename, $pdf_page_no) {
	my $stext_xml = get_mutool_text_stext_raw(
		$pdf_filename,
		$pdf_page_no,
	);
	# page -> [list of blocks]
	#   block -> [list of blocks]
	#     block is either:
	#       - stext
	#           line -> [list of lines] (all have same baseline)
	#             span -> [list of spans] (horizontal spaces over a line)
	#               char -> [list of chars]
	#       - image
	#           TODO

	my $stext = XMLin( $stext_xml,
		ForceArray => [ qw(page block line span char) ] );

	return $stext;
}

=func get_mutool_page_info_raw

  get_mutool_page_info_raw($pdf_filename)

Returns an XML string of the page bounding boxes of PDF file C<$pdf_filename>.

The data is in the form:

  <document>
    <page pagenum="1">
      <MediaBox l="0" b="0" r="531" t="666" />
      <CropBox l="0" b="0" r="531" t="666" />
      <Rotate v="0" />
    </page>
    <page pagenum="2">
      ...
    </page>
  </document>

=cut
fun get_mutool_page_info_raw($pdf_filename) {
	my $stdout = _call_mutool(
		qw(pages),
		$pdf_filename
	);

	# remove the first line
	$stdout =~ s/^[^\n]*\n//s;

	# wraps the data with a root node
	return "<document>$stdout</document>"
}

=func get_mutool_page_info_xml

  get_mutool_page_info_xml($pdf_filename)

Returns a HashRef containing the page bounding boxes of PDF file
C<$pdf_filename>.

See function L<get_mutool_page_info_raw|/get_mutool_page_info_raw> for
information on the structure of the data.

=cut
fun get_mutool_page_info_xml($pdf_filename) {
	my $page_info_xml = get_mutool_page_info_raw( $pdf_filename );

	my $page_info = XMLin( $page_info_xml,
		ForceArray => [ qw(page) ] );

	return $page_info;
}

=func get_mutool_outline_simple

  fun get_mutool_outline_simple($pdf_filename)

Returns an array of the outline of the PDF file C<$pdf_filename> as an
C<ArrayRef[HashRef]> which corresponds to the C<items> attribute of
L<Renard::Curie::Model::Outline>.

=cut
fun get_mutool_outline_simple($pdf_filename) {
	my $outline_text = _call_mutool(
		qw(show),
		$pdf_filename,
		qw(outline)
	);

	my @outline_items = ();
	open my $outline_fh, '<:encoding(UTF-8):crlf', \$outline_text;
	while( defined( my $line = <$outline_fh> ) ) {
		$line =~ /^(?<indent>\t*)(?<text>.*)\t(?<page>\d+)$/;
		my %copy = %+;
		$copy{level} = length $copy{indent};
		delete $copy{indent};
		push @outline_items, \%copy;
	}

	return \@outline_items;
}


1;
