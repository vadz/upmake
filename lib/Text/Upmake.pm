package Text::Upmake;

# ABSTRACT: Update make files.

use strict;
use warnings;
use autodie;

use Exporter qw(import);

our @EXPORT = qw(read_files_list upmake);

# VERSION

=head1 SYNOPSIS

    use Text::Upmake;
    my $vars = read_files_list('files.lst');
    upmake('foo.vcxproj', $vars->{sources}, $vars->{headers});

=cut

=func read_files_list

Reads the file containing the file lists definitions and returns a hash ref
with variable names as keys and refs to arrays of the file names as values.

Takes an (open) file handle as argument.

The file contents is supposed to have the following very simple format:

    # Comments are allowed and ignored.
    sources =
        file1.cpp
        file2.cpp

    headers =
        file1.h
        file2.h
=cut

sub read_files_list
{
    my ($fh) = @_;

    my ($var, %vars);
    while (<$fh>) {
        chomp;
        s/#.*$//;
        s/^\s+//;
        s/\s+$//;
        next if !$_;

        if (/^(\w+)\s*=$/) {
            $var = $1;
        } else {
            die "Unexpected contents outside variable definition at line $.\n"
                unless defined $var;
            push @{$vars{$var}}, $_;
        }
    }

    return \%vars;
}

=func upmake

Update the file with the given name in place using the specified function and
passing it the rest of the arguments.

This is meant to be used with C<update_xxx()> defined in different
Text::Upmake::Xxx modules.
=cut

sub upmake
{
    my ($fname, $updater, @args) = @_;

    my $fname_new = "$fname.upmake.new"; # TODO make it more unique

    open my $in, '<', $fname;
    open my $out, '>', $fname_new;

    my $changed = $updater->($in, $out, @args);

    close $in;
    close $out;

    if ($changed) {
        rename $fname_new, $fname;
    } else {
        unlink $fname_new;
    }

    $changed
}

1;
