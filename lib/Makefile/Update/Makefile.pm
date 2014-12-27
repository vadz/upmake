package Makefile::Update::Makefile;
# ABSTRACT: Update lists of files in makefile variables.

use Exporter qw(import);
our @EXPORT = qw(update_makefile);

use strict;
use warnings;

# VERSION

=head1 SYNOPSIS

This can be used to update the contents of a variable containing a list of
files in a makefile.

    use Makefile::Update::Makefile;
    Makefile::Update::upmake('GNUmakefile', \&update_makefile, $vars);

=head1 SEE ALSO

Makefile::Update

=cut

=func update_makefile

Update variable definitions in a makefile format with the data from the hash
ref containing all the file lists.

Only most straightforward cases of variable or target definitions are
recognized here, i.e. just "var := value", "var = value" or "target: value".
In particular we don't support any GNU make extensions such as "export" or
"override" without speaking of anything more complex.

On top of it, currently the value should contain a single file per line with
none at all on the first line (but this restriction could be relaxed later if
needed), i.e. the only supported case is

    var = \
          foo \
          bar \
          baz

and it must be followed by an empty line, too.

Notice that if any of the "files" in the variable value looks like a makefile
variable, i.e. has "$(foo)" form, it is ignored by this function, i.e. not
removed even if it doesn't appear in the list of files (which will never be
the case normally).

Takes the (open) file handles of the files to read and to write and the file
lists hash ref as arguments.

Returns 1 if any changes were made.
=cut

sub update_makefile
{
    my ($in, $out, $vars) = @_;

    # Variable whose contents is being currently replaced.
    my $var;

    # Hash with files defined for the specified variable as keys and 0 or 1
    # depending on whether we have seen them in the input file as values.
    my %files;

    # Array of lines in the existing makefile.
    my @values;

    # True if the values are in alphabetical order: we use this to add new
    # entries in alphabetical order too if the existing ones use it, otherwise
    # we just append them at the end.
    my $sorted = 1;

    # Extension of the files in the files list and in the makefile, can be
    # different (e.g. ".cpp" and ".o") and we translate between them then.
    my ($src_ext, $make_ext);

    # Helper to get the extension. Note that the "extension" may be a make
    # variable, e.g. the file could be something like "foo.$(obj)", so don't
    # restrict it to just word characters.
    sub _get_ext { $_[0] =~ /(\.\S+)$/ ? $1 : undef }

    # Indent and the part after the value (typically some amount of spaces and
    # a backslash) for normal lines and, separately, for the last one, as it
    # may or not have backslash after it.
    my ($indent, $tail, $last_tail);

    # Set to 1 if we made any changes.
    my $changed = 0;
    while (defined(my $line = <$in>)) {
        chomp $line;

        # If we're inside the variable definition, parse the current line as
        # another file name,
        if (defined $var) {
            if ($line =~ /^(?<indent>\s*)(?<file>[^ ]+)(?<tail>\s*\\?)$/) {
                if (defined $indent) {
                    warn qq{Inconsistent indent at line $. in the } .
                         qq{definition of the variable "$var".\n"}
                        if $+{indent} ne $indent;
                } else {
                    $indent = $+{indent};
                }

                $last_tail = $+{tail};
                my $file_orig = $+{file};

                $tail = $last_tail if !defined $tail;

                # Check if we have something with the correct extension and
                # preserve unchanged all the rest -- we don't want to remove
                # expansions of other makefile variables from this one, for
                # example, but such expansions would never be in the files
                # list as they don't make sense for the other formats.
                my $file = $file_orig;
                if (defined (my $file_ext = _get_ext($file))) {
                    if (defined $make_ext) {
                        if ($file_ext ne $make_ext) {
                            warn qq{Values of variable "$var" use both } .
                                 qq{"$file_ext" and "$make_ext" extensions.\n};
                        }
                    } else {
                        $make_ext = $file_ext;
                    }

                    if ($file_ext ne $src_ext) {
                        $file =~ s/\Q$file_ext\E$/$src_ext/
                    }

                    if (exists $files{$file}) {
                        if ($files{$file}) {
                            warn qq{Duplicate file "$file" in the definition of the } .
                                 qq{variable "$var" at line $.\n}
                        } else {
                            $files{$file} = 1;
                        }
                    } else {
                        # This file was removed.
                        $changed = 1;

                        # Don't store this line in @values below.
                        next;
                    }
                }

                # Are we still sorted?
                if (@values && lc $line lt $values[-1]) {
                    $sorted = 0;
                }

                push @values, $line;
                next;
            }

            # The variable definition is expected to end with a blank line.
            warn qq{Expected blank line at line $..\n} if $line =~ /\S/;

            # End of variable definition, add new lines.
            my $new_files = 0;
            while (my ($file, $seen) = each(%files)) {
                next if $seen;

                # This file was wasn't present in the input, add it.

                # If this is the first file we add, ensure that the last line
                # present in the makefile so far has the line continuation
                # character at the end as this might not have been the case.
                if (!$new_files) {
                    $new_files = 1;

                    if (@values && $values[-1] !~ /\\$/) {
                        $values[-1] .= $tail;
                    }
                }

                # Next give it the right extension.
                if (defined $make_ext && $make_ext ne $src_ext) {
                    $file =~ s/\Q$src_ext\E$/$make_ext/
                }

                # Finally store it.
                push @values, "$indent$file$tail";
            }

            if ($new_files) {
                $changed = 1;

                # Sort them if necessary using the usual Schwartzian transform.
                if ($sorted) {
                    @values = map { $_->[0] }
                              sort { $a->[1] cmp $b->[1] }
                              map { [$_, lc $_] } @values;
                }

                # Fix up the tail of the last line to be the same as that of
                # the previous last line.
                $values[-1] =~ s/\s*\\$/$last_tail/;
            }

            undef $var;

            print $out join("\n", @values), "\n";
        }

        # We're only interested in variable or target declarations.
        if ($line =~ /^\s*(?<var>\S+)\s*(?::?=|:)(?<tail>.*)/) {
            $var = $+{var};
            my $tail = $+{tail};

            # And only those of them for which we have values, but this is
            # where it gets tricky as we try to be smart to accommodate common
            # use patterns with minimal effort.
            if (!exists $vars->{$var}) {
                # Helper: return name if a variable with such name exists or
                # undef otherwise.
                my $var_if_exists = sub { exists $vars->{$_[0]} ? $_[0] : undef };

                if ($var =~ /^objects$/i || $var =~ /^obj$/i) {
                    # Special case: map it to "sources" as we work with the
                    # source, not object, files.
                    $var = $var_if_exists->('sources');
                } elsif ($var =~ /^(\w+)_(objects|obj|sources|src|headers|hdr)$/i) {
                    $var = $var_if_exists->($1) or $var_if_exists->("$1_sources");
                } elsif ($var =~ /^(\w+)\$\(\w+\)/) {
                    # This one is meant to catch relatively common makefile
                    # constructions like "target$(exe_ext)".
                    $var = $var_if_exists->($1);
                } else {
                    undef $var;
                }
            }

            if (defined $var) {
                if ($tail !~ /\s*\\$/) {
                    warn qq{Unsupported format for variable "$var" at line $..\n};
                    undef $var;
                } else {
                    %files = map { $_ => 0 } @{$vars->{$var}};

                    @values = ();

                    # We assume all files have the same extension (it's not
                    # clear what could we do if this were not the case anyhow).
                    $src_ext = _get_ext(${$vars->{$var}}[0]);

                    # Not known yet.
                    undef $make_ext;

                    undef $indent;
                    $tail = $tail;
                    undef $last_tail;
                }
            }
        }

        print $out "$line\n";
    }

    $changed
}
