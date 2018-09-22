package Makefile::Update::Bakefile0;
# ABSTRACT: Update bakefile-0.x files list.

use Exporter qw(import);
our @EXPORT = qw(update_bakefile_0);

use strict;
use warnings;

# VERSION

=head1 SYNOPSIS

This is used exclusively to update wxWidgets C<files.bkl> and is probably not
useful outside of wxWidgets project.

    use Makefile::Update::Bakefile0;
    Makefile::Update::upmake('bakefiles/files.bkl', \&update_bakefile_0, $vars);

=head1 SEE ALSO

Makefile::Update

=cut

=func update_bakefile_0

Update file with variable definitions in bakefile-0 format with the data
from the hash ref containing all the file lists.

Takes the (open) file handles of the files to read and to write and the file
lists hash ref as arguments.

Returns 1 if any changes were made.
=cut

sub update_bakefile_0
{
    my ($in, $out, $vars) = @_;

    # Variable whose contents is being currently replaced.
    my $var;

    # Hash with files defined for the specified variable as keys and 0 or 1
    # depending on whether we have seen them in the input file as values.
    my %files;

    # <if>-related state.
    my ($seen_any_files, $wrapped_in_if, $if_nesting_level, $add_new_files);

    # Set to 1 if we made any changes.
    my $changed = 0;
    while (<$in>) {
        chomp;

        if (/<set var="(\w+)" hints="files">/ && exists $vars->{$1}) {
            $var = $1;
            %files = map { $_ => 0 } @{$vars->{$var}};
            $seen_any_files = 0;
            $if_nesting_level = 0;
            $add_new_files = 0;
        } elsif (defined $var) {
            local $_ = $_;
            s/<!-- .* -->//;
            s/^\s+//;
            s/\s+$//;

            # We need to handle <if>...</if> inside the files list if only
            # because we need to insert any newly added files before the final
            # </if>.
            if (m{<if [^>]+>}) {
                if (!$seen_any_files) {
                    # Remember that the closing tag will be </if>, not </set>.
                    $wrapped_in_if = 1
                }

                $if_nesting_level++;
            } elsif (m{</if>}) {
                if (!--$if_nesting_level && $wrapped_in_if) {
                    # We need to add any new files here, before the last
                    # </if> as otherwise they would end up outside of it.
                    $add_new_files = 1;
                }
            } elsif (m{</set>}) {
                # Note that if we're in the $wrapped_in_if case, then this had
                # already been done and $var was undefined, so we don't do it
                # twice.
                $add_new_files = 1
            } elsif ($_) {
                if (not exists $files{$_}) {
                    # This file was removed.
                    $changed = 1;
                    next;
                }

                if ($files{$_}) {
                    warn qq{Duplicate file "$_" in the definition of the } .
                         qq{variable "$var" at line $.\n}
                } else {
                    $files{$_} = 1;
                }
            }
        }

        if ($add_new_files) {
            # Check if we have any new files.
            #
            # TODO Insert them in alphabetical order.
            while (my ($file, $seen) = each(%files)) {
                if (!$seen) {
                    # This file was wasn't present in the input, add it.
                    # TODO Use proper indentation.
                    print $out "    $file\n";

                    $changed = 1;
                }
            }

            undef $var;
            $add_new_files = 0
        }

        print $out "$_\n";
    }

    $changed
}
