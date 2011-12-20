#!/usr/bin/perl

use strict;
use File::Slurp;
use Archive::Zip qw( :ERROR_CODES );

my ($csv_input, $docx_input) = @ARGV;

unless ($csv_input =~ /\.csv$/ and $docx_input =~ /\.docx$/) {
    die "Usage: labels <.csv file> <.docx file>\n";
}

# Read the entire Google CSV
my $csv = read_file($csv_input);

# Extract the Word document XML
my $template_file = Archive::Zip->new();
unless ($template_file->read( $docx_input ) == AZ_OK) { 
    die "Couldn't read $docx_input"; 
};
unless ($template_file->extractMemberWithoutPaths(
    "word/document.xml", "/tmp/template.xml") == AZ_OK) 
{ 
    die "Couldn't extract word/document.xml";
}
my $template_xml = read_file('/tmp/template.xml');

# Make sure we have markers to work with
unless ($template_xml =~ /\$\{0\}/) { 
    die "I think you forgot to add markers to the template"; 
}

# Clean out the weird characters that come with a Google CSV
$csv =~ s/[^\w\s\d,"\.\@\-]//g;

# Escape and unquote any quoted fields
$csv =~ s/"([^"]+)"/escape($1)/ge;

my %headers;
my @addresses;
my @lines = split /\r\n/, $csv;

# Compile a list of formatted addresses
foreach (@lines) {
    my @fields = split /,/, $_;
    if (keys %headers) {

        # Name and address
        my $name = $fields[$headers{'Name'}];
        my $address = $fields[$headers{'Address 1 - Formatted'}];
        push @addresses, unescape("$name\r\n$address");
    } 
    else {

        # Read the CSV headers
        my $i = -1;
        %headers = map { $i++; $_ => $i } @fields;
    }
}

my $i = 0;
my $current_xml = $template_xml;
foreach (@addresses) {
    if ($current_xml =~ /\$\{0\}/) {
        # We have remaining space

        # Replace markers ${0} through ${4} with address lines
        my @address_lines = split /\r\n/, $_;
        print "Reading address for $address_lines[0]\n";
        $current_xml =~ s/\$\{0\}/$address_lines[0]/;
        $current_xml =~ s/\$\{1\}/$address_lines[1]/;
        $current_xml =~ s/\$\{2\}/$address_lines[2]/;
        $current_xml =~ s/\$\{3\}/$address_lines[3]/;
        $current_xml =~ s/\$\{4\}/$address_lines[4]/;
    }
    else {

        # Current document is full
        build_document();
        $current_xml = $template_xml;
        $i++;
    }
}
build_document();

sub build_document {
    
    # Discard remaining unused markers and save document XML
    $current_xml =~ s/\$\{\d\}//g;
    write_file("/tmp/template-$i.xml", $current_xml);

    # Create a new .docx file
    $docx_input =~ /^(.+)(\.[^.]+)$/;
    my $filename = "$1-$i$2";
    `cp $docx_input $filename`;

    print "Writing $filename\n";

    # Insert document XML into the new .docx file 
    my $new_doc = Archive::Zip->new();
    unless ($new_doc->read( $filename ) == AZ_OK) { 
        die "Couldn't read $filename"; 
    };
    $new_doc->removeMember("word/document.xml");
    $new_doc->addFile("/tmp/template-$i.xml", "word/document.xml");
    unless ($new_doc->overwrite() == AZ_OK) { 
        die "Couldn't save $filename"; 
    }
}

sub escape {
    my ($value) = @_;   
    $value =~ s/\n/\\n/g;
    $value =~ s/\r/\\r/g;
    $value =~ s/,/\\_/g;
    return $value;
}

sub unescape {
    my ($value) = @_;
    $value =~ s/\\n/\n/g;
    $value =~ s/\\r/\r/g;
    $value =~ s/\\_/,/g;
    return $value;
}
