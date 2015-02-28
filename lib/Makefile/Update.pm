package Makefile::Update;

# ABSTRACT: Update make files.

use strict;
use warnings;
use autodie;

use Exporter qw(import);

our @EXPORT = qw(read_files_list upmake);

# VERSION

=head1 SYNOPSIS

    use Makefile::Update;
    my $vars = read_files_list('files.lst');
    upmake('foo.vcxproj', $vars->{sources}, $vars->{headers});

=cut

=func read_files_list

Reads the file containing the file lists definitions and returns a hash ref
with variable names as keys and refs to arrays of the file names as values.

Takes an (open) file handle as argument.

The file contents is supposed to have the following very simple format:

    # Comments are allowed and ignored.
    #
    # The variable definitions must always be in the format shown below,
    # i.e. whitespace is significant and there should always be a single
    # file per line.
    sources =
        file1.cpp
        file2.cpp

    headers =
        file1.h
        file2.h

    # It is also possible to define variables in terms of other variables
    # defined before it in the file (no forward references):
    everything =
        $sources
        $headers
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
            if (/^\$(\w+)$/) {
                my $name = $1;
                die qq{Reference to undefined variable "$name" in the } .
                    qq{assignment to "$var" at line $.\n}
                    unless exists $vars{$name};
                my $value = $vars{$name};
                push @{$vars{$var}}, $_ for @$value;
            } else {
                push @{$vars{$var}}, $_;
            }
        }
    }

    return \%vars;
}

=func upmake

Update a file in place using the specified function and passing it the rest of
the arguments.

The first parameter is either just the file path or a hash reference which may
contain the following keys:

=over

=item C<file>

The path to the file to be updated, required.

=item C<verbose>

If true, give more messages about what is being done.

=item C<quiet>

If true, don't output any non-error messages.

=item C<dryrun>

If true, don't really update the file but just output whether it would have
been updated or not. If C<verbose> is also true, also output the diff of the
changes that would have been done.

=back

This is meant to be used with C<update_xxx()> defined in different
Makefile::Update::Xxx modules.

Returns 1 if the file was changed or 0 otherwise.
=cut

sub upmake
{
    my $file_or_options = shift;
    my ($updater, @args) = @_;

    my ($fname, $verbose, $quiet, $dryrun);
    if (ref $file_or_options eq 'HASH') {
        $fname = $file_or_options->{file};
        $verbose = $file_or_options->{verbose};
        $quiet = $file_or_options->{quiet};
        $dryrun = $file_or_options->{dryrun};
    } else {
        $fname = $file_or_options;
        $verbose =
        $quiet =
        $dryrun = 0;
    }

    if ($dryrun) {
        my $old = do {
            local $/;
            open my $f, '<', $fname;
            <$f>
        };
        my $new = '';

        open my $in, '<', \$old;
        open my $out, '>', \$new;

        if ($updater->($in, $out, @args)) {
            print qq{Would update "$fname"};

            if ($verbose) {
                if (eval { require Text::Diff; }) {
                    print " with the following changes:\n";

                    print Text::Diff::diff(\$old, \$new, {
                                FILENAME_A => $fname,
                                FILENAME_B => "$fname.new"
                            });
                } else {
                    print ".\n";

                    warn qq{Can't display diff of the changes, please install Text::Diff module.\n};
                }
            } else {
                print ".\n";
            }
        } else {
            print qq{Wouldn't change the file "$fname".\n};
        }

        return 0;
    }

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

    if ($changed) {
        print qq{File "$fname" successfully updated.\n} unless $quiet;
        return 1;
    } else {
        print qq{No changes in the file "$fname".\n} if $verbose;
        return 0;
    }
}

1;
